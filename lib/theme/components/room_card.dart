import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'brightness_slider.dart';
import 'cce_card.dart';
import 'cce_switch.dart';
import 'status_dot.dart';

/// Card de habitación (sidebar tablet y lista phone).
///
/// ALTURA UNIFORME ([kHeight]), con slider o sin él. Antes la card medía 76 sin
/// slider y 104 con slider: en una lista donde unas habitaciones dimean y otras
/// no, ese salto del 37% aparecía de forma aparentemente aleatoria y era lo que
/// hacía que la lista "saltara" al recorrerla. Reservar siempre la misma altura
/// cuesta un poco de densidad y compra ritmo vertical, que a la larga es lo que
/// hace que una lista se lea como un sistema y no como una pila de cosas.
/// Todo lo que se agregue a la card (el badge de [temperature], por ejemplo)
/// se acomoda DENTRO de esa caja; nada la estira.
///
/// El estado ENCENDIDO se comunica con el ácento del sistema (ícono + switch +
/// dot), NO con el color real de las luces: en una lista lo que importa es
/// *si* algo está prendido, no de qué color está. El color real de cada lámpara
/// vive en su tile y en el detalle, donde sí es la información principal —
/// pintarlo acá era lo que convertía la home en un arcoíris de toggles.
class RoomCard extends StatefulWidget {
  const RoomCard({
    super.key,
    required this.title,
    this.icon,
    this.iconBuilder,
    required this.lightsOn,
    required this.lightsTotal,
    required this.anyOn,
    this.tint,
    this.tintColors = const [],
    this.brightness,
    this.selected = false,
    this.compact = false,
    this.motion = false,
    this.contactOpen = false,
    this.subtitleOverride,
    this.temperature,
    this.toggleEnabled = true,
    required this.onTap,
    required this.onToggle,
    this.onBrightnessCommitted,
    this.neo = false,
  }) : assert(icon != null || iconBuilder != null,
            'RoomCard necesita icon o iconBuilder');

  final String title;

  /// Glyph fijo (Icon(Mdi...) o CceIcon). EmbossedGlyph lo recolorea vía
  /// IconTheme — sirve para Material/CceIcon, NO para un SvgPicture de icons0.
  final Widget? icon;

  /// Glyph dependiente del color de estado: recibe el `glyphColor` calculado en
  /// build y lo hornea (necesario para SVG icons0, que ignora IconTheme). Si se
  /// pasa, tiene prioridad sobre [icon]. Mismo patrón que las light tiles.
  final Widget Function(Color glyphColor)? iconBuilder;
  final int lightsOn;
  final int lightsTotal;
  final bool anyOn;

  /// Color dominante (fallback del gradiente si [tintColors] viene vacío).
  final Color? tint;

  /// Colores de todas las luces ON: gradiente multicolor estilo Hue. Vacío
  /// ⇒ se usa [tint] como color único.
  final List<Color> tintColors;
  final double? brightness; // 0..1; null = sin slider
  final bool selected; // resaltado en sidebar tablet
  final bool compact; // phone vs tablet

  /// true → StatusDot(CceColors.motion, pulse: true).
  final bool motion;

  /// true → StatusDot(CceColors.contact, pulse: true).
  final bool contactOpen;

  /// "Toda la casa": "12/31 · 2 con movimiento".
  final String? subtitleOverride;

  /// Temperatura actual de la habitación en °C, ya resuelta por
  /// `RoomTemperature.forRoom` (la card no sabe de sensores). null ⇒ NO se
  /// renderiza nada: una habitación sin termómetro se ve exactamente igual que
  /// antes de que existiera el badge. La fila "Toda la casa" del sidebar no es
  /// una habitación real y por eso tampoco lo pasa.
  final double? temperature;

  /// false ⇒ Switch deshabilitado (onChanged: null); onTap sigue vivo.
  final bool toggleEnabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle; // switch a la derecha
  final ValueChanged<double>? onBrightnessCommitted; // commit al soltar, 0..1

  /// OPT-IN: relieve neumórfico (home teléfono y sidebar tablet). Default false
  /// ⇒ render plano legacy. Con neo:true la card es SIEMPRE la almohada raised
  /// de neoBase (mismo material apagada/encendida); el ON sólo suma glow +
  /// anillo + ícono/dot de acento, sin fill de color.
  final bool neo;

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  /// Altura única de la fila. 88 = padding 12 + contenido 44 + slider 20 + 12.
  /// Las cards sin slider centran su contenido en la misma caja.
  static const double kHeight = 88;

