import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_tokens.dart';

/// Slider de brillo estilo Hue: track grueso redondeado (pill) con fill
/// proporcional. [value] en 0..1 — el caller garantiza no-NaN.
///
/// Stateful: durante el drag muestra un readout "NN%" sobre el extremo del
/// fill ([showPercent]) y dispara haptics (lightImpact al tocar 0%/100%,
/// selectionClick al soltar). Solo reclama gestos horizontales y tap, para
/// no robar el scroll vertical de las listas que lo contienen.
class CceBrightnessSlider extends StatefulWidget {
  const CceBrightnessSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.height = 44,
    this.showPercent = true,
  });

  final double value; // 0..1
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor; // default CceColors.warm
  final double height;
  final bool showPercent;

  @override
  State<CceBrightnessSlider> createState() => _CceBrightnessSliderState();
}

class _CceBrightnessSliderState extends State<CceBrightnessSlider> {
  bool _dragging = false;
  double _dragValue = 0;
  bool _edgeHapticFired = false;

  void _emit(double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0.0 || clamped >= 1.0) {
      if (!_edgeHapticFired) {
        HapticFeedback.lightImpact();
        _edgeHapticFired = true;
      }
    } else {
      _edgeHapticFired = false;
    }
    setState(() => _dragValue = clamped);
    widget.onChanged(clamped);
  }

  void _end(double v) {
    final clamped = v.clamp(0.0, 1.0).toDouble();
    HapticFeedback.selectionClick();
    widget.onChangeEnd?.call(clamped);
    if (mounted) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.activeColor ?? CceColors.warm;
    final double v =
        (_dragging ? _dragValue : widget.value).clamp(0.0, 1.0).toDouble();

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          double valueFor(Offset local) {
            if (width <= 0) return v;
            return (local.dx / width).clamp(0.0, 1.0).toDouble();
          }

          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
                (recognizer) => recognizer
                  ..onStart = (d) {
                    setState(() => _dragging = true);
                    _emit(valueFor(d.localPosition));
                  }
                  // OJO: cuerpos con bloque, no flecha — un `=> _emit(...)`
                  // seguido de `..onEnd` cascadea sobre el void de _emit.
                  ..onUpdate = (d) {
                    _emit(valueFor(d.localPosition));
                  }
                  ..onEnd = (d) {
                    _end(_dragValue);
                  }
                  ..onCancel = () {
                    if (mounted) setState(() => _dragging = false);
                  },
              ),
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(),
                (recognizer) => recognizer
                  ..onTapDown = (d) {
                    setState(() => _dragging = true);
                    _emit(valueFor(d.localPosition));
                  }
                  ..onTapUp = (d) {
                    final tapped = valueFor(d.localPosition);
                    _emit(tapped);
                    _end(tapped);
                  }
                  ..onTapCancel = () {
                    // El drag horizontal ganó el arena: su onStart re-marca
                    // _dragging; acá no se toca nada para evitar parpadeo.
                  },
              ),
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(CceRadii.pill),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Track
                        const ColoredBox(color: CceColors.surfaceHigh),
                        // Fill
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor:
                                v <= 0 ? 0.0 : v.clamp(0.06, 1.0).toDouble(),
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color.lerp(fill, Colors.white, 0.18) ??
                                        fill,
                                    fill,
                                  ],
                                ),
                                borderRadius:
                                    BorderRadius.circular(CceRadii.pill),
                              ),
                            ),
                          ),
                        ),
                        // Handle (barrita vertical cerca del borde del fill)
                        if (v > 0)
                          Align(
                            alignment:
                                Alignment(-1.0 + 2.0 * v.clamp(0.06, 1.0), 0),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                width: 4,
                                height: widget.height * 0.45,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Readout "NN%" sobre el extremo del fill durante el drag.
                if (widget.showPercent && width > 72)
                  Positioned(
                    left: (v * width - 46)
                        .clamp(4.0, width - 50.0)
                        .toDouble(),
                    top: (widget.height - 28) / 2,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _dragging ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                CceColors.surfaceHigh.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(CceRadii.pill),
                          ),
                          child: Text(
                            '${(v * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: CceColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
