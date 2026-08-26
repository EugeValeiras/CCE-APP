import 'package:flutter/material.dart';

import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';

/// La ÚNICA superficie de la pantalla del teléfono (CCE#14).
///
/// Antes convivían cuatro lenguajes: la card gris redondeada de la línea, la
/// card naranja con borde del aviso, el panel de audio, y un rectángulo plano
/// sin radio para el número. Parecían pantallas de apps distintas. Ahora todo
/// bloque —chip de línea, display, cards de estado, panel de audio, filas del
/// historial y de la libreta— se apoya en esto: mismo radio, mismo hairline,
/// misma familia de color. Entre bloques cambia el CONTENIDO, no el envase.
///
/// Es un [CceCard] con las decisiones ya tomadas, no otro componente.
class PhoneSurface extends StatelessWidget {
  const PhoneSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CceSpace.lg),
    this.color,
    this.tint,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Base: [CceColors.surface]. El display usa [CceColors.surfaceHigh], que es
  /// el escalón de los inputs en el design system.
  final Color? color;

  /// Color semántico para un bloque que ES un estado (el error del backend).
  /// Se mezcla con la superficie en vez de reemplazarla: sigue siendo la misma
  /// pieza, teñida.
  final Color? tint;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// El radio de todas las superficies del teléfono. 16 y no 22 porque son
  /// bloques finos (un chip de 34 px con radio 22 es una píldora, y un display
  /// de 68 px con radio 22 es un jabón); a 16 los dos se leen como piezas del
  /// mismo juego que las teclas y los botones.
  static const double radius = CceRadii.control;

  @override
  Widget build(BuildContext context) {
    final base = color ?? CceColors.surface;
    return CceCard(
      radius: radius,
      border: true,
      borderColor: tint?.withValues(alpha: 0.35),
      color: tint == null
          ? base
          : Color.alphaBlend(tint!.withValues(alpha: 0.12), base),
      padding: padding,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

/// Separador interno de una [PhoneSurface]: un hairline, nada más.
class PhoneDivider extends StatelessWidget {
  const PhoneDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1,
      width: double.infinity,
      child: DecoratedBox(decoration: BoxDecoration(color: CceColors.stroke)),
    );
  }
}