  // Drag local del slider: mientras se arrastra (y 800 ms después de
  // soltar) se muestra _dragValue en lugar de widget.brightness, para que
  // el refresh del service no "pelee" con el dedo.
  double? _dragValue;
  Timer? _retainTimer;

  @override
  void dispose() {
    _retainTimer?.cancel();
    super.dispose();
  }

  void _onSliderChanged(double v) {
    _retainTimer?.cancel();
    _retainTimer = null;
    setState(() => _dragValue = v);
  }

  void _onSliderEnd(double v) {
    setState(() => _dragValue = v);
    widget.onBrightnessCommitted?.call(v);
    _retainTimer?.cancel();
    _retainTimer = Timer(const Duration(milliseconds: 800), () {
      _retainTimer = null;
      if (mounted) setState(() => _dragValue = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSlider = !widget.compact && widget.brightness != null;
    const height = kHeight;

    // El ACENTO de la card es el del sistema, no el color real de las luces
    // (ver doc de clase). Encendida se ilumina el ícono; apagada, el ícono
    // duerme en texto terciario.
    const Color accent = CceColors.accent;
    const double iconSize = 28;
    final Color glyphColor =
        widget.anyOn ? accent : CceColors.textTertiary;

    // Subtítulo de estado (pedido del dueño v1.62): SIN "Encendido/Apagado"
    // (ni "Sin luces") — los dots solos comunican el estado. Con EXACTAMENTE
    // UN dot activo se muestra su acción como texto; con 0 o 2+ dots, ''.
    // El subtitleOverride de "Toda la casa" (sidebar tablet) sigue ganando y
    // se muestra tal cual.
    //
    // Sin NADA que mostrar (ni dots ni texto) la fila del subtítulo NO se
    // renderiza y el título queda centrado en la card. Antes se dibujaba un
    // Text vacío que reservaba el line-height para que el título no se
    // recentrara al cambiar de estado; el dueño lo vio en pantalla (PR #22)
    // y prefirió "Living" y "Cocina" centrados. Efecto aceptado: una sala con
    // sensor recentra el título cuando aparece "Movimiento detectado".
    final activeDots = (widget.contactOpen ? 1 : 0) +
        (widget.motion ? 1 : 0) +
        (widget.anyOn ? 1 : 0);
    final subtitle = widget.subtitleOverride ??
        (activeDots == 1
            ? (widget.contactOpen
                ? 'Puerta abierta'
                : (widget.motion ? 'Movimiento detectado' : 'Luz encendida'))
            : '');
    // OJO: con 2+ dots el texto es '' pero SÍ hay dots que dibujar.
    final showStatus = activeDots > 0 || subtitle.isNotEmpty;
    // El subtítulo NO se tiñe: el dot que lo precede ya lleva el color del
    // estado. Pintar los dos del mismo color era decir dos veces lo mismo y
    // sumaba una fuente de color más a la lista.
    const Color subtitleColor = CceColors.textSecondary;

    final headerRow = Row(
      children: [
        // Ícono GRANDE extruido, SIN círculo. Reservamos el mismo ancho que el
        // viejo badge (44) con Center, para no mover el título (Expanded) ni el
        // switch: el layout de la card compacta (76px) queda intacto. El glyph
        // de 32 se pinta dentro de esa caja; Clip.none del EmbossedGlyph permite
        // que el relieve sobresalga sin recortarse.
        SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: EmbossedGlyph(
              size: iconSize,
              color: glyphColor,
              highlight: glyphColor,
              shadow: glyphColor,
              child: widget.iconBuilder?.call(glyphColor) ?? widget.icon!,
            ),
          ),
        ),
        SizedBox(width: CceSpace.md),
        // Nombre + subtítulo de estado (dos líneas).
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CceText.headline,
              ),
              if (showStatus) ...[
                SizedBox(height: CceSpace.xs),
                Row(
                  children: [
                    if (widget.contactOpen) ...[
                      const StatusDot(
                        CceColors.contact,
                        pulse: true,
                        semanticLabel: 'Puerta abierta',
                      ),
                      SizedBox(width: CceSpace.sm),
                    ],
                    if (widget.motion) ...[
                      const StatusDot(
                        CceColors.motion,
                        pulse: true,
                        semanticLabel: 'Movimiento',
                      ),
                      SizedBox(width: CceSpace.sm),
                    ],
                    // Punto AMARILLO fijo "luz encendida" (amberHi): siempre
                    // que anyOn, SIN cantidad y SIN pulso; convive con los
                    // dots de contact (naranja) y motion (azul) — ya no se
                    // suprime cuando hay sensores activos.
                    if (widget.anyOn) ...[
                      const StatusDot(
                        CceColors.amberHi,
                        semanticLabel: 'Luz encendida',
                      ),
                      SizedBox(width: CceSpace.sm),
                    ],
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CceText.caption.copyWith(
                          color: subtitleColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Badge de temperatura, entre el bloque de título y el switch. Va
        // FUERA del Expanded: con un nombre de habitación largo el que se
        // trunca es el título, nunca el badge. Su alto (una línea de 15px) es
        // menor que el del bloque título/subtítulo, así que NO estira la fila
        // y [kHeight] se mantiene igual con y sin badge — que es justamente la
        // decisión de diseño que documenta el header de este archivo.
        //
        // Se dibuja SIEMPRE que haya lectura, tenga la habitación luces o no:
        // es la columna que hace que todas las filas se lean como la misma
        // fila (CCE#59).
        if (widget.temperature != null) ...[
          SizedBox(width: CceSpace.sm),
          _TemperatureBadge(widget.temperature!),
        ],
        SizedBox(width: CceSpace.md),
        // Switch unificado (CceSwitch): tamaño natural del JBL, sin FittedBox.
        // El título Expanded cede ancho; entra al final del Row sin desbordar.
        //
        // Sin luces NO hay switch, pero SÍ su riel: queda el hueco vacío,
        // sin perilla ([CceSwitchEmptyTrack]). La silueta de la fila no
        // cambia — ícono, nombre, badge y control ocupan exactamente el mismo
        // lugar que en las demás — y la única diferencia es que no hay nada
        // que mover, que es justo lo que hay que decir. Un hueco mudo dejaba
        // la fila coja; un chevron le inventaba una acción que la card entera
        // ya ofrece con su onTap (CCE#59). [toggleEnabled] false es otra cosa:
        // el control existe, sólo está bloqueado momentáneamente, y ahí sí se
        // muestra deshabilitado — con perilla y al 40%.
        if (widget.lightsTotal == 0)
          const CceSwitchEmptyTrack()
        else
          CceSwitch(
            value: widget.anyOn,
            accent: accent,
            onChanged: widget.toggleEnabled ? widget.onToggle : null,
          ),
      ],
    );

    final card = CceCard(
      neo: widget.neo,
      color: widget.selected ? CceColors.surfaceHigh : CceColors.surface,
      radius: CceRadii.card,
      // Padding SIMÉTRICO. El 16/14 anterior desalineaba el switch respecto
      // del ícono por 2px — invisible de a uno, evidente en una lista larga.
      padding: EdgeInsets.symmetric(
        horizontal: CceSpace.lg,
        vertical: CceSpace.md,
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: showSlider
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: headerRow),
                CceBrightnessSlider(
                  height: 20,
                  thin: true,
                  showPercent: false,
                  value: (_dragValue ?? widget.brightness!)
                      .clamp(0.0, 1.0)
                      .toDouble(),
                  activeColor: accent,
                  // El riel vacío se ve entero (CceColors.sliderTrack): un
                  // hueco más oscuro que el lienzo desaparecía y la barra se
                  // leía cortada en el valor en vez de llena hasta él.
                  thinTrackColor: CceColors.sliderTrack,
                  onChanged: _onSliderChanged,
                  onChangeEnd: _onSliderEnd,
                ),
              ],
            )
          : Center(child: headerRow),
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          card,
          // Hairline de la card. Siempre presente: es lo que da estructura sin
          // sombras. Se refuerza sólo cuando la card está seleccionada
          // (sidebar tablet); el estado encendido ya lo dicen ícono, dot y
          // switch, y un anillo más sería decir lo mismo por cuarta vez.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.card),
                  border: Border.all(
                    color: widget.selected
                        ? CceColors.accent
                        : CceColors.stroke,
                    width: widget.selected ? 1.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lectura de temperatura de la habitación dentro de la [RoomCard].
///
/// Texto pelado, sin píldora ni color propio: la card ya comunica el estado
/// con el acento (ícono + dot + switch) y meterle una caja más sería sumar
/// ruido para decir un número. Cifras TABULARES ([CceText.data]) para que
/// pasar de 23.9 a 24.0 no mueva el layout, y un ancho mínimo que alinea las
/// lecturas normales en columna a lo largo de la lista sin recortar las largas
/// ("-10.5°" se expande en vez de truncarse).
class _TemperatureBadge extends StatelessWidget {
  const _TemperatureBadge(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    final text = '${value.toStringAsFixed(1)}°';
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 46),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.right,
        semanticsLabel: 'Temperatura ${value.toStringAsFixed(1)} grados',
        style: CceText.data.copyWith(color: CceColors.textSecondary),
      ),
    );
  }
}
