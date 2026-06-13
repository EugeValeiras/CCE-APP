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
    this.neo = false,
  });

  final T value;
  final List<CceSegment<T>> segments;
  final ValueChanged<T> onChanged;

  /// Opt-in neumórfico (solo el TABLET lo activa). Default `false` preserva
  /// el render flat actual byte a byte (el phone NO lo pasa).
  final bool neo;

  @override
  Widget build(BuildContext context) {
    final count = segments.length;
    var selectedIndex = segments.indexWhere((s) => s.value == value);
    if (selectedIndex < 0) selectedIndex = 0;

    // Track exterior: carril hundido (neo) o pill surfaceHigh flat (default).
    // El `color` opaco neoBase es obligatorio para que el inset se vea.
    final trackDecoration = neo
        ? BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
          )
        : BoxDecoration(
            color: CceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(CceRadii.pill),
          );

    // Thumb activo: relieve raised (neo) o surface + borde hairline (default).
    final thumbDecoration = neo
        ? BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: CceShadows.neo(blur: 8, offset: 3),
          )
        : BoxDecoration(
            color: CceColors.surface,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            border: Border.all(color: CceColors.stroke),
          );

    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: trackDecoration,
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
                  decoration: thumbDecoration,
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
