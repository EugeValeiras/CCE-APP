import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../utils/verb_labels.dart';

/// CCE#100 — El MODO y las ESCENAS propias de una luz, en un widget que se
/// monta en las DOS pantallas de luz de la app.
///
/// Vive acá y no dentro de una pantalla porque el review encontró que el UI se
/// había agregado sólo a `LightDetailSheet`, que se abre ÚNICAMENTE con un
/// long-press en el floor plan del teléfono: tocar la luz en la lista, en una
/// card destacada o en el floor plan de tablet abre `LightColorScreen`, y por
/// ahí la feature no existía. Duplicar el bloque en las dos pantallas habría
/// dejado dos copias que se desincronizan; esto es una sola.
///
/// Se colapsa a nada (`SizedBox.shrink`) cuando el device no tiene modos ni
/// escenas, así que montarlo en una pantalla compartida con luces Hue no cuesta
/// nada.
class LightModeScenesSection extends StatefulWidget {
  final Device device;
  final DevicesService service;

  /// `true` en pantallas apretadas (el editor de color): tipografía y
  /// espaciados más chicos, y el aviso del brillo en escena se omite.
  final bool compact;

  const LightModeScenesSection({
    super.key,
    required this.device,
    required this.service,
    this.compact = false,
  });

  @override
  State<LightModeScenesSection> createState() => _LightModeScenesSectionState();
}

class _LightModeScenesSectionState extends State<LightModeScenesSection> {
  bool _saving = false;

  /// La escena que se está borrando ahora (su chip se atenúa), o null.
  String? _removingId;

  Device get _d => widget.device;

  List<String> get _modes => _d.state.lightModes ?? const [];
  List<LightScene> get _scenes => _d.state.lightScenes ?? const [];
  bool get _hasScenes => (_d.capabilities).contains('scene');

  /// Nombre de la escena puesta, o por qué no hay uno. En modo escena SIN id la
  /// puso la app del fabricante y CCE todavía no la capturó: decirlo es más
  /// útil que un guión.
  String get _activeSceneName {
    final id = _d.state.sceneId;
    if (id != null) {
      for (final sc in _scenes) {
        if (sc.id == id) return sc.name;
      }
    }
    return _d.state.mode == 'scene' ? 'Sin guardar' : '—';
  }

