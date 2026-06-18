import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/cce_tokens.dart';

/// Envuelve un hijo y reproduce un "respiro" suave neomórdico cuando [triggerAt]
/// cambia, para indicar "este widget acaba de recibir un update en vivo".
///
/// Antes era un destello extravagante (borde de color 2px + halo fuerte) que se
/// REINICIABA en cada evento → parpadeo constante ante ráfagas de updates. Ahora:
///  - Throttle: si ya hay un respiro corriendo NO se reinicia, y se respeta un
///    [cooldown] desde el inicio del último ⇒ una ráfaga = UN solo respiro.
///  - Estética: sin borde; un glow tenue (baja alpha, difuso) del color de la
///    sala que sube y baja con una curva seno (sin onset brusco) — relieve que
///    "respira", no un flash.
class PulseOnUpdate extends StatefulWidget {
  final Widget child;
  final DateTime? triggerAt;
  final Color color;
  final Duration duration;

  /// Tiempo mínimo entre el inicio de un respiro y el siguiente. Absorbe las
  /// ráfagas de eventos (varios devices cambiando a la vez) en un único pulso.
  final Duration cooldown;
  final double borderRadius;

  const PulseOnUpdate({
    super.key,
    required this.child,
    required this.triggerAt,
    this.color = CceColors.info,
    this.duration = const Duration(milliseconds: 900),
    this.cooldown = const Duration(milliseconds: 1400),
    this.borderRadius = CceRadii.tile,
  });

  @override
  State<PulseOnUpdate> createState() => _PulseOnUpdateState();
}

class _PulseOnUpdateState extends State<PulseOnUpdate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  DateTime? _lastPulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didUpdateWidget(covariant PulseOnUpdate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerAt == null || widget.triggerAt == oldWidget.triggerAt) {
      return;
    }
    // Throttle: no reiniciar un respiro en curso, ni respirar más seguido que el
    // cooldown. Así una ráfaga de eventos no titila: muestra un único pulso.
    if (_ctrl.isAnimating) return;
    final now = DateTime.now();
    if (_lastPulse != null && now.difference(_lastPulse!) < widget.cooldown) {
      return;
    }
    _lastPulse = now;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        // Curva seno: 0 → 1 → 0. Sube y baja suave (sin destello inicial duro).
        final b = math.sin(math.pi * _ctrl.value.clamp(0.0, 1.0));
        if (b <= 0.001) return child!;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    // Sin borde. Glow tenue y difuso del color de la sala: un
                    // relieve que respira, no un anillo brillante.
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.16 * b),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
