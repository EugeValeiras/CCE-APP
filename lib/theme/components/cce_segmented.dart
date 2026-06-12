import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Segmento de [CceSegmented].
class CceSegment<T> {
  const CceSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final Widget? icon;
}

/// Control segmentado estilo Hue: pill surfaceHigh con thumb animado
/// surface + borde hairline.
class CceSegmented<T> extends StatelessWidget {
  const CceSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<CceSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final count = segments.length;
    var selectedIndex = segments.indexWhere((s) => s.value == value);
    if (selectedIndex < 0) selectedIndex = 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.pill),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth =
              count > 0 ? constraints.maxWidth / count : constraints.maxWidth;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: segmentWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CceColors.surface,
                    borderRadius: BorderRadius.circular(CceRadii.pill),
                    border: Border.all(color: CceColors.stroke),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(segments[i].value),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (segments[i].icon != null) ...[
                                IconTheme.merge(
                                  data: IconThemeData(
                                    size: 16,
                                    color: i == selectedIndex
                                        ? CceColors.textPrimary
                                        : CceColors.textTertiary,
                                  ),
                                  child: segments[i].icon!,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                segments[i].label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: i == selectedIndex
                                      ? CceColors.textPrimary
                                      : CceColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
