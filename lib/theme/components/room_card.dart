import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'brightness_slider.dart';
import 'cce_card.dart';
import 'cce_switch.dart';
import 'status_dot.dart';

/// Card de habitacion (sidebar tablet y lista phone), lenguaje NEOMÓRDICO:
/// SIEMPRE la MISMA almohada de [CceColors.neoBase] (relieve cardFloat +
/// gradiente sutil + bevel), tanto apagada como encendida. El estado ENCENDIDO
/// NO se pinta con un fill de color: se comunica con (a) un GLOW de acento que
/// se filtra por debajo de la almohada, (b) un anillo de acento de baja opacidad
/// en el borde, (c) el ícono teñido del color real de las luces y (d) un
/// StatusDot. La tipografía y la superficie nunca se tiñen.
///
/// Layout congelado (anti-overflow):
///  - compact == true (phone): altura FIJA 76, NUNCA renderiza slider.
///  - compact == false (tablet): 76 sin slider; 104 con slider thin (24).
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

  /// Promedio RGB simple de las paradas del gradiente (para decidir el fg).
  static Color _avgColor(List<Color> colors) {
    if (colors.isEmpty) return CceColors.warm;
    if (colors.length == 1) return colors.first;
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in colors) {
      r += (c.r * 255.0);
      g += (c.g * 255.0);
      b += (c.b * 255.0);
    }
    final n = colors.length;
    return Color.fromARGB(
        255, (r / n).round(), (g / n).round(), (b / n).round());
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
    final height = widget.compact ? 76.0 : (showSlider ? 104.0 : 76.0);

    // Colores de las luces ON (una parada por luz con color); 0/1 ⇒ tint
    // dominante o ámbar. Ya NO se pintan como fill: sólo derivan el ACENTO
    // (glow + anillo + ícono + dot) cuando hay alguna encendida.
    final colors = widget.tintColors.isNotEmpty
        ? widget.tintColors
        : [widget.tint ?? CceColors.warm];

    // Acento de la card encendida = color real de las luces NORMALIZADO (clamp
    // de sat/luz en HSL, conservando hue). Es la chispa permitida: tiñe el ícono
    // y el switch que prende — nunca la superficie ni la tipografía.
    final Color accent = CceTint.normalize(_avgColor(colors));

    // ÍCONO GRANDE EXTRUIDO (sin círculo): SIEMPRE sobre la goma oscura neoBase,
    // así que usa el par FIJO de CceEmboss (calibrado para oscuro, misma fuente
    // de verdad que el IconTheme global). En ON el glyph se tiñe del `accent`
    // (chispa de color); en OFF cae a neoTextSub (la almohada apagada "duerme",
    // reservando el blanco/acento para el estado activo).
    const double iconSize = 32;
    final Color glyphColor =
        widget.anyOn ? accent : CceColors.neoTextSub;
    final Color embHi = CceEmboss.highlight.color;
    final Color embSh = CceEmboss.shadow.color;

    // Subtítulo de estado (pedido del dueño v1.62): SIN "Encendido/Apagado"
    // (ni "Sin luces") — los dots solos comunican el estado. Con EXACTAMENTE
    // UN dot activo se muestra su acción como texto; con 0 o 2+ dots, ''
    // (el Text vacío conserva el line-height del caption para que el título
    // no se recentre al cambiar el estado). El subtitleOverride de "Toda la
    // casa" (sidebar tablet) sigue ganando y se muestra tal cual.
    final activeDots = (widget.contactOpen ? 1 : 0) +
        (widget.motion ? 1 : 0) +
        (widget.anyOn ? 1 : 0);
    final subtitle = widget.subtitleOverride ??
        (activeDots == 1
            ? (widget.contactOpen
                ? 'Puerta abierta'
                : (widget.motion ? 'Movimiento detectado' : 'Luz encendida'))
            : '');
    // El texto de acción única lleva el MISMO acento que su dot (naranja
    // contact / azul motion / amarillo amberHi): es la misma "chispa" puntual
    // permitida por el manual neumórfico — la superficie y el título no se
    // tiñen. El subtitleOverride ("Toda la casa") y el string vacío quedan
    // en textSecondary.
    final Color subtitleColor =
        (widget.subtitleOverride == null && activeDots == 1)
            ? (widget.contactOpen
                ? CceColors.contact
                : (widget.motion ? CceColors.motion : CceColors.amberHi))
            : CceColors.textSecondary;

    final headerRow = Row(
      children: [
        // Ícono GRANDE extruido, SIN círculo. Reservamos el mismo ancho que el
        // viejo badge (44) con Center, para no mover el título (Expanded) ni el
        // switch: el layout de la card compacta (76px) queda intacto. El glyph
        // de 32 se pinta dentro de esa caja; Clip.none del EmbossedGlyph permite
        // que el relieve sobresalga sin recortarse.
        SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: EmbossedGlyph(
              size: iconSize,
              color: glyphColor,
              highlight: embHi,
              shadow: embSh,
              child: widget.iconBuilder?.call(glyphColor) ?? widget.icon!,
            ),
          ),
        ),
        const SizedBox(width: 14),
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
                // Nombre con relieve neumórfico (como el título de la card JBL),
                // IGUAL apagada o encendida: tinta titleInk + CceText.embossShadows.
                // El texto NUNCA se tiñe — la superficie es siempre la misma goma.
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: CceText.titleInk,
                  shadows: CceText.embossShadows,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (widget.contactOpen) ...[
                    const StatusDot(
                      CceColors.contact,
                      pulse: true,
                      semanticLabel: 'Puerta abierta',
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (widget.motion) ...[
                    const StatusDot(
                      CceColors.motion,
                      pulse: true,
                      semanticLabel: 'Movimiento',
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Punto AMARILLO fijo "luz encendida" (amberHi): siempre que
                  // anyOn, SIN cantidad y SIN pulso; convive con los dots de
                  // contact (naranja) y motion (azul) — ya no se suprime cuando
                  // hay sensores activos.
                  if (widget.anyOn) ...[
                    const StatusDot(
                      CceColors.amberHi,
                      semanticLabel: 'Luz encendida',
                    ),
                    const SizedBox(width: 6),
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
          ),
        ),
        const SizedBox(width: 8),
        // Switch unificado (CceSwitch): tamaño natural del JBL, sin FittedBox.
        // El título Expanded cede ancho; entra al final del Row sin desbordar.
        CceSwitch(
          value: widget.anyOn,
          accent: accent,
          onChanged: (!widget.toggleEnabled || widget.lightsTotal == 0)
              ? null
              : widget.onToggle,
        ),
      ],
    );

    final card = CceCard(
      // SIEMPRE la almohada raised de neoBase (raisedDecoration: gradiente sutil
      // + cardFloat + bevel), apagada O encendida: misma goma continua. El ON no
      // cambia la superficie — sólo el glow/anillo/ícono/dot de acento (fuera de
      // CceCard). En legacy (neo:false) se conserva el render plano histórico.
      neo: widget.neo,
      color: widget.neo
          ? CceColors.neoBase
          : (widget.selected ? CceColors.surfaceHigh : CceColors.cardOff),
      radius: CceRadii.hueCard,
      padding: EdgeInsets.fromLTRB(16, showSlider ? 10 : 8, 14, 8),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: showSlider
          ? Column(
              children: [
                Expanded(child: headerRow),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CceBrightnessSlider(
                    height: 24,
                    thin: true,
                    showPercent: false,
                    value: (_dragValue ?? widget.brightness!)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    // Riel hundido en la goma (canal oscuro) + relleno con el
                    // ACENTO real de la sala (coherente con glyph/dot), en vez
                    // de blanco sobre un track derivado del viejo fill pastel.
                    activeColor: accent,
                    thinTrackColor: CceColors.neoDark,
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderEnd,
                  ),
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
          // SIN glow de acento: el relieve lo da CceCard (raisedDecoration) y
          // el estado ON lo marca el SWITCH (que prende del color del ícono) +
          // el ícono tinteado. No se derrama luz fuera de la card.
          card,
          // Borde superpuesto. PRIORIDAD:
          //  1) selección (tablet) → hairline blanco 0.80, width 1.4 (gana).
          //  2) encendido sin selección → ANILLO de acento sutil 0.22, width 1.2:
          //     el "rim" de color que insinúa el estado sin rellenar nada.
          //  3) resto → transparente.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.hueCard),
                  // Sin anillo de "encendido": el estado ON lo marca el switch
                  // (que prende) + el ícono tinteado. Sólo la selección (tablet)
                  // dibuja un hairline blanco.
                  border: Border.all(
                    color: widget.selected
                        ? Colors.white.withValues(alpha: 0.80)
                        : Colors.transparent,
                    width: 1.4,
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
