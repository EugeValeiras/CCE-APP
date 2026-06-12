import 'package:flutter/material.dart';

/// Dot de estado con halo (reemplaza a las StatusPills de ancho rígido):
/// círculo de color pleno + glow, con pulso opcional mientras [pulse] sea
/// true (movimiento, puerta abierta, evento live).
class StatusDot extends StatefulWidget {
  const StatusDot(
    this.color, {
    super.key,
    this.size = 8,
    this.pulse = false,
    this.semanticLabel,
  });

  /// Color pleno (CceColors.motion / contact / ok).
  final Color color;

  /// 8 en room cards, 10 en automation cards, 6 junto a tiempos.
  final double size;

  /// Scale 1.0→1.25, 1.2 s easeInOut en loop mientras sea true.
  final bool pulse;

  /// Semantics + Tooltip ("Movimiento", "Puerta abierta").
  final String? semanticLabel;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.25)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget dot = ScaleTransition(
      scale: _scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.55),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label != null && label.isNotEmpty) {
      dot = Tooltip(
        message: label,
        child: Semantics(label: label, child: dot),
      );
    }
    return dot;
  }
}
