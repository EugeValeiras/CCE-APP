import 'dart:math';
import 'package:flutter/material.dart';

class SplashView extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashView({super.key, required this.onComplete});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late AnimationController _lightController;
  late AnimationController _textController;
  late List<Animation<double>> _lightAnimations;

  @override
  void initState() {
    super.initState();

    _lightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat(reverse: true);

    final random = Random(42);
    _lightAnimations = List.generate(5, (i) {
      final delay = random.nextDouble() * 20;
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 10 + delay),
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 30 - delay),
      ]).animate(_lightController);
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _lightController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final buildingWidth = isTablet ? 520.0 : 320.0;
    final buildingHeight = isTablet ? 163.0 : 100.0;
    return Scaffold(
      backgroundColor: const Color(0xFF1B3A6B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: buildingWidth,
              height: buildingHeight,
              child: AnimatedBuilder(
                animation: _lightController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _BuildingPainter(
                      lightValues: _lightAnimations.map((a) => a.value).toList(),
                    ),
                    size: Size(buildingWidth, buildingHeight),
                  );
                },
              ),
            ),
            SizedBox(height: isTablet ? 48 : 32),
            AnimatedBuilder(
              animation: _textController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + _textController.value * 0.5,
                  child: Text(
                    'Preparando tu hogar...',
                    style: TextStyle(
                      color: const Color(0xFF8BACC8),
                      fontSize: isTablet ? 26 : 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildingPainter extends CustomPainter {
  final List<double> lightValues;

  _BuildingPainter({required this.lightValues});

  // SVG building bounds: x 348..1699, y 947..1100 → 1351 x 153
  static const _svgLeft = 348.0;
  static const _svgTop = 947.0;
  static const _svgWidth = 1351.0;
  static const _svgHeight = 153.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale SVG coords to fit widget width, center vertically
    final scale = size.width / _svgWidth;
    final scaledH = _svgHeight * scale;
    final yOffset = (size.height - scaledH) / 2;

    canvas.save();
    canvas.translate(0, yOffset);
    canvas.scale(scale);
    canvas.translate(-_svgLeft, -_svgTop);

    final paint = Paint()..color = const Color(0xFFD0ECF6);

    // Roof — exact SVG path: translate(467,947) "m0 0h1111l13 1 1 2v18l-1 1h-1125l-1-1v-20z"
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
    canvas.drawPath(roof, paint);

    // Left block — translate(479,975) "m0 0h883l24 1v123l-2 1h-1035l-1-1v-120l1-3z"
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
    canvas.drawPath(leftBlock, paint);

    // Right block — translate(1465,975) "m0 0h122l112 1v123l-2 1h-249l-1-1-1-10v-112l1-1z"
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
    canvas.drawPath(rightBlock, paint);

    // Wall lights at 5 positions along the building
    final lightXPositions = [550.0, 800.0, 1050.0, 1300.0, 1570.0];
    const lightY = 1037.0;

    for (var i = 0; i < lightXPositions.length && i < lightValues.length; i++) {
      final opacity = lightValues[i];
      if (opacity <= 0.01) continue;

      final x = lightXPositions[i];

      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, opacity),
            Color.fromRGBO(255, 226, 122, opacity * 0.85),
            Color.fromRGBO(255, 192, 64, opacity * 0.45),
            Color.fromRGBO(255, 168, 32, opacity * 0.15),
            Color.fromRGBO(255, 149, 0, 0),
          ],
          stops: const [0.0, 0.1, 0.25, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x, lightY), radius: 58));

      // Bidirectional wall light (bowtie shape)
      final lightPath = Path()
        ..moveTo(x - 38, lightY - 58)
        ..lineTo(x + 38, lightY - 58)
        ..lineTo(x + 2, lightY)
        ..lineTo(x + 38, lightY + 58)
        ..lineTo(x - 38, lightY + 58)
        ..lineTo(x - 2, lightY)
        ..close();

      canvas.drawPath(lightPath, glowPaint);

      paint.color = Color.fromRGBO(255, 255, 255, opacity);
      canvas.drawCircle(Offset(x, lightY), 3.5, paint);
    }

    // Reset paint color for next frame
    paint.color = const Color(0xFFD0ECF6);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BuildingPainter oldDelegate) => true;
}
