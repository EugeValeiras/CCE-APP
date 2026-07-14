import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';

/// Pantalla de un device de UN solo botón (eWeLink Button y similares): un
/// botón neumórfico grande y redondo que se hunde al tocarlo. Tocarlo simula un
/// click (key 0) y dispara la acción configurada en el backend; mantenerlo
/// presionado simula long-press (key 2). Mismo feedback visual (Click /
/// Mantenido) que [DialSwitchScreen], pero con un único cuadrante.
class SingleButtonScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  const SingleButtonScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<SingleButtonScreen> createState() => _SingleButtonScreenState();
}

class _SingleButtonScreenState extends State<SingleButtonScreen> {
  bool _pressed = false; // feedback visual (hundido)
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
  void _flash() {
    setState(() => _pressed = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  Future<void> _press(int key) async {
    HapticFeedback.mediumImpact();
    setState(() => _feedback =
        key == 2 ? 'Mantenido' : (key == 1 ? 'Doble click' : 'Click'));
    _fbTimer?.cancel();
    _fbTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _feedback = null);
    });
    final ok = await widget.service
        .simulateButton(widget.device, key: key, outlet: 0);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo accionar el botón')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.service.byId(widget.device.id) ?? widget.device;
    return Scaffold(
      backgroundColor: CceColors.neoBase,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(widget.service.displayName(d), style: CceText.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: CceColors.textSecondary),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _feedback ?? 'Tocá el botón',
              style: CceText.display.copyWith(
                fontSize: 22,
                color:
                    _feedback != null ? CceColors.warm : CceColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tocá · doble tap · mantené para long-press',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 40),
            _button(),
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

  /// El botón: un disco elevado dentro de un "pozo" circular hundido, para dar
  /// profundidad (relieve dentro de relieve). Se hunde con glow cálido al tocar.
  Widget _button() {
    const well = 300.0;
    const pad = 22.0;
    return Container(
      width: well,
      height: well,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.neoBase,
        boxShadow: [
          ...CceShadows.neoInset(blur: 24, offset: 10, intensity: 1.2),
          BoxShadow(
            color: CceColors.warm.withValues(
              alpha: _pressed ? 0.22 : 0.10,
            ),
            blurRadius: 48,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(pad),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _flash(),
        onTap: () => _press(0),
        onDoubleTap: () => _press(1),
        onLongPress: () => _press(2),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          scale: _pressed ? 0.95 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              // Reposo = disco ELEVADO; pulsado = HUNDIDO profundo + glow.
              boxShadow: _pressed
                  ? CceShadows.neoInset(blur: 14, offset: 6, intensity: 1.2)
                  : CceShadows.neo(blur: 18, offset: 9, intensity: 1.1),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _pressed ? CceColors.warm : CceColors.neoTextSub,
                  shape: BoxShape.circle,
                  boxShadow: _pressed
                      ? [
                          BoxShadow(
                            color: CceColors.warm.withValues(alpha: 0.6),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
