import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';

/// Pantalla del switch multi-botón (Hue Tap Dial / remote de 4 botones): un
/// dial neumórfico oscuro dividido en 4 cuadrantes que se hunden al tocarlos.
/// Tocar un cuadrante simula la pulsación (key 0) y dispara la acción
/// configurada en el backend; mantener presionado simula long-press (key 2).
///
/// Cada cuadrante es su PROPIO [GestureDetector] (sin overlays ni ClipOval que
/// roben el tap), con feedback instantáneo en `onTapDown` (hundido + glow).
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
  int? _pressed; // cuadrante con feedback visual activo
  String? _feedback; // 'Click' / 'Mantenido'
  Timer? _flashTimer;
  Timer? _fbTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _fbTimer?.cancel();
    super.dispose();
  }

  /// Hundido instantáneo al apoyar el dedo (no espera al backend).
  void _flash(int outlet) {
    setState(() => _pressed = outlet);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pressed = null);
    });
  }

  Future<void> _press(int outlet, int key) async {
    HapticFeedback.mediumImpact();
    setState(() => _feedback = key == 2 ? 'Mantenido' : 'Click');
    _fbTimer?.cancel();
    _fbTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _feedback = null);
    });
    final ok = await widget.service
        .simulateButton(widget.device, key: key, outlet: outlet);
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
                color:
                    _feedback != null ? CceColors.warm : CceColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tocá para accionar · mantené para long-press',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 40),
            _dial(count),
            const SizedBox(height: 32),
            Text(
              d.type,
              style: CceText.caption.copyWith(color: CceColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  /// El dial: 4 cuadrantes elevados dentro de un "pozo" circular hundido para
  /// dar profundidad (relieve dentro de relieve). El gap entre cuadrantes hace
  /// la cruz divisoria — sin painter encima que tape el tap.
  Widget _dial(int count) {
    const well = 300.0;
    const pad = 16.0;
    return Container(
      width: well,
      height: well,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.neoBase,
        // Pozo: hundido profundo + un glow cálido tenue por fuera.
        boxShadow: [
          ...CceShadows.neoInset(blur: 24, offset: 10, intensity: 1.2),
          BoxShadow(
            color: CceColors.warm.withValues(
              alpha: _pressed != null ? 0.22 : 0.10,
            ),
            blurRadius: 48,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(pad),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _quad(0, count),
                const SizedBox(width: 8),
                _quad(1, count),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                _quad(2, count),
                const SizedBox(width: 8),
                _quad(3, count),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Radios del cuadrante: la esquina EXTERNA muy redondeada (forma de cuarto
  /// de disco), las internas casi rectas — juntos arman el disco con cruz.
  BorderRadius _radii(int outlet) {
    const r = Radius.circular(128); // esquina externa (borde del disco)
    const s = Radius.circular(14); // esquinas internas
    switch (outlet) {
      case 0:
        return const BorderRadius.only(
            topLeft: r, topRight: s, bottomLeft: s, bottomRight: s);
      case 1:
        return const BorderRadius.only(
            topRight: r, topLeft: s, bottomLeft: s, bottomRight: s);
      case 2:
        return const BorderRadius.only(
            bottomLeft: r, topLeft: s, topRight: s, bottomRight: s);
      default:
        return const BorderRadius.only(
            bottomRight: r, topLeft: s, topRight: s, bottomLeft: s);
    }
  }

  Widget _quad(int outlet, int count) {
    final radii = _radii(outlet);
    // Cuadrante inexistente (switch de <4 botones): pad estático, sin tap, para
    // que el disco quede entero.
    if (outlet >= count) {
      return Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: radii,
            boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
          ),
        ),
      );
    }

    final active = _pressed == outlet;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _flash(outlet),
        onTap: () => _press(outlet, 0),
        onLongPress: () => _press(outlet, 2),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          scale: active ? 0.95 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: radii,
              // Reposo = cuadrante ELEVADO; pulsado = HUNDIDO profundo + glow.
              boxShadow: active
                  ? CceShadows.neoInset(blur: 12, offset: 5, intensity: 1.2)
                  : CceShadows.neo(blur: 16, offset: 8, intensity: 1.1),
            ),
            child: Center(child: _dots(outlet + 1, active)),
          ),
        ),
      ),
    );
  }

  /// n puntos (1..4) que identifican el botón, como el Hue Tap Dial. Se
  /// iluminan (cálido) cuando el cuadrante está activo.
  Widget _dots(int n, bool active) {
    final color = active ? CceColors.warm : CceColors.neoTextSub;
    Widget dot() => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: CceColors.warm.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
    return SizedBox(
      width: 34,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 7,
        runSpacing: 7,
        children: [for (var i = 0; i < n; i++) dot()],
      ),
    );
  }
}
