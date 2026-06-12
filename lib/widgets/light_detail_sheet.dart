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

  Color _currentColor() {
    final s = widget.device.state;
    if (s.hue != null && s.sat != null) {
      final h = (s.hue! / 65535) * 360.0;
      final sat = (s.sat! / 254).clamp(0.0, 1.0);
      return HSVColor.fromAHSV(1.0, h, sat, 1.0).toColor();
    }
    return Colors.amber;
  }

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
