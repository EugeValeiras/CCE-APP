import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/device.dart';
import '../models/color_preset.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/brightness_slider.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';
import '../utils/verb_labels.dart';

class LightDetailSheet extends StatefulWidget {
  final Device device;
  final DevicesService service;

  const LightDetailSheet({super.key, required this.device, required this.service});

  @override
  State<LightDetailSheet> createState() => _LightDetailSheetState();
}

class _LightDetailSheetState extends State<LightDetailSheet> {
  late double _bri;
  late Color _color;
  Timer? _colorDebounce;

  @override
  void initState() {
    super.initState();
    final s = widget.device.state;
    _bri = s.bri.toDouble();
    _color = _currentColor();
  }

  // Si isWhite, r.color ya es el blanco real (ctToWhiteColor): mejor seed
  // para el picker que un amber fijo.
  Color _currentColor() => resolveLightColor(widget.device.state).color;

  @override
  void dispose() {
    _colorDebounce?.cancel();
    super.dispose();
  }

  void _onColorChanged(Color c) {
    setState(() => _color = c);
    _colorDebounce?.cancel();
    _colorDebounce = Timer(const Duration(milliseconds: 250), () {
      final hsv = HSVColor.fromColor(c);
      final cceHue = ((hsv.hue / 360) * 65535).round().clamp(0, 65535);
      final cceSat = (hsv.saturation * 254).round().clamp(0, 254);
      widget.service.setColor(widget.device, hue: cceHue, sat: cceSat);
    });
  }

  void _applyPreset(ColorPreset p) {
    HapticFeedback.selectionClick();
    setState(() => _color = p.color);
    widget.service.setColor(widget.device, hue: p.hue, sat: p.sat);
  }

  void _commitBrightness() {
    widget.service.setBrightness(widget.device, _bri.round());
  }

  // ── CCE#100 — Escenas propias de la luz ───────────────────────────────────

  bool _saving = false;

  /// Nombre de la escena puesta, o por qué no hay uno. En modo escena SIN id la
  /// puso la app del fabricante y CCE todavía no la capturó: decirlo es más
  /// útil que un guión.
  String _activeSceneName(Device d) {
    final id = d.state.sceneId;
    if (id != null) {
      for (final sc in d.state.lightScenes ?? const <LightScene>[]) {
        if (sc.id == id) return sc.name;
      }
    }
    return d.state.mode == 'scene' ? 'Sin guardar' : '—';
  }

