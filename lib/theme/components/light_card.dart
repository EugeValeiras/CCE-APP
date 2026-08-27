import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Card compacta oscura (neumórfica). El color real de la luz NO llena el fondo:
/// cuando está encendida el color va al ÍCONO + un borde y un glow del color
/// (estilo "alerta" del sensor de movimiento), cuya intensidad sube con el
/// BRILLO. Apagada = card neutra; sin conexión = color muteado + ícono wifi-off.
///
/// Dos layouts sobre el mismo material:
///  - vertical (default): ícono grande, nombre a dos líneas y franja inferior
///    con el switch. Es el tile de la tablet y de la tab de luces.
///  - [compact]: fila de [kCompactHeight] para la grilla de DOS columnas del
///    detalle de habitación en el teléfono — ícono y switch arriba, nombre
///    abajo en una línea. Con tres columnas de 113 px los nombres de dos
///    líneas se cortaban a media altura ("Front 3 DOWN" partido); con dos
///    columnas de 179 el nombre entra entero.
class LightCard extends StatelessWidget {
  const LightCard({
    super.key,
    required this.name,
    required this.iconBuilder,
    required this.on,
    this.brightness,
    this.color,
    this.reachable = true,
    this.stateLabel,
    this.height = 132,
    this.onToggle,
    this.neo = false,
    this.automationCount = 0,
    this.compact = false,
  });

  /// Altura del layout [compact]: 14 (padding) + 30 (fila del switch) + 6
  /// (respiro) + 22 (nombre) + 14 (padding) = 86. Medida de componente, como
  /// `RoomCard.kHeight`. Era 78 con padding 12 y sin respiro: el dueño lo vio
  /// apretado (el nombre a 12 px del borde y las filas casi tocándose) y
  /// aceptó ver 12 luces en pantalla en vez de 14 a cambio del aire.
  static const double kCompactHeight = 86;

  /// Padding interno del tile compacto Y gap de la grilla que lo hospeda: el
  /// mismo aire adentro y entre tiles es lo que hace que la grilla se lea
  /// como un ritmo. Fuera de la escala base 4 de [CceSpace] a propósito
  /// (pedido del dueño mirando la pantalla); vive acá y no en los tokens
  /// porque es una medida de ESTE componente.
  static const double kCompactPadding = 14;

  /// Respiro entre la fila ícono/switch y el nombre.
  static const double _compactBreath = 6;

  final String name;
  /// Construye el ícono con el color de primer plano que decide la card
  /// (necesario para tintar SVGs de icons0, que no respetan IconTheme).
  final Widget Function(Color color) iconBuilder;
  final bool on;
  final double? brightness; // 0..1 → modula lightness/saturación del fill
  final Color? color; // color real de la luz (default CceColors.warm)
  final bool reachable;

  /// 'Sin conexión' | null. Ya no lleva "Apagada": el switch lo dice, y el
  /// sistema prohíbe decir lo mismo dos veces.
  final String? stateLabel;
  final double height;
  final ValueChanged<bool>? onToggle; // null ⇒ switch deshabilitado

  /// OPT-IN: relieve neumórfico (default false ⇒ render idéntico al actual).
  final bool neo;

  /// Cuántas automatizaciones ACTIVAS gobiernan esta luz. > 0 dibuja el
  /// indicador de rayo.
  ///
  /// Existe porque frente a un dispositivo la pregunta más frecuente es "¿esto
  /// lo maneja algo?" — y para contestarla había que ir a la lista general de
  /// automatizaciones y leer los triggers y las acciones de cada una.
  final int automationCount;

  /// Layout de fila para la grilla de dos columnas (ver doc de la clase).
  final bool compact;

  /// Mutea el color para luces sin conexión (sat × 0.4).
  static Color _muted(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.4).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final base = color ?? CceColors.warm;
    final displayColor = reachable ? base : _muted(base);
    final surfaceBase = neo ? CceColors.neoBase : CceColors.cardOff;

