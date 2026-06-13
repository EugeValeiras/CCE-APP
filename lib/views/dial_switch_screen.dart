import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';

/// Pantalla del switch multi-botón (Hue Tap Dial / remote de 4 botones), al
/// estilo de la app de Hue: un dial redondo dividido en cuadrantes. Tocar un
/// cuadrante simula la pulsación (key 0) y dispara la acción configurada en el
/// backend; mantener presionado simula long-press (key 2). Girar la rueda es
/// físico (ajusta el brillo de los targets server-side).
class DialSwitchScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  const DialSwitchScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<DialSwitchScreen> createState() => _DialSwitchScreenState();
}

class _DialSwitchScreenState extends State<DialSwitchScreen> {
  int? _pressed; // outlet con feedback activo
  String? _feedback; // 'Click' / 'Mantenido'
  Timer? _fbTimer;

  @override
  void dispose() {
    _fbTimer?.cancel();
    super.dispose();
  }

  Future<void> _press(int outlet, int key) async {
    HapticFeedback.selectionClick();
    setState(() {
      _pressed = outlet;
      _feedback = key == 2 ? 'Mantenido' : 'Click';
    });
    _fbTimer?.cancel();
    _fbTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _pressed = null);
    });
    final ok =
        await widget.service.simulateButton(widget.device, key: key, outlet: outlet);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo accionar el botón')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.service.byId(widget.device.id) ?? widget.device;
    final count = d.outletCount.clamp(1, 4);
    return Scaffold(
      backgroundColor: CceColors.neoBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.service.displayName(d), style: CceText.title),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _feedback ?? 'Tocá un botón',
              style: CceText.display.copyWith(
                fontSize: 22,
                color: _feedback != null ? CceColors.warm : CceColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tocá para accionar · mantené para long-press',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 36),
            _dial(count),
            const SizedBox(height: 28),
            Text(
              d.type,
              style: CceText.caption.copyWith(color: CceColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dial(int count) {
    const d = 280.0;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Disco elevado neumórfico: highlight sup-izq + sombra inf-der, más un
        // glow cálido sutil debajo.
        boxShadow: [
          ...CceShadows.neo(blur: 26, offset: 12, intensity: 1.1),
          BoxShadow(
            color: CceColors.warm.withValues(alpha: 0.16),
            blurRadius: 50,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.2, -0.3),
              radius: 1.0,
              colors: [Color(0xFFF6F2EA), Color(0xFFC9C3B8)],
            ),
          ),
          child: Stack(
            children: [
              // Cuadrantes (2×2). Outlet 0=arriba-izq … 3=abajo-der; los
              // puntos (1..4) identifican el botón como en el Tap Dial.
              Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _quad(0, count),
                        _quad(1, count),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _quad(2, count),
                        _quad(3, count),
                      ],
                    ),
                  ),
                ],
              ),
              // Cruz divisoria sutil.
              const Center(
                child: SizedBox.expand(
                  child: CustomPaint(painter: _CrossPainter()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quad(int outlet, int count) {
    if (outlet >= count) return const Expanded(child: SizedBox.shrink());
    final active = _pressed == outlet;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _press(outlet, 0),
        onLongPress: () => _press(outlet, 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          // Pulsado = cuadrante "hundido": sombra interna sutil sobre la cara.
          decoration: BoxDecoration(
            color: active
                ? Colors.black.withValues(alpha: 0.06)
                : Colors.transparent,
            boxShadow: active ? CceShadows.neoInset(blur: 10, offset: 4) : null,
          ),
          child: Center(child: _dots(outlet + 1)),
        ),
      ),
    );
  }

  /// n puntos (1..4) que identifican el botón, como el Hue Tap Dial.
  Widget _dots(int n) {
    Widget dot() => Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Color(0xFF3C3A36),
            shape: BoxShape.circle,
          ),
        );
    return SizedBox(
      width: 30,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [for (var i = 0; i < n; i++) dot()],
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 1.5;
    canvas.drawLine(
        Offset(size.width / 2, 8), Offset(size.width / 2, size.height - 8), p);
    canvas.drawLine(
        Offset(8, size.height / 2), Offset(size.width - 8, size.height / 2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