  /// Pide el nombre y guarda lo que la luz tiene puesto AHORA. El backend
  /// decide si eso es el payload de la escena o el color vigente.
  Future<void> _askSceneName(Device d) async {
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
      await widget.service.captureLightScene(d, name);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final d = widget.device;
        final presets = widget.service.colorPresets;
        final icon = IconResolver.resolve(d, configuredIcon: widget.service.iconFor(d.id), displayName: widget.service.displayName(d));

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: CceColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: CceColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: d.state.on ? _color.withValues(alpha: 0.28) : CceColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(CceRadii.control),
                          border: Border.all(
                            color: d.state.on ? _color : CceColors.stroke,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(icon, color: d.state.on ? Colors.white : CceColors.textTertiary, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.service.displayName(d),
                              style: CceText.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.type,
                              style: CceText.caption.copyWith(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: d.state.on,
                        onChanged: (_) => widget.service.toggleLight(d),
                        activeThumbColor: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // Brightness slider
                  if (d.supportsBrightness) ...[
                    _SectionLabel('Brillo', trailing: '${((_bri / 254) * 100).round()}%'),
                    const SizedBox(height: 10),
                    CceBrightnessSlider(
                      value: (_bri / 254).clamp(0.0, 1.0).toDouble(),
                      activeColor: d.supportsColor ? _color : null,
                      onChanged: (v) => setState(() => _bri = v * 254),
                      onChangeEnd: (v) {
                        _bri = v * 254;
                        _commitBrightness();
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  // Color presets
                  if (presets.isNotEmpty && d.supportsColor) ...[
                    const _SectionLabel('Presets'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: presets.map((p) => _PresetChip(preset: p, onTap: () => _applyPreset(p))).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Color picker
                  if (d.supportsColor) ...[
                    const _SectionLabel('Color'),
                    const SizedBox(height: 12),
                    Center(
                      child: HueRingPicker(
                        pickerColor: _color,
                        enableAlpha: false,
                        displayThumbColor: true,
                        onColorChanged: _onColorChanged,
                        portraitOnly: true,
                        colorPickerHeight: 220,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // CT slider (tunable white)
                  if (d.supportsCT && !d.supportsColor) ...[
                    const _SectionLabel('Temperatura'),
                    const SizedBox(height: 6),
                    _CtSlider(
                      initialCt: d.state.ct ?? 350,
                      onCommit: (v) => widget.service.setCt(d, v),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // CCE#100 — MODO de la luz (Tuya work_mode). Sólo con más de
                  // un modo: con uno solo no hay nada que elegir. Los modos son
                  // del PRODUCTO, así que los dos Hexagon ofrecen lo mismo estén
                  // en el modo que estén.
                  if ((d.state.lightModes ?? const []).length > 1) ...[
                    _SectionLabel('Modo',
                        trailing: lightModeLabel(d.state.mode ?? '')),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in d.state.lightModes!)
                          _ChoiceChip(
                            label: lightModeLabel(m),
                            selected: d.state.mode == m,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.service.setLightMode(d, m);
                            },
                          ),
                      ],
                    ),
                    if (d.state.mode == 'scene')
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
                    const SizedBox(height: 24),
                  ],
                  // CCE#100 — Las escenas PROPIAS del aparato, guardadas en CCE
                  // con su payload: el firmware no expone un catálogo.
                  if (d.capabilities.contains('scene')) ...[
                    _SectionLabel('Escenas', trailing: _activeSceneName(d)),
                    const SizedBox(height: 10),
                    if ((d.state.lightScenes ?? const []).isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sc in d.state.lightScenes!)
                            _ChoiceChip(
                              label: sc.name,
                              selected: d.state.sceneId == sc.id,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.service.setLightScene(d, sc.id);
                              },
                            ),
                        ],
                      )
                    else
                      const Text(
                        'Todavía no hay ninguna guardada. Dejá la luz como la '
                        'querés —el color, o la escena que le pusiste desde la '
                        'app del fabricante— y guardala acá con un nombre.',
                        style: TextStyle(
                            color: CceColors.textTertiary,
                            fontSize: 12,
                            height: 1.35),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : () => _askSceneName(d),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: Text(_saving ? 'Guardando…' : 'Guardar como escena'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const _SectionLabel(this.text, {this.trailing});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text.toUpperCase(),
          style: CceText.section,
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// CCE#100 — Chip de un selector: marca el valor PUESTO. Sin el estado de
/// selección los chips de modo y de escena se ven todos iguales y no se sabe
/// dónde está la luz.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? CceColors.accent.withValues(alpha: 0.18)
          : CceColors.surfaceHigh,
      borderRadius: BorderRadius.circular(CceRadii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(CceRadii.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.control),
                  border: Border.all(color: CceColors.accent),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? CceColors.accent : CceColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final ColorPreset preset;
  final VoidCallback onTap;
  const _PresetChip({required this.preset, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: preset.color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: preset.color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: preset.color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            Text(
              preset.name,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtSlider extends StatefulWidget {
  final int initialCt;
  final ValueChanged<int> onCommit;
  const _CtSlider({required this.initialCt, required this.onCommit});
  @override
  State<_CtSlider> createState() => _CtSliderState();
}

class _CtSliderState extends State<_CtSlider> {
  late double _ct;
  @override
  void initState() {
    super.initState();
    _ct = widget.initialCt.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 14,
        thumbColor: Colors.white,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            colors: [Color(0xFFBBDEFB), Colors.white, Color(0xFFFFCC80)],
          ),
        ),
        padding: EdgeInsets.zero,
        child: Slider(
          min: 153,
          max: 500,
          value: _ct.clamp(153, 500),
          onChanged: (v) => setState(() => _ct = v),
          onChangeEnd: (v) => widget.onCommit(v.round()),
        ),
      ),
    );
  }
}
