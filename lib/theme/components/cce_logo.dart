import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Logo de CCE (la silueta del edificio del splash) en clave NEUMÓRFICA: el
/// edificio cálido se ve extruido del fondo (realce de luz arriba-izquierda +
/// sombra abajo-derecha, con los tokens neo) y conserva un par de ventanas
/// encendidas cálidas como sello de marca. Versión estática (sin animación),
/// pensada para el header del home.
class CceLogo extends StatelessWidget {
  const CceLogo({super.key, this.height = 22, this.color = _brand});

  /// Tono cálido de la marca (mismo que el edificio del splash).
  static const Color _brand = Color(0xFFEFD9BD);

  final double height;
  final Color color;

  // Relación de aspecto del bounding box SVG del edificio (1351 x 153).
  static const double _aspect = 1351 / 153;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * _aspect,
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(painter: _CceLogoPainter(color: color)),
      ),
    );
  }
}

class _CceLogoPainter extends CustomPainter {
  _CceLogoPainter({required this.color});

  final Color color;

  // Bounding box del edificio en coords SVG (igual que el splash).
  static const double _svgLeft = 348;
  static const double _svgTop = 947;
  static const double _svgWidth = 1351;

  Path _buildingPath() {
    final roof = Path()
      ..moveTo(467, 947)
      ..lineTo(1578, 947)
      ..lineTo(1591, 948)
      ..lineTo(1592, 950)
      ..lineTo(1592, 968)
      ..lineTo(1591, 969)
      ..lineTo(466, 969)
      ..lineTo(465, 968)
      ..lineTo(465, 948)
      ..close();
    final leftBlock = Path()
      ..moveTo(479, 975)
      ..lineTo(1362, 975)
      ..lineTo(1386, 976)
      ..lineTo(1386, 1099)
      ..lineTo(1384, 1100)
      ..lineTo(349, 1100)
      ..lineTo(348, 1099)
      ..lineTo(348, 979)
      ..lineTo(349, 976)
      ..close();
    final rightBlock = Path()
      ..moveTo(1465, 975)
      ..lineTo(1587, 975)
      ..lineTo(1699, 976)
      ..lineTo(1699, 1099)
      ..lineTo(1697, 1100)
      ..lineTo(1448, 1100)
      ..lineTo(1447, 1099)
      ..lineTo(1446, 1089)
      ..lineTo(1446, 977)
      ..lineTo(1447, 976)
      ..close();
    return Path()
      ..addPath(roof, Offset.zero)
      ..addPath(leftBlock, Offset.zero)
      ..addPath(rightBlock, Offset.zero);
  }

  void _drawBuilding(Canvas canvas, Size size, Offset pxOffset, Paint paint) {
    canvas.save();
    canvas.translate(pxOffset.dx, pxOffset.dy);
    final scale = size.width / _svgWidth;
    canvas.scale(scale);
    canvas.translate(-_svgLeft, -_svgTop);
    canvas.drawPath(_buildingPath(), paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Relieve neumórfico: sombra (abajo-derecha) + realce (arriba-izquierda) +
    // cara cálida de la marca encima. Offsets en px lógicos, sutiles.
    _drawBuilding(canvas, size, const Offset(1.4, 2.0),
        Paint()..color = CceColors.neoDark.withValues(alpha: 0.9));
    _drawBuilding(canvas, size, const Offset(-1.1, -1.5),
        Paint()..color = CceColors.neoLight.withValues(alpha: 0.85));
    _drawBuilding(canvas, size, Offset.zero, Paint()..color = color);

    // Ventanas encendidas (estáticas) como sello de marca.
    final scale = size.width / _svgWidth;
    const lit = [550.0, 1050.0, 1570.0];
    const lightY = 1037.0;
    for (final x in lit) {
      final c = Offset((x - _svgLeft) * scale, (lightY - _svgTop) * scale);
      canvas.drawCircle(
        c,
        size.height * 0.06,
        Paint()
          ..color = const Color(0xFFFFC766)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      canvas.drawCircle(
          c, size.height * 0.028, Paint()..color = const Color(0xFFFFF2D0));
    }
  }

  @override
  bool shouldRepaint(_CceLogoPainter oldDelegate) => oldDelegate.color != color;
}
