import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_card.dart';
import 'status_dot.dart';

/// Tile de la grilla "Destacados" de la home (2 × 2).
///
/// Anatomía fija, de arriba a abajo: glyph a la izquierda y el control rápido
/// a la derecha en la misma fila; el nombre; y una línea de estado (dot +
/// texto). Todas las cards destacadas (TV, JBL, termostato, robot, teléfono,
/// luz, botón, cerradura, sensor, escena, automatización) se renderizan con
/// este mismo molde cuando van en la grilla, así que la sección se lee como
/// un sistema y no como una pila de cards distintas.
///
/// ALTURA ÚNICA [kHeight]: 12 + fila de control 32 + nombre 21 + 2 + estado
/// 17 + 12, redondeado. Antes cada destacado era una fila de 76 px a todo el
/// ancho: cuatro de ellos ocupaban 340 px y empujaban "Habitaciones" fuera de
/// la primera pantalla. Dos filas de estos tiles ocupan 216.
class FeaturedTile extends StatelessWidget {
  const FeaturedTile({
    super.key,
    required this.glyph,
    required this.glyphColor,
    required this.title,
    required this.subtitle,
    required this.control,
    this.dotColor,
    this.dotPulse = false,
    this.onTap,
    this.onLongPress,
  });

  /// Altura del tile. Vive acá, no en un token: es una medida de componente,
  /// como `RoomCard.kHeight`.
  static const double kHeight = 102;

  /// Alto de la fila superior (glyph + control). Aloja el switch (30) y los
  /// botones de acción ([FeaturedTileAction]) sin estirar el tile.
  static const double _controlRow = 32;

  /// Ícono del dispositivo (CceIcon SVG o Icon de Material); se lleva a 24
  /// y se tiñe con [glyphColor].
  final Widget glyph;
  final Color glyphColor;
  final String title;
  final String subtitle;

  /// Dot de estado a la izquierda del subtítulo. null ⇒ sin dot.
  final Color? dotColor;
  final bool dotPulse;

  /// Control rápido (switch, ▶, contador, chevron). El tap sobre el control
  /// es del control; el tap sobre el resto del tile es [onTap].
  final Widget control;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kHeight,
      child: CceCard(
        neo: true,
        radius: CceRadii.card,
        padding: EdgeInsets.all(CceSpace.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _controlRow,
              child: Row(
                children: [
                  EmbossedGlyph(
                    size: 24,
                    color: glyphColor,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: glyph,
                  ),
                  const Spacer(),
                  control,
                ],
              ),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.headline,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (dotColor != null) ...[
                  StatusDot(dotColor!, pulse: dotPulse, semanticLabel: subtitle),
                  SizedBox(width: CceSpace.sm),
                ],
                Flexible(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CceText.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Control "abre el detalle" para lo que no tiene acción rápida (fuera de
  /// línea, cerraduras, sensores).
  static Widget chevron() => const Padding(
        padding: EdgeInsets.all(4),
        child: CceIcon(
          CceIcons.chevronRight,
          size: 20,
          color: CceColors.textTertiary,
          emboss: false,
        ),
      );
}

/// Botón de acción de un [FeaturedTile] (▶ limpiar, ▶ aplicar escena, ⏸):
/// círculo de 32 en [CceColors.surfaceHigh] con hairline, glyph de 16.
/// [busy] muestra el spinner en su lugar; [done] el check de confirmación.
class FeaturedTileAction extends StatelessWidget {
  const FeaturedTileAction({
    super.key,
    required this.svg,
    required this.onTap,
    this.tooltip,
    this.busy = false,
    this.child,
  });

  final String svg;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool busy;

  /// Reemplaza el glyph (p.ej. el check de "ejecutada").
  final Widget? child;

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final Widget content = busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: CceColors.textSecondary),
          )
        : child ??
            CceIcon(svg,
                size: 16, color: CceColors.textSecondary, emboss: false);
    final button = Material(
      color: CceColors.surfaceHigh,
      shape: const CircleBorder(side: BorderSide(color: CceColors.stroke)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: content),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
