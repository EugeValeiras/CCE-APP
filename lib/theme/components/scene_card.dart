import 'package:flutter/material.dart';

import '../cce_tokens.dart';
import 'status_pill.dart';

/// Card de escena (Hue nativa o CCE), réplica del formato Hue: card OSCURA
/// fija de 132 con un CÍRCULO de color centrado (gradiente del swatch, o
/// círculo cálido con el ícono para escenas CCE) y el nombre DEBAJO.
/// Activa = borde blanco sutil + check arriba a la derecha (la card NO se
/// tiñe entera). Badge "auto" para smart scenes y spinner sobre el círculo
/// mientras se aplica.
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
  final bool active; // borde blanco + check
  final bool isSmart; // badge "auto"
  final bool busy; // spinner mientras aplica
  final VoidCallback onTap;

  static const double _height = 132;
  static const double _circle = 60;

  /// Ajusta la luminosidad HSL de [c] en [delta] (conserva hue/saturación).
  static Color _shiftL(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  Widget _buildCircle() {
    final hasSwatch = colors.isNotEmpty;
    // Con 1 solo color el gradiente le da profundidad (claro arriba a la
    // izquierda, oscuro abajo a la derecha); multi-color usa el swatch tal
    // cual. Siempre colores REALES saturados, NO pastel.
    final gradientColors = colors.length == 1
        ? [
            _shiftL(colors.first, 0.10),
            colors.first,
            _shiftL(colors.first, -0.08),
          ]
        : colors;

    final circle = Container(
      width: _circle,
      height: _circle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // El círculo lleva los colores REALES saturados (como Hue);
        // el pastel es solo para cards de luces/habitaciones.
        color: hasSwatch ? null : CceColors.warm,
        gradient: hasSwatch
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors.take(5).toList(),
              )
            : null,
      ),
      child: !hasSwatch && icon != null
          ? IconTheme.merge(
              data: const IconThemeData(
                color: Color(0xFF211B10),
                size: 24,
              ),
              child: Center(child: icon!),
            )
          : null,
    );

    if (!busy) return circle;
    return Stack(
      alignment: Alignment.center,
      children: [
        circle,
        Container(
          width: _circle,
          height: _circle,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x66000000),
          ),
        ),
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(CceRadii.hueScene);

    return SizedBox(
      height: _height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CceColors.cardOffHigh,
          borderRadius: borderRadius,
          border: active
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.85), width: 1.4)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                    child: Column(
                      children: [
                        _buildCircle(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              height: 1.15,
                              color: CceColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSmart)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: StatusPill(
                      label: 'auto',
                      color: Color(0x52000000),
                    ),
                  ),
                if (active && !busy)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.white,
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