  /// Pide el nombre y guarda lo que la luz tiene puesto AHORA. El backend
  /// decide si eso es el payload de la escena o el color vigente.
  Future<void> _askSceneName() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.surface,
        title: const Text('Guardar como escena'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre de la escena'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.service.captureLightScene(_d, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Escena «$name» guardada')),
      );
    } catch (e) {
      if (!mounted) return;
      // El backend da el motivo real (sin estado local, ni escena ni color).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// CCE#110 — Borra una escena capturada. Siempre pregunta: es irreversible
  /// (la captura depende de cómo estaba la luz en ese momento) y una
  /// automatización que la ponga va a fallar al ejecutarse.
  ///
  /// Cancelar no llama a la API. El service quita la escena del estado del
  /// device EN EL LUGAR (sin `refresh()`, que dejaría huérfano a
  /// `widget.device`), así que la grilla se redibuja sola. Un fallo se muestra
  /// con el motivo del backend; no hay aviso de éxito sobre un borrado que no
  /// ocurrió.
  Future<void> _confirmRemove(LightScene sc) async {
    HapticFeedback.mediumImpact();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.surface,
        title: Text('Borrar «${sc.name}»'),
        content: const Text(
          'No se puede deshacer: la captura depende de cómo estaba la luz en '
          'ese momento. Si una automatización pone esta escena, va a fallar '
          'al ejecutarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: CceColors.danger),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _removingId = sc.id);
    try {
      await widget.service.removeLightScene(sc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Escena «${sc.name}» borrada')),
      );
    } catch (e) {
      if (!mounted) return;
      // El motivo real del backend («Escena X no encontrada»).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se redibuja con el estado del device: el eco del backend llega por WS.
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        // Con un solo modo no hay nada que elegir, y sin capability de escena
        // no hay nada que guardar: el widget desaparece.
        final mostrarModo = _modes.length > 1;
        if (!mostrarModo && !_hasScenes) return const SizedBox.shrink();

        final gap = widget.compact ? 12.0 : 24.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mostrarModo) ...[
              _Label('Modo',
                  trailing: lightModeLabel(_d.state.mode ?? ''),
                  compact: widget.compact),
              SizedBox(height: widget.compact ? 6 : 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _modes)
                    LightChoiceChip(
                      label: lightModeLabel(m),
                      icon: lightModeIcon(m),
                      selected: _d.state.mode == m,
                      compact: widget.compact,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.service.setLightMode(_d, m);
                      },
                    ),
                ],
              ),
              // La consecuencia real de que este producto no tenga DP de
              // brillo. En compacto se omite: la pantalla no tiene lugar y el
              // dato está en el sheet.
              if (_d.state.mode == 'scene' && !widget.compact)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'En escena el brillo y el color los pone la escena. '
                    'Si movés el brillo, la luz pasa a modo Color con el '
                    'color que tiene.',
                    style: TextStyle(
                        color: CceColors.textTertiary,
                        fontSize: 12,
                        height: 1.35),
                  ),
                ),
              SizedBox(height: gap),
            ],
            if (_hasScenes) ...[
              _Label('Escenas',
                  trailing: _activeSceneName, compact: widget.compact),
              SizedBox(height: widget.compact ? 6 : 10),
              if (_scenes.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sc in _scenes)
                      Opacity(
                        opacity: _removingId == sc.id ? 0.4 : 1,
                        child: LightChoiceChip(
                          label: sc.name,
                          // El ícono que le puso el dueño; el default sólo si
                          // no hay (antes se parseaba y no se renderizaba
                          // nunca).
                          icon: sc.icon ?? '🎨',
                          selected: _d.state.sceneId == sc.id,
                          compact: widget.compact,
                          onTap: () {
                            if (_removingId != null) return;
                            HapticFeedback.selectionClick();
                            widget.service.setLightScene(_d, sc.id);
                          },
                          // CCE#110 — mantener apretado borra (con
                          // confirmación). El chip no tiene lugar para una
                          // cruz y es el gesto de la app para lo destructivo.
                          onLongPress: _removingId == null
                              ? () => _confirmRemove(sc)
                              : null,
                        ),
                      ),
                  ],
                )
              else
                Text(
                  widget.compact
                      ? 'Todavía no hay ninguna guardada.'
                      : 'Todavía no hay ninguna guardada. Dejá la luz como la '
                          'querés —el color, o la escena que le pusiste desde '
                          'la app del fabricante— y guardala acá con un nombre.',
                  style: const TextStyle(
                      color: CceColors.textTertiary,
                      fontSize: 12,
                      height: 1.35),
                ),
              if (_scenes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Mantené apretada una escena para borrarla.',
                    style: TextStyle(
                        color: CceColors.textTertiary,
                        fontSize: widget.compact ? 11 : 12,
                        height: 1.35),
                  ),
                ),
              SizedBox(height: widget.compact ? 4 : 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _askSceneName,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(_saving ? 'Guardando…' : 'Guardar como escena'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Rótulo de sección con su valor a la derecha (el mismo formato que el resto
/// del sheet de la luz).
class _Label extends StatelessWidget {
  final String text;
  final String? trailing;
  final bool compact;
  const _Label(this.text, {this.trailing, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text.toUpperCase(),
          style: compact
              ? CceText.section.copyWith(fontSize: 11)
              : CceText.section,
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: CceColors.textPrimary,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// Chip de un selector: marca el valor PUESTO. Sin el estado de selección los
/// chips de modo y de escena se ven todos iguales y no se sabe dónde está la
/// luz.
class LightChoiceChip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  /// CCE#110 — opcional: qué hacer al mantener apretado (borrar, en las
  /// escenas). Sin él, el chip sólo responde al toque.
  final VoidCallback? onLongPress;

  const LightChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.compact = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final h = compact ? 7.0 : 10.0;
    final w = compact ? 10.0 : 14.0;
    return Material(
      color: selected
          ? CceColors.accent.withValues(alpha: 0.18)
          : CceColors.surfaceHigh,
      borderRadius: BorderRadius.circular(CceRadii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(CceRadii.control),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: w, vertical: h),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.control),
                  border: Border.all(color: CceColors.accent),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null && icon!.isNotEmpty) ...[
                Text(icon!, style: TextStyle(fontSize: compact ? 12 : 14)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? CceColors.accent : CceColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
