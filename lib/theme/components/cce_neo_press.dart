import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interacción táctil NEUMÓRFICA (el equivalente del ripple de Material para
/// este design system): al apretar, el elemento se "hunde" — baja de escala con
/// una animación suave (rápida al apretar, con un pequeño rebote al soltar) y un
/// háptico. Reemplaza la onda de tinta de Material, que sobre superficies
/// neumórficas queda fuera de lugar.
///
/// Dos formas de uso:
///  - [child]: el hijo sólo se escala (cards/tiles que ya pintan su relieve).
///  - [builder]: recibe `t` (0 reposo → 1 apretado) para que el hijo además
///    cambie su relieve (p. ej. un botón raised→inset). En ambos casos
///    [CceNeoPress] aplica la escala, el gesto y el háptico.
class CceNeoPress extends StatefulWidget {
  const CceNeoPress({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.scaleTo = 0.96,
    this.haptic = true,
  }) : assert(child != null || builder != null,
            'CceNeoPress necesita child o builder');

  /// Hijo estático (sólo se escala). Mutuamente excluyente con [builder].
  final Widget? child;

  /// Builder con el valor de presión `t` (0..1) para hijos que reaccionan al
  /// estado apretado (botones que cambian de relieve).
  final Widget Function(BuildContext context, double t)? builder;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Escala al apretar a fondo (1 = sin escala). 0.96 ≈ hundido sutil.
  final double scaleTo;

  /// Háptico al confirmar el tap / long-press. Default true.
  final bool haptic;

  @override
  State<CceNeoPress> createState() => _CceNeoPressState();
}

class _CceNeoPressState extends State<CceNeoPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 0,
  );

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _press() =>
      _c.animateTo(1, duration: const Duration(milliseconds: 80), curve: Curves.easeOut);

  void _release() => _c.animateBack(0,
      duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final t = _c.value;
        final w = widget.builder != null ? widget.builder!(ctx, t) : widget.child!;
        final s = 1 - (1 - widget.scaleTo) * t;
        return Transform.scale(scale: s, child: w);
      },
    );

    if (!_enabled) return core;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: core,
    );
  }
}
