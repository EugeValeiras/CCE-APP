import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Fill de color desde abajo proporcional al brillo, estilo Hue.
class LightCard extends StatelessWidget {
  const LightCard({
    super.key,
    required this.name,
    required this.icon,
    required this.on,
    this.brightness,
    this.color,
    this.reachable = true,
    this.stateLabel,
    this.height = 180,
    this.onMorePressed,
  });

  final String name;
  final Widget icon;
  final bool on;
  final double? brightness; // 0..1 -> CceGradients.lightFill
  final Color? color; // color real de la luz (default CceColors.warm)
  final bool reachable;
  final String? stateLabel; // '80%' | 'Apagada'
  final double height;
  final VoidCallback? onMorePressed;

  @override
  Widget build(BuildContext context) {
    final fillColor = color ?? CceColors.warm;
    final double b = (brightness ?? 0.0).clamp(0.0, 1.0).toDouble();
    final showFill = on && b > 0;

    // Contraste: texto oscuro si el fill es claro y cubre la zona del nombre.
    final darkText =
        showFill && b > 0.45 && fillColor.computeLuminance() > 0.55;
    final fg = darkText ? const Color(0xFF22150A) : CceColors.textPrimary;
    final fgSub = darkText ? const Color(0xB322150A) : CceColors.textSecondary;

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CceColors.surface,
          borderRadius: BorderRadius.circular(CceRadii.tile),
          border: Border.all(color: CceColors.stroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showFill)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: CceGradients.lightFill(
                    fillColor.withValues(alpha: 0.92),
                    b,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconTheme.merge(
                          data: IconThemeData(
                            color: on ? fillColor : CceColors.textTertiary,
                            size: 26,
                          ),
                          child: icon,
                        ),
                      ),
                      const Spacer(),
                      if (!reachable)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 6),
                          child: Icon(
                            Icons.wifi_off,
                            size: 18,
                            color: CceColors.textTertiary,
                          ),
                        ),
                      if (onMorePressed != null)
                        IconButton(
                          onPressed: onMorePressed,
                          icon: Icon(Icons.more_horiz, color: fgSub),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: fg,
                    ),
                  ),
                  if (stateLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stateLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption.copyWith(color: fgSub),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
