import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';

/// Un hecho de la habitación listo para pintar: glifo, palabra y color.
///
/// Es data pura para que quien decide QUÉ estados hay (la card, que recibe
/// bools ya resueltos) y quien decide CÓMO se ven (este componente) no se
/// mezclen — el mismo reparto que tenía `SensorChipData` (CCE#57).
@immutable
class StatusBadgeData {
  const StatusBadgeData({
    required this.glyph,
    required this.label,
    required this.color,
    required this.semanticLabel,
    this.live = false,
  });

  /// SVG de [CceIcons] (currentColor: lo tinta el badge).
  final String glyph;

  /// Palabra corta del estado ('Abierta', 'Movimiento', 'Luz'). Corta a
  /// propósito: en la fila de una habitación el ancho es el recurso escaso y
  /// el glifo ya dice de qué se está hablando.
  final String label;

  /// Color del sistema para ese hecho ([CceColors.contact], `motion`,
  /// `amberHi`). El badge NO inventa color: es el mismo que tenía el dot que
  /// reemplaza.
  final Color color;

  /// Frase completa para lectores de pantalla y tooltip ('Puerta abierta').
  /// Es la que hace que un badge sin texto (ver [StatusBadge.showLabel]) siga
  /// siendo accesible.
  final String semanticLabel;

  /// El hecho está pasando AHORA (contacto abierto, movimiento) ⇒ el glifo
  /// late. La luz encendida no late: no es un evento, es un estado.
  final bool live;
}

/// Pastilla de UN estado de la habitación: glifo de color + palabra.
///
/// Hereda la forma del `SensorChip` de CCE#57 —fondo [CceColors.surfaceHigh],
/// hairline [CceColors.strokeSoft], radio `sm`, texto secundario— porque esa
/// pastilla ya se vio en pantalla y gustó; lo que se descartó entonces fue
/// ponerla en lugar del switch, no la pastilla. Cambia el contenido: aquélla
/// mostraba MEDICIONES (23.9°, 33%), ésta muestra ESTADOS.
///
/// La caja es NEUTRA y el color vive sólo en el glifo. Tres pastillas
/// tintadas al lado del nombre de la habitación convierten la lista en un
/// semáforo: el nombre es lo que la fila viene a decir y ninguna caja de color
/// debería ganarle. El color, en el glifo, alcanza para reconocer el hecho de
/// un vistazo — es la misma cantidad de color que tenía el dot.
///
/// Medidas propias del componente (no salen de la escala de espaciado): están
/// derivadas del alto que la [RoomCard] deja libre en su fila de estado.
class StatusBadge extends StatefulWidget {
  const StatusBadge(this.data, {super.key, this.showLabel = true});

  final StatusBadgeData data;

  /// false ⇒ sólo el glifo. Lo decide [StatusBadgeRow] cuando no hay ancho
  /// para todos: un badge mudo sigue diciendo (color + forma + tooltip) más
  /// que el punto que había antes, y nunca se recorta una palabra a la mitad.
  final bool showLabel;

  /// Alto de la pastilla. TOPE DURO: la card mide 88px y, con el slider
  /// puesto, su fila de contenido son 44 — de los que el nombre (17px de
  /// headline con height 1.25) ya se lleva 21.25. Quedan 22.75 para el gap y
  /// el badge; 18 + 4 de gap entra con margen. Un badge más alto estira la
  /// card, y la altura uniforme de la lista es justamente lo que este archivo
  /// viene cuidando desde CCE#22.
  static const double kHeight = 18;

  /// Lado del glifo y cuerpo del texto. 11 es un escalón por debajo del
  /// `SensorChip` (12): el badge de estado convive con OTROS badges en la
  /// misma línea, y cada punto de tipografía se paga en ancho tres veces.
  static const double kGlyphSize = 11;
  static const double kFontSize = 11;

  /// Aire interno, separación glifo↔palabra y hairline. Los tres entran en el
  /// ancho, y el hairline también: [widthOf] tiene que devolver el ancho REAL
  /// de la caja o la fila reparte de menos y termina eligiendo una palabra
  /// para elidir teniendo lugar de sobra.
  static const double kPadH = 5;
  static const double kInnerGap = 3;
  static const double kBorder = 1;

  /// Estilo del texto. Público porque [widthOf] mide con él: la fila calcula
  /// cuántas palabras entran ANTES de dibujar, y tiene que medir exactamente
  /// lo que después se pinta.
  static const TextStyle labelStyle = TextStyle(
    fontSize: kFontSize,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: CceColors.textSecondary,
  );

  /// Ancho de un badge SIN texto (sólo glifo).
  static const double glyphOnlyWidth = (kPadH + kBorder) * 2 + kGlyphSize;

