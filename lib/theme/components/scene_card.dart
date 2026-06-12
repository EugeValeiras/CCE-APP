import 'package:flutter/material.dart';

import '../cce_tokens.dart';
import 'status_pill.dart';

/// Card de escena (Hue nativa o CCE): altura FIJA 100, gradiente horizontal
/// con el swatch de colores (o surfaceHigh si no hay), borde accent + check
/// cuando esta activa, badge "auto" para smart scenes y spinner mientras
/// se aplica.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.name,
    this.colors = const <Color>[],
    this.icon,
    this.active = false,
    this.isSmart = false,
    this.busy = false,
    required this.onTap,
  });

  final String name;
  final List<Color> colors; // swatch hasta 5 (HueScene.colors)
  final Widget? icon; // para CceScene (icon name -> MdiIcons)
  final bool active; // borde accent + check
  final bool isSmart; // badge "auto"
  final bool busy; // spinner mientras aplica
  final VoidCallback onTap;

  static const double _height = 100;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(CceRadii.tile);
    final hasSwatch = colors.isNotEmpty;
    final gradientColors =
        colors.length == 1 ? [colors.first, colors.first] : colors;

    return SizedBox(
      height: _height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasSwatch ? null : CceColors.surfaceHigh,
          gradient: hasSwatch
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: gradientColors,
                )
              : null,
          borderRadius: borderRadius,
          border: active
              ? Border.all(color: CceColors.accent, width: 2)
              : Border.all(color: CceColors.stroke),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              children: [
                // Scrim inferior para legibilidad del nombre sobre el swatch.
                if (hasSwatch)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.42),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (icon != null)
                            IconTheme.merge(
                              data: const IconThemeData(
                                color: CceColors.textPrimary,
                                size: 20,
                              ),
                              child: icon!,
                            ),
                          const Spacer(),
                          if (isSmart)
                            const StatusPill(
                              label: 'auto',
                              color: Color(0x52000000),
                            ),
                          if (busy) ...[
                            const SizedBox(width: 6),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ] else if (active) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: CceColors.accent,
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: CceColors.textPrimary,
                          shadows: [
                            Shadow(color: Color(0x66000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