    final double iconSize = compact ? 24 : 34;
    final embHi = CceEmboss.highlight.color;
    final embSh = CceEmboss.shadow.color;

    // TRANSICIÓN ENCENDIDO ↔ APAGADO.
    //
    // `t` va de 0 (apagada) a 1 (encendida) e interpola TODO lo que cambia:
    // borde, halo, color del ícono y del texto de estado. Antes no había
    // ninguna animación acá: la card saltaba de un frame al siguiente, y el
    // único movimiento venía de un halo difuso de 900 ms que se disparaba
    // DESPUÉS (PulseOnUpdate) — o sea, el cambio era un corte seco y luego
    // llegaba tarde un fantasma que ya no correspondía a nada.
    //
    // Ahora la transición ES el feedback: la luz se enciende en la pantalla al
    // mismo tiempo que en la habitación, y a la misma velocidad a la que una
    // lámpara real levanta.
    final bool lit = on && reachable;
    final double h = compact ? kCompactHeight : height;
    return SizedBox(
      height: h,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: lit ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          final Color borderColor = Color.lerp(
            CceColors.stroke,
            displayColor.withValues(alpha: 0.75),
            t,
          )!;
          final Color glyphColor =
              Color.lerp(CceColors.textSecondary, displayColor, t)!;
          final Color fgSub =
              Color.lerp(CceColors.textSecondary, displayColor, t)!;
          return _buildCard(
            t: t,
            borderColor: borderColor,
            glyphColor: glyphColor,
            fgSub: fgSub,
            displayColor: displayColor,
            surfaceBase: surfaceBase,
            iconSize: iconSize,
            embHi: embHi,
            embSh: embSh,
          );
        },
      ),
    );
  }

  BoxDecoration _decoration({
    required double t,
    required Color borderColor,
    required Color displayColor,
    required Color surfaceBase,
  }) {
    return BoxDecoration(
      gradient: CceGradients.cardSurface(surfaceBase),
      borderRadius: BorderRadius.circular(CceRadii.card),
      // Sin conexión NO lleva borde de encendido aunque el último estado
      // conocido sea `on`: una lámpara inalcanzable no está iluminando
      // nada, y mostrarla igual que una encendida es afirmar algo que la
      // app no sabe.
      border: Border.all(color: borderColor, width: 1 + 0.5 * t),
      boxShadow: [
        if (neo) ...CceShadows.cardFloat(),
        // El halo entra con la transición, no después de ella.
        if (t > 0.01)
          BoxShadow(
            color: displayColor.withValues(alpha: 0.16 * t),
            blurRadius: 20,
            offset: const Offset(0, 4),
            spreadRadius: -6,
          ),
      ],
    );
  }

  Widget _glyph({
    required double iconSize,
    required Color glyphColor,
    required Color embHi,
    required Color embSh,
  }) {
    // Ícono extruido, SIN círculo (igual que RoomCard). EmbossedGlyph aplana
    // y recolorea el glyph a [glyphColor] (cubre tanto el Icon de Material
    // como el SVG de icons0 ya tintado por iconBuilder). FittedBox-ea a
    // iconSize, así el size intrínseco que iconBuilder pasa al IconResolver
    // es indiferente.
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: Center(
        child: EmbossedGlyph(
          size: iconSize,
          color: glyphColor,
          highlight: embHi,
          shadow: embSh,
          child: iconBuilder(glyphColor),
        ),
      ),
    );
  }

  Widget _buildCard({
    required double t,
    required Color borderColor,
    required Color glyphColor,
    required Color fgSub,
    required Color displayColor,
    required Color surfaceBase,
    required double iconSize,
    required Color embHi,
    required Color embSh,
  }) {
    final decoration = _decoration(
      t: t,
      borderColor: borderColor,
      displayColor: displayColor,
      surfaceBase: surfaceBase,
    );
    final glyph = _glyph(
      iconSize: iconSize,
      glyphColor: glyphColor,
      embHi: embHi,
      embSh: embSh,
    );

    if (compact) {
      // El Border de la decoración se descuenta como padding interno: los
      // 14 px se miden desde el canto EXTERIOR (que es como se mide en el
      // diseño), así que se le resta el ancho del borde — que además anima
      // de 1 a 1.5 al encender. Sin esto el contenido desbordaba 1 px.
      final double border = 1 + 0.5 * t;
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        padding: EdgeInsets.all(kCompactPadding - border),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                glyph,
                const Spacer(),
                // Contexto, no estado: en texto terciario para no competir
                // con el color de la luz.
                if (automationCount > 0) ...[
                  const Icon(Icons.bolt,
                      size: 13, color: CceColors.textTertiary),
                  if (automationCount > 1)
                    Text(
                      '$automationCount',
                      style: CceText.caption.copyWith(
                        color: CceColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  SizedBox(width: CceSpace.sm),
                ],
                // El switch PRENDE con el color real de la luz (mismo
                // displayColor que tiñe el ícono), no con el ámbar por
                // defecto.
                CceSwitch(
                    value: on, accent: displayColor, onChanged: onToggle),
              ],
            ),
            // Respiro fijo + Spacer: el nombre se apoya en el borde inferior
            // y nunca queda a menos de 6 px de la fila del switch.
            const SizedBox(height: _compactBreath),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CceText.headline,
                  ),
                ),
                // Sin conexión: el glyph, junto al nombre (como Hue).
                if (!reachable) ...[
                  SizedBox(width: CceSpace.sm),
                  CceIcon(CceIcons.wifiOff,
                      size: 14, color: fgSub, emboss: false),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        child: Stack(
          children: [
            // Contenido.
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Caja que HUGGEA el glyph (iconSize x iconSize) para
                        // preservar el footprint vertical del tile (altos
                        // fijos 138/156/174).
                        glyph,
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            // height 1.15: el interlineado por defecto del
                            // sistema (1.2) hace que un nombre de dos líneas
                            // no entre en el tile y se corte a mitad.
                            style: CceText.label.copyWith(
                              color: CceColors.textPrimary,
                              height: 1.15,
                            ),
                          ),
                        ),
                        if (stateLabel != null) ...[
                          SizedBox(height: CceSpace.xs),
                          Text(
                            stateLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CceText.caption.copyWith(color: fgSub),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Franja inferior: separada por un borde superior; el switch
                // (CceSwitch, tamaño natural del JBL) va centrado. Altura 56
                // para alojar el switch natural sin que el clipBehavior recorte
                // el track (antes 48 con Transform.scale 0.95).
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: CceColors.strokeSoft)),
                  ),
                  alignment: Alignment.center,
                  // El switch PRENDE con el color real de la luz (mismo
                  // displayColor que tiñe el ícono), no con el ámbar por defecto.
                  child: CceSwitch(
                      value: on, accent: displayColor, onChanged: onToggle),
                ),
              ],
            ),
            // Sin conexión: ícono chico arriba a la derecha (como Hue).
            if (!reachable)
              Positioned(
                top: CceSpace.sm,
                right: CceSpace.sm,
                child: CceIcon(CceIcons.wifiOff,
                    size: 14, color: fgSub, emboss: false),
              ),
            // "Algo maneja esta luz". Arriba a la IZQUIERDA para no pelear con
            // el indicador de sin-conexión, y en texto terciario porque es
            // contexto, no estado: no debe competir con el color de la luz,
            // que es lo que el tile viene a comunicar.
            if (automationCount > 0)
              Positioned(
                top: CceSpace.sm,
                left: CceSpace.sm,
                child: Row(
                  children: [
                    const Icon(Icons.bolt,
                        size: 13, color: CceColors.textTertiary),
                    if (automationCount > 1)
                      Text(
                        '$automationCount',
                        style: CceText.caption.copyWith(
                          color: CceColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