  /// Ancho que ocupa el badge de [label] con su palabra, con la tipografía
  /// real y el escalado de accesibilidad del dispositivo.
  static double widthOf(String label, {TextScaler textScaler = TextScaler.noScaling}) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return glyphOnlyWidth + kInnerGap + width;
  }

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  /// El LATIDO del badge, heredado del `StatusDot(pulse: true)` que reemplaza.
  ///
  /// Cambia de vehículo a propósito: el dot pulsaba de TAMAÑO (scale 1→1.25),
  /// y un badge que crece empuja a los que tiene al lado — la fila entera
  /// bailaría al ritmo del sensor, que es justo el ritmo que esta lista viene
  /// cuidando. Late la OPACIDAD del glifo: dice lo mismo ("esto está pasando
  /// ahora") sin mover un pixel de layout.
  ///
  /// Es null mientras el hecho no lata: un badge quieto —la luz encendida, o un
  /// sensor en un badge sin latido— no paga un Ticker. En una lista de diez
  /// habitaciones eso son diez animaciones que nadie mira.
  AnimationController? _controller;
  Animation<double>? _fade;

  void _startPulse() {
    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade ??= Tween<double>(begin: 1.0, end: 0.45).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    controller.repeat(reverse: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.data.live) _startPulse();
  }

  @override
  void didUpdateWidget(StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.live) {
      if (_controller?.isAnimating != true) _startPulse();
    } else if (_controller?.isAnimating == true) {
      _controller!.stop();
      _controller!.value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    Widget glyph = CceIcon(
      data.glyph,
      size: StatusBadge.kGlyphSize,
      color: data.color,
      // Sin relieve: a 11px el emboss es una sombra sobre una mancha.
      emboss: false,
    );
    final fade = _fade;
    if (data.live && fade != null) {
      glyph = FadeTransition(opacity: fade, child: glyph);
    }

    final badge = Container(
      height: StatusBadge.kHeight,
      padding: const EdgeInsets.symmetric(horizontal: StatusBadge.kPadH),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.sm),
        border: Border.all(
            color: CceColors.strokeSoft, width: StatusBadge.kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          if (widget.showLabel) ...[
            const SizedBox(width: StatusBadge.kInnerGap),
            // Flexible + ellipsis: red de seguridad para un ancho que ni la
            // fila previó (escalado de texto extremo). Nunca desborda.
            Flexible(
              child: Text(
                data.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: StatusBadge.labelStyle,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: data.semanticLabel,
      child: Semantics(
        label: data.semanticLabel,
        excludeSemantics: true,
        child: badge,
      ),
    );
  }
}

/// La fila de badges de estado de una habitación, con su regla de ancho.
///
/// LA REGLA (CCE#63, punto 3 del issue): los badges se dibujan en orden fijo
/// —el mismo que tenían los dots— y el ancho se reparte por PRIORIDAD INVERSA:
/// el ÚLTIMO es el primero en quedarse sin palabra.
///
///  1. Si entran todos con su palabra, se dibujan todos con su palabra.
///  2. Si no, el último pierde el texto y queda en glifo. Se repite hacia
///     atrás hasta que la fila entre — incluido el primero.
///  3. Sólo si un badge no entra ni con su glifo solo, su texto elide (el
///     Flexible del primero; no debería pasar nunca).
///
/// Por qué así y no de las otras formas posibles:
///  - NO se apilan: dos líneas de badges rompen los 88px de la card, que es la
///    única medida que este componente tiene prohibido tocar.
///  - NO se recortan las palabras ("Movimien…"): un texto cortado no se lee, y
///    leerse es todo el punto del cambio. Por eso el primero también cede su
///    palabra cuando hace falta: en el sidebar de tablet, donde a los badges
///    les quedan 78px, "Abie…" junto a un glifo era peor que los dos glifos —
///    el dibujo de una puerta abierta dice más que media palabra.
///  - NO hay contador "+1": un "+1" es tan mudo como el punto que se está
///    sacando, y encima ocupa casi lo mismo que el glifo, que al menos dice
///    QUÉ pasa y conserva su color y su tooltip.
///
/// El orden de llegada de la lista es también el de prioridad, y la card lo
/// arma poniendo primero lo que no se dice en ningún otro lado de la fila
/// (los sensores) y último lo que ya dicen el ícono, el switch y el slider
/// (la luz encendida).
class StatusBadgeRow extends StatelessWidget {
  const StatusBadgeRow(this.badges, {super.key});

  final List<StatusBadgeData> badges;

  /// Separación entre badges. [CceSpace.xs]: son cajas con hairline propio,
  /// no necesitan el aire que necesitaría un texto suelto.
  static const double gap = CceSpace.xs;

  /// Cuáles de [badges] van con palabra dentro de [maxWidth]. Pura, estática y
  /// sin widgets: es la regla de arriba escrita una sola vez, y se puede
  /// probar con una tabla de anchos en vez de con capturas.
  static List<bool> labelsThatFit(
    List<StatusBadgeData> badges,
    double maxWidth, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final showLabel = List<bool>.filled(badges.length, true);
    if (badges.isEmpty) return showLabel;

    final withLabel = [
      for (final b in badges)
        StatusBadge.widthOf(b.label, textScaler: textScaler)
    ];
    double total() {
      var sum = gap * (badges.length - 1);
      for (var i = 0; i < badges.length; i++) {
        sum += showLabel[i] ? withLabel[i] : StatusBadge.glyphOnlyWidth;
      }
      return sum;
    }

    for (var i = badges.length - 1; i >= 0 && total() > maxWidth; i--) {
      showLabel[i] = false;
    }
    return showLabel;
  }

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel =
            labelsThatFit(badges, constraints.maxWidth, textScaler: textScaler);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < badges.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              // Sólo el primero es flexible: después del reparto es el único
              // al que le puede faltar ancho (un ancho absurdo, un escalado de
              // texto extremo), y ahí su contenido elide antes que desbordar
              // la card.
              if (i == 0)
                Flexible(child: StatusBadge(badges[i], showLabel: showLabel[i]))
              else
                StatusBadge(badges[i], showLabel: showLabel[i]),
            ],
          ],
        );
      },
    );
  }
}
