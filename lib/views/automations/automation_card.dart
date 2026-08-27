import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
import '../../theme/mdi.dart';
import '../../utils/time_format.dart';
import 'automation_phrases.dart';

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
/// Un valor "parece id de ícono" si es ascii kebab/snake (nunca un emoji).
bool _looksLikeIconId(String s) =>
    RegExp(r'^[a-z0-9][a-z0-9:_-]*$').hasMatch(s.toLowerCase());

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
    // Logos de marca del catálogo del Dashboard.
    if (raw == 'jbl-logo') {
      return CceIcon(CceIcons.jbl, size: size, color: color);
    }
    if (raw == 'samsung-logo') {
      return CceIcon(CceIcons.samsung, size: size, color: color);
    }
    // Glifos propios del catálogo del Dashboard (no existen en MDI).
    if (raw == 'dial-switch') {
      return CceIcon(CceIcons.dialSwitchGlyph, size: size, color: color);
    }
    if (raw == 'dimmer-switch') {
      return CceIcon(CceIcons.dimmerSwitchGlyph, size: size, color: color);
    }
    // Id del catálogo (kebab ascii: 'lamp', 'dial-switch', 'ceiling-light'…):
    // se resuelve por el set MDI vendoreado. SIN esto se caía al branch de
    // emoji y el id se dibujaba como TEXTO ("lamp", "dial-switch").
    if (_looksLikeIconId(raw)) {
      final data = _mdiFromString(raw);
      if (data != null) return Icon(data, size: size, color: color);
      // Id desconocido: genérico, JAMÁS el id como texto.
      return CceIcon(CceIcons.automations, size: size, color: color);
    }
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
/// frase "trigger → acción" en una línea (con pill de condición), y abajo el
/// metadato temporal en cifras tabulares ("Próxima hoy 19:04", "Se ejecutó
/// hace 12 min"). UN solo control: el switch de enabled. Ejecutar ahora vive
/// en el menú de long-press, junto con editar/duplicar/eliminar.
///
/// Desactivada se ATENÚA además de mudarse de sección: antes se veía idéntica
/// a una activa, sólo que en otra lista.
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

  /// Alto de la card: 12 + fila de 44 + 8 + metadato 17 + 12, con aire.
  /// Medida de componente (como `RoomCard.kHeight`).
  static const double kHeight = 96;

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

  /// Metadato temporal: la próxima ejecución si está programada a hora fija;
  /// si no, cuándo se ejecutó por última vez. Vacío si no hay nada que decir
  /// (la línea igual reserva su alto: todas las cards miden lo mismo).
  String _meta() {
    final a = widget.automation;
    final last = widget.lastExecuted;
    final now = DateTime.now();
    if (last != null && now.difference(last).inSeconds < 60) {
      return 'Se ejecutó ahora';
    }
    if (a.enabled) {
      final next = nextScheduleRun(a.trigger, now: now);
      if (next != null) return 'Próxima ${TimeFormat.upcoming(next, now: now)}';
    }
    if (last != null) {
      return 'Se ejecutó ${TimeFormat.relativeInSentence(last, now: now)}';
    }
    return '';
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
    final enabled = a.enabled;

    Widget body;
    if (widget.confirmingDelete) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              '¿Eliminar "${a.name}"?',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CceText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: widget.onCancelDelete,
            child: const Text('Cancelar',
                style: TextStyle(color: CceColors.textSecondary)),
          ),
          SizedBox(width: CceSpace.xs),
          FilledButton(
            onPressed: widget.onConfirmDelete,
            style: FilledButton.styleFrom(
              backgroundColor: CceColors.danger,
              foregroundColor: CceColors.textPrimary,
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
            style: CceText.headline.copyWith(
              color: enabled ? CceColors.textPrimary : CceColors.textSecondary,
            ),
          ),
          SizedBox(height: CceSpace.xs),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${triggerPhrase(a, widget.devices)} → '
                  '${actionsPhrase(a, widget.devices)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.caption.copyWith(
                    color: enabled
                        ? CceColors.textSecondary
                        : CceColors.textTertiary,
                  ),
                ),
              ),
              if (cond.isNotEmpty) ...[
                SizedBox(width: CceSpace.sm),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: CceSpace.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: CceColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(CceRadii.pill),
                  ),
                  child: Text(
                    cond,
                    style: CceText.section.copyWith(letterSpacing: 0),
                  ),
                ),
              ],
            ],
          ),
        ],
      );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Desactivada: el círculo pierde el color del trigger y el
              // glyph cae a terciario.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? color.withValues(alpha: 0.18)
                      : CceColors.surfaceHigh,
                ),
                child: automationIcon(a.icon,
                    size: 22,
                    color: enabled ? color : CceColors.textTertiary),
              ),
              SizedBox(width: CceSpace.md),
              Expanded(child: texts),
              SizedBox(width: CceSpace.sm),
              // CceSwitch, no Switch.adaptive: en iOS `adaptive` cae al
              // CupertinoSwitch verde e ignora el switchTheme, así que este
              // era el único control de la app fuera de la paleta.
              CceSwitch(
                value: a.enabled,
                onChanged: widget.onToggleEnabled,
              ),
            ],
          ),
          Text(
            _meta(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CceText.dataCaption,
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
            padding: EdgeInsets.fromLTRB(
                CceSpace.lg, CceSpace.md, CceSpace.md, CceSpace.md),
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
