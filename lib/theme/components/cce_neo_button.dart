import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_neo_press.dart';

/// Interpola dos pares de sombra (raised ↔ inset) por `t` (0..1) para el
/// "hundido" animado de los botones neumórficos.
List<BoxShadow> _lerpShadow(List<BoxShadow> a, List<BoxShadow> b, double t) {
  return [for (var i = 0; i < a.length; i++) BoxShadow.lerp(a[i], b[i], t)!];
}

/// IconButton neumórfico raised (size cycle, refresh). Diámetro fijo 44.
///
/// Estado presionado → hundido (`neoInset`); reposo → extruido (`neo`), con
/// transición ANIMADA + escala (vía [CceNeoPress]); deshabilitado
/// (`onPressed == null`) → plano sin relieve, icono atenuado. El `color: neoBase`
/// opaco se mantiene SIEMPRE (necesario para `BlurStyle.inner` del estado
/// presionado).
class CceNeoIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);

    final button = CceNeoPress(
      onTap: onPressed,
      builder: (ctx, t) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase,
          boxShadow: enabled ? _lerpShadow(raised, inset, t) : const [],
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: enabled ? CceColors.neoText : CceColors.neoTextSub,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// IconButton neumórfico raised gemelo de [CceNeoIconButton], pero renderiza
/// un glifo SVG de [CceIcons] (regla icons0.dev) en vez de un [IconData]
/// Material. Mismas sombras / háptico / estados (raised→press→inset animado).
/// Diámetro fijo 44.
class CceNeoSvgIconButton extends StatelessWidget {
  const CceNeoSvgIconButton({
    super.key,
    required this.svg,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconColor,
  });

  final String svg;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  /// Color del glifo cuando está habilitado. Por defecto [CceColors.neoText].
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);

    final button = CceNeoPress(
      onTap: onPressed,
      builder: (ctx, t) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase,
          boxShadow: enabled ? _lerpShadow(raised, inset, t) : const [],
        ),
        child: CceIcon(
          svg,
          size: size * 0.5,
          color: enabled
              ? (iconColor ?? CceColors.neoText)
              : CceColors.neoTextSub,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Botón de texto neumórfico raised (Encender / Apagar todo) con hundido
/// animado.
///
/// `onPressed == null` ⇒ deshabilitado (plano, sin relieve, label atenuado).
/// El háptico NO va acá: el call-site dispara su propio `HapticFeedback`; por
/// eso [CceNeoPress] se usa con `haptic: false`.
class CceNeoActionButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);

    return CceNeoPress(
      onTap: onPressed,
      haptic: false,
      builder: (ctx, t) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          boxShadow: enabled ? _lerpShadow(raised, inset, t) : const [],
        ),
        child: Text(
          label,
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
