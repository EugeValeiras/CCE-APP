import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_tokens.dart';

/// IconButton neumórfico raised (size cycle, refresh). Diámetro fijo 44.
///
/// Estado presionado → hundido (`neoInset`); reposo → extruido (`neo`);
/// deshabilitado (`onPressed == null`) → plano sin relieve, icono atenuado.
/// El `color: neoBase` opaco se mantiene SIEMPRE (necesario para
/// `BlurStyle.inner` del estado presionado).
class CceNeoIconButton extends StatefulWidget {
  const CceNeoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  State<CceNeoIconButton> createState() => _CceNeoIconButtonState();
}

class _CceNeoIconButtonState extends State<CceNeoIconButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final List<BoxShadow> shadow = !enabled
        ? const []
        : (_pressed
            ? CceShadows.neoInset(blur: 6, offset: 2)
            : CceShadows.neo(blur: 8, offset: 3));

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase,
          boxShadow: shadow,
        ),
        child: Icon(
          widget.icon,
          size: widget.size * 0.5,
          color: enabled ? CceColors.neoText : CceColors.neoTextSub,
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Botón de texto neumórfico raised (Encender / Apagar todo).
///
/// `onPressed == null` ⇒ deshabilitado (plano, sin relieve, label atenuado).
/// El haptic NO va acá: el call-site dispara su propio `HapticFeedback`; este
/// widget sólo invoca [onPressed].
class CceNeoActionButton extends StatefulWidget {
  const CceNeoActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 40,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  State<CceNeoActionButton> createState() => _CceNeoActionButtonState();
}

class _CceNeoActionButtonState extends State<CceNeoActionButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final List<BoxShadow> shadow = !enabled
        ? const []
        : (_pressed
            ? CceShadows.neoInset(blur: 6, offset: 2)
            : CceShadows.neo(blur: 8, offset: 3));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          boxShadow: shadow,
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: enabled ? CceColors.neoText : CceColors.neoTextSub,
          ),
        ),
      ),
    );
  }
}
