import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Slider de brillo estilo Hue: track grueso redondeado (pill) con fill
/// proporcional. [value] en 0..1 — el caller garantiza no-NaN.
class CceBrightnessSlider extends StatelessWidget {
  const CceBrightnessSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.height = 44,
  });

  final double value; // 0..1
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fill = activeColor ?? CceColors.warm;
    final double v = value.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          double valueFor(Offset local) {
            if (width <= 0) return v;
            return (local.dx / width).clamp(0.0, 1.0).toDouble();
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onChanged(valueFor(d.localPosition)),
            onTapUp: (d) => onChangeEnd?.call(valueFor(d.localPosition)),
            onHorizontalDragStart: (d) => onChanged(valueFor(d.localPosition)),
            onHorizontalDragUpdate: (d) => onChanged(valueFor(d.localPosition)),
            onHorizontalDragEnd: (d) =>
                onChangeEnd?.call(valueFor(d.localPosition)),
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
                      widthFactor: v <= 0 ? 0.0 : v.clamp(0.06, 1.0).toDouble(),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(fill, Colors.white, 0.18) ?? fill,
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
                          height: height * 0.45,
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
          );
        },
      ),
    );
  }
}
