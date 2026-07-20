import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/mdi.dart';
import '../../utils/time_format.dart';
import 'automation_phrases.dart';
import 'run_automation.dart';

/// Color por tipo de trigger.
Color triggerColor(Automation a) {
  switch (a.trigger.type) {
    case 'sensor':
      return CceColors.triggerSensor;
    case 'schedule':
      return CceColors.triggerSchedule;
    default:
      return CceColors.triggerManual;
  }
}

/// Ícono del trigger (para el círculo de la card).
Widget triggerIcon(Automation a, {double size = 20, Color? color}) {
  switch (a.trigger.type) {
    case 'sensor':
      return CceIcon(CceIcons.sensors, size: size, color: color);
    case 'schedule':
      return CceIcon(CceIcons.clock, size: size, color: color);
    default:
      return CceIcon(CceIcons.handTap, size: size, color: color);
  }
}

/// Render del ícono configurado de una automation. La API documenta
/// `mdi:*`, `icons0:*` y emoji literal; NO existe resolver runtime de
/// icons0, así que ese prefijo cae al fallback (rayo).
/// [customIcons] = mapa 'icons0:<prefix>:<name>' → SVG que el Dashboard
/// guarda en la config; sin él los favoritos icons0 caen al rayo genérico.
Widget automationIcon(String? icon,
    {double size = 24,
    Color? color,
    Map<String, String> customIcons = const {}}) {
  final raw = icon?.trim() ?? '';
  if (raw.startsWith('mdi:') || raw.startsWith('mdi-')) {
    final data = _mdiFromString(raw.substring(4));
    if (data != null) return Icon(data, size: size, color: color);
    return CceIcon(CceIcons.automations, size: size, color: color);
  }
  if (raw.startsWith('icons0:')) {
    // SVG vendoreado por el Dashboard.
    final svg = customIcons[raw];
    if (svg != null && svg.contains('<svg')) {
      return SvgPicture.string(
        svg,
        width: size,
        height: size,
        colorFilter: color != null
            ? ColorFilter.mode(color, BlendMode.srcIn)
            : null,
      );
    }
    // icons0:mdi:<name> sin SVG cacheado → resolver por el catálogo MDI.
    final parts = raw.split(':');
    if (parts.length >= 3 && parts[1] == 'mdi') {
      final data = _mdiFromString(parts.sublist(2).join(':'));
      if (data != null) return Icon(data, size: size, color: color);
    }
    return CceIcon(CceIcons.automations, size: size, color: color);
  }
  if (raw.isNotEmpty) {
    // Emoji literal.
    return Text(
      raw,
      style: TextStyle(fontSize: size * 0.84, height: 1.0),
      textAlign: TextAlign.center,
    );
  }
  return CceIcon(CceIcons.automations, size: size, color: color);
}

/// kebab-case → camelCase → Mdi.byName (patrón de scenes_section).
IconData? _mdiFromString(String name) {
  final lower = name.toLowerCase();
  final parts = lower.split('-').where((p) => p.isNotEmpty).toList();
  final camel = parts.isEmpty
      ? lower
      : parts.first +
          parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  return Mdi.byName[camel];
}

/// Card de automatización: ícono 44 en círculo color-de-trigger, nombre,
/// frase trigger → acciones, pill de condición, "Última vez", switch de
/// enabled y botón ▶ de prueba. Glow del color del trigger al ejecutarse.
class AutomationCard extends StatefulWidget {
  const AutomationCard({
    super.key,
    required this.automation,
    required this.service,
    required this.devices,
    this.lastExecuted,
    this.confirmingDelete = false,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleEnabled,
    required this.onConfirmDelete,
    required this.onCancelDelete,
  });

  final Automation automation;
  final AutomationsService service;
  final DevicesService devices;
  final DateTime? lastExecuted;

  /// true = la card muestra la confirmación inline de borrado.
  final bool confirmingDelete;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onConfirmDelete;
  final VoidCallback onCancelDelete;

  @override
  State<AutomationCard> createState() => _AutomationCardState();
}

class _AutomationCardState extends State<AutomationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _glow.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(AutomationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ts = widget.lastExecuted;
    if (ts != null &&
        ts != oldWidget.lastExecuted &&
        DateTime.now().difference(ts).inSeconds < 10) {
      // Glow fade-out 1.8 s easeOut al ejecutarse.
      _glow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  String _line2() {
    final a = widget.automation;
    final last = widget.lastExecuted;
    if (last != null && DateTime.now().difference(last).inSeconds < 60) {
      final s = DateTime.now().difference(last).inSeconds;
      return 'Ejecutada hace $s s';
    }
    return '${triggerPhrase(a, widget.devices)} → '
        '${actionsPhrase(a, widget.devices)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.automation;
    final color = triggerColor(a);
    // 1 → 0 con easeOut (forward del controller = fade del glow).
    final glowT = _glow.isAnimating || _glow.value > 0
        ? 1.0 - Curves.easeOut.transform(_glow.value)
        : 0.0;

    final cond = conditionsPhrase(a, widget.devices);
    final last = widget.lastExecuted;

    Widget body;
    if (widget.confirmingDelete) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              '¿Eliminar "${a.name}"?',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CceColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.onCancelDelete,
            child: const Text('Cancelar',
                style: TextStyle(color: CceColors.textSecondary)),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: widget.onConfirmDelete,
            style: FilledButton.styleFrom(
              backgroundColor: CceColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      );
    } else {
      final texts = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            a.name.isEmpty ? 'Sin nombre' : a.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  _line2(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: CceColors.textSecondary, fontSize: 13),
                ),
              ),
              if (cond.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: CceColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(CceRadii.pill),
                  ),
                  child: Text(
                    cond,
                    style: const TextStyle(
                        color: CceColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 3),
            Text(
              'Última vez: ${TimeFormat.relative(last)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: CceColors.textTertiary, fontSize: 11),
            ),
          ],
        ],
      );

      body = Row(
        children: [
          Opacity(
            opacity: a.enabled ? 1 : 0.45,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: automationIcon(a.icon, size: 22, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(opacity: a.enabled ? 1 : 0.45, child: texts),
          ),
          const SizedBox(width: 4),
          Opacity(
            opacity: a.enabled ? 1 : 0.45,
            child: RunAutomationButton(
              automation: a,
              service: widget.service,
              compact: true,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 48,
            height: 48,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Switch.adaptive(
                value: a.enabled,
                onChanged: widget.onToggleEnabled,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CceRadii.tile),
        border: glowT > 0.01
            ? Border.all(color: color.withValues(alpha: glowT), width: 2)
            : null,
        boxShadow: glowT > 0.01
            ? [
                for (final s in CceShadows.glowOn(color))
                  BoxShadow(
                    color: s.color.withValues(
                        alpha: ((s.color.a) * glowT).clamp(0.0, 1.0).toDouble()),
                    blurRadius: s.blurRadius,
                    offset: s.offset,
                    spreadRadius: s.spreadRadius,
                  ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          CceCard(
            radius: CceRadii.tile,
            neo: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            onTap: widget.confirmingDelete ? null : widget.onTap,
            onLongPress: widget.confirmingDelete ? null : widget.onLongPress,
            child: body,
          ),
          // Borde izquierdo interior 3 px del color del trigger (enabled).
          if (a.enabled && !widget.confirmingDelete)
            Positioned(
              left: 0,
              top: 14,
              bottom: 14,
              child: IgnorePointer(
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
