import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Card base del design system: superficie redondeada con gradiente o color
/// plano, borde hairline opcional y soporte de tap/long-press con ripple.
class CceCard extends StatelessWidget {
  const CceCard({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.radius = CceRadii.card,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.border = false,
    this.neo = false,
    this.neoInset = false,
  });

  final Widget child;
  final Gradient? gradient;
  final Color? color; // default CceColors.surface
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool border;

  /// OPT-IN: extrusión neumórfica externa (highlight sup-izq + sombra inf-der).
  /// Default false ⇒ render plano idéntico al actual.
  final bool neo;

  /// OPT-IN: relieve hundido (inner-shadow nativa en la propia decoración,
  /// sin overlay ni Stack). Default false ⇒ render plano idéntico al actual.
  final bool neoInset;

  /// Decoración canónica de una card RAISED (almohada flotante): superficie
  /// con gradiente sutil [CceGradients.cardSurface], elevación difusa
  /// [CceShadows.cardFloat] y bevel hairline superior opcional. NO usar para
  /// fills de color ON. El boxShadow va incluido: si el contenedor clipea,
  /// poner esta decoración en un contenedor EXTERNO sin clip (igual que hoy).
  static BoxDecoration raisedDecoration({
    required Color base,
    required double radius,
    bool bevel = true,
  }) {
    final br = BorderRadius.circular(radius);
    return BoxDecoration(
      gradient: CceGradients.cardSurface(base),
      borderRadius: br,
      border: bevel ? Border.all(color: CceColors.cardBevel) : null,
      boxShadow: CceShadows.cardFloat(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    // Color base: con neo (sin gradiente) cae a neoBase; con neoInset (sin
    // gradiente) cae a neoSunken; si no, surface (comportamiento histórico).
    final Color? effectiveColor = color ??
        (gradient != null
            ? null
            : neoInset
                ? CceColors.neoSunken
                : neo
                    ? CceColors.neoBase
                    : null);

    // Caso raised (almohada): la superficie (gradiente + sombra + bevel) la
    // pinta el DecoratedBox EXTERNO via raisedDecoration; la decoración interna
    // debe quedar transparente para que el gradiente se vea (el InkWell clipea).
    final bool useRaised = neo && gradient == null && !neoInset;

    final decoration = BoxDecoration(
      color: gradient == null
          ? (useRaised ? null : (effectiveColor ?? CceColors.surface))
          : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: border ? Border.all(color: CceColors.stroke) : null,
      // La inner-shadow del inset vive en la propia decoración (no overlay).
      boxShadow: neoInset ? CceShadows.neoInset() : null,
    );

    final content = Padding(padding: padding, child: child);

    final Widget base;
    if (onTap == null && onLongPress == null) {
      base = Container(decoration: decoration, child: content);
    } else {
      base = Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: borderRadius,
            child: content,
          ),
        ),
      );
    }

    // Extrusión externa: como el branch con tap clipea (Clip.antiAlias) y un
    // boxShadow se recortaría, la sombra va en un DecoratedBox EXTERNO sin clip.
    if (neo) {
      // Raised "almohada": superficie nueva (gradiente sutil + cardFloat +
      // bevel). El gradiente lo pinta este DecoratedBox externo (la decoración
      // interna quedó transparente via useRaised), así cubre el área completa
      // y el ripple queda recortado dentro del Container clipeado.
      if (useRaised) {
        return DecoratedBox(
          decoration: CceCard.raisedDecoration(
            base: effectiveColor ?? CceColors.neoBase,
            radius: radius,
          ),
          child: base,
        );
      }
      // Caso neo con gradiente/color propio (fills ON: huePastel, lightFull,
      // color explícito): se conserva el relieve de botón simétrico para NO
      // tocar los estados encendidos ni lavar el color saturado.
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: CceShadows.neo(),
        ),
        child: base,
      );
    }

    return base;
  }
}
