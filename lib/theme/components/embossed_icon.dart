import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Ícono "goma" neumórfico: el glyph sobresale del fondo (sin contenedor) con
/// un realce tenue arriba-izquierda y una sombra abajo-derecha. Universal:
/// funciona con [Icon] de Material y con SVG ([CceIcon]) tintando dos copias
/// desplazadas y desenfocadas detrás del ícono real.
///
/// El [child] NO debe fijar su propio color (déjelo tomar el [IconTheme]); el
/// [color] de este widget controla el tinte real y los fantasmas.
class EmbossedIcon extends StatelessWidget {
  const EmbossedIcon({
    super.key,
    required this.child,
    required this.color,
    this.size = 23,
  });

  final Widget child;
  final Color color;
  final double size;

  Widget _ghost(Color c, Offset off, double blur) => Transform.translate(
        offset: off,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(c, BlendMode.srcATop),
            child: IconTheme.merge(
              data: IconThemeData(color: c, size: size),
              child: child,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Sombra que proyecta el ícono hacia abajo-derecha (relieve).
          _ghost(const Color(0xCC05060A), const Offset(1.3, 2.2), 2.0),
          // Realce arriba-izquierda (luz neumórfica).
          _ghost(const Color(0x1FFFFFFF), const Offset(-1.1, -1.4), 1.1),
          // Ícono real, con su color.
          IconTheme.merge(
            data: IconThemeData(color: color, size: size),
            child: child,
          ),
        ],
      ),
    );
  }
}
