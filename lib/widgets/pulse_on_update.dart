import 'package:flutter/material.dart';

/// Wraps a child and plays a brief glow pulse whenever [triggerAt] changes.
/// Use to indicate "this widget just received a live WS update".
class PulseOnUpdate extends StatefulWidget {
  final Widget child;
  final DateTime? triggerAt;
  final Color color;
  final Duration duration;
  final double borderRadius;

  const PulseOnUpdate({
    super.key,
    required this.child,
    required this.triggerAt,
    this.color = const Color(0xFF4FC3F7),
    this.duration = const Duration(milliseconds: 650),
    this.borderRadius = 24,
  });

  @override
  State<PulseOnUpdate> createState() => _PulseOnUpdateState();
}

class _PulseOnUpdateState extends State<PulseOnUpdate> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didUpdateWidget(covariant PulseOnUpdate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerAt != null && widget.triggerAt != oldWidget.triggerAt) {
      _ctrl.forward(from: 0);
    }
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
        final v = _ctrl.value;
        if (v == 0) return child!;
        // Ease-out: strong at start, fades to 0.
        final intensity = (1 - Curves.easeOut.transform(v)).clamp(0.0, 1.0);
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.7 * intensity),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.45 * intensity),
                        blurRadius: 18 * intensity + 6,
                        spreadRadius: 2 * intensity,
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
