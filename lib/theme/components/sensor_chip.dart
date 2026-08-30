import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';

/// Una medición lista para pintar: glifo + valor, sin lógica de sensores.
///
/// La resuelve `RoomAmbient` (lib/utils/room_ambient.dart) y la consume
/// [SensorChip]. Es data pura — un SVG, un texto y un color — para que quien
/// decide QUÉ mostrar (el helper, testeable sin montar widgets) y quien decide
/// CÓMO se ve (este componente) no se mezclen.
@immutable
class SensorChipData {
  const SensorChipData({
    required this.glyph,
    required this.label,
    this.glyphColor,
    this.semanticLabel,
  });

  /// SVG de [CceIcons] (currentColor: lo tinta el chip).
  final String glyph;

  /// Valor a mostrar, ya formateado ('20.1°', 'Cerrada', '1 mando').
  final String label;

  /// Tinte del glifo. null ⇒ hereda la tinta del texto. Se usa SÓLO para
  /// estados que ya tienen color en el sistema (contacto abierto, movimiento):
  /// un chip de lectura no inventa color.
  final Color? glyphColor;

  /// Frase para lectores de pantalla; null ⇒ se lee [label] tal cual.
  final String? semanticLabel;
}

/// Pastilla compacta de una medición dentro de una fila de la lista.
///
/// Vive en la segunda línea de la [RoomCard] de una habitación SIN luces, donde
/// va en lugar del subtítulo de estado. De ahí salen sus medidas: tiene que
/// entrar en el alto que la card ya reservaba para el slider (20px) sin
/// estirarla, así que es más chica que cualquier otra píldora de la app
/// ([StatusPill], 12/10/5, es de detalle de dispositivo).
///
/// El valor usa las cifras TABULARES de [CceText.data]: en una lista, pasar de
/// 23.9° a 24.0° no debe mover el chip que tiene al lado.
class SensorChip extends StatelessWidget {
  const SensorChip(this.data, {super.key});

  final SensorChipData data;

  /// Alto de la pastilla: 12 de texto (height 1.2 ⇒ 14.4) + 3+3 de padding +
  /// el hairline. Fijo para que dos chips con y sin glifo no se desalineen.
  static const double kHeight = 21;

  /// Lado del glifo. 12 es el tamaño al que un lucide de stroke 2 sigue
  /// leyéndose: por debajo se convierte en una mancha.
  static const double kGlyphSize = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kHeight,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.sm),
        border: Border.all(color: CceColors.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(
            data.glyph,
            size: kGlyphSize,
            // Por defecto el glifo va un escalón por debajo del valor: el dato
            // es el texto, el glifo sólo dice de qué es.
            color: data.glyphColor ?? CceColors.textTertiary,
            // Sin relieve: a 12px el emboss es una sombra sobre una mancha.
            emboss: false,
          ),
          SizedBox(width: CceSpace.xs),
          // Flexible + ellipsis: con la card angosta los chips se comprimen
          // antes que desbordar la fila.
          Flexible(
            child: Text(
              data.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: data.semanticLabel,
              style: CceText.data.copyWith(
                fontSize: 12,
                color: CceColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
