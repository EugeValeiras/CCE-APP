import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_neo_press.dart';

/// Interpola dos listas de sombra por `t` (0..1) para el hundido animado de
/// los botones.
///
/// Tolera listas de LARGO DISTINTO: la que se queda corta aporta una sombra
/// transparente. Es necesario porque los estados del sistema ya no tienen la
/// misma cantidad de sombras (el estado hundido no lleva ninguna), y asumir
/// simetría hacía estallar el índice en cada frame de la animación.
List<BoxShadow> _lerpShadow(List<BoxShadow> a, List<BoxShadow> b, double t) {
  const empty = BoxShadow(color: Color(0x00000000), blurRadius: 0);
  final n = a.length > b.length ? a.length : b.length;
  return [
    for (var i = 0; i < n; i++)
      BoxShadow.lerp(
        i < a.length ? a[i] : empty,
        i < b.length ? b[i] : empty,
        t,
      )!,
  ];
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
        // emboss:false → glifo PLANO. El relieve ya lo da el botón (raised); el
        // emboss del ícono suma un ghost desplazado (1.3,2.2) que lo corre y lo
        // hace ver descentrado dentro del círculo.
        child: CceIcon(
          svg,
          size: size * 0.5,
          emboss: false,
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
