import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Card base del design system: superficie redondeada con gradiente o color
/// plano, borde hairline opcional y soporte de tap/long-press con ripple.
class CceCard extends StatelessWidget {
  const CceCard({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.radius = CceRadii.card,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.onLongPress,
    this.border = false,
  });

  final Widget child;
  final Gradient? gradient;
  final Color? color; // default CceColors.surface
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? CceColors.surface) : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: border ? Border.all(color: CceColors.stroke) : null,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null && onLongPress == null) {
      return Container(decoration: decoration, child: content);
    }

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          child: content,
        ),
      ),
    );
  }
}
