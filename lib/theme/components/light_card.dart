import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Card compacta oscura (neumórfica). El color real de la luz NO llena el fondo:
/// cuando está encendida el color va al ÍCONO + un borde y un glow del color
/// (estilo "alerta" del sensor de movimiento), cuya intensidad sube con el
/// BRILLO. Apagada = card neutra; sin conexión = color muteado + ícono wifi-off.
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
  });

  final String name;
  /// Construye el ícono con el color de primer plano que decide la card
  /// (necesario para tintar SVGs de icons0, que no respetan IconTheme).
  final Widget Function(Color color) iconBuilder;
  final bool on;
  final double? brightness; // 0..1 → modula lightness/saturación del fill
  final Color? color; // color real de la luz (default CceColors.warm)
  final bool reachable;
  final String? stateLabel; // 'Apagada' | 'Sin conexión' | null (encendida)
  final double height;
  final ValueChanged<bool>? onToggle; // null ⇒ switch deshabilitado

  /// OPT-IN: relieve neumórfico (default false ⇒ render idéntico al actual).
  final bool neo;

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

    const double iconSize = 34;
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
    return SizedBox(
      height: height,
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
    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
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
        ),
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
                        // Ícono GRANDE extruido, SIN círculo (igual que
                        // RoomCard). EmbossedGlyph aplana y recolorea el glyph a
                        // [glyphColor] (cubre tanto el Icon de Material como el
                        // SVG de icons0 ya tintado por iconBuilder) y lo extruye
                        // con 2 capas ghost. FittedBox-ea a iconSize, así el
                        // size intrínseco que iconBuilder pasa al IconResolver es
                        // indiferente.
                        // Caja que HUGGEA el glyph (iconSize x iconSize) para
                        // preservar el footprint vertical del tile (altos fijos
                        // 138/156/174): el relieve sobresale via Clip.none del
                        // EmbossedGlyph, así que no necesita padding extra. Con
                        // el viejo box de 40 el nombre OFF (2 líneas + "Apagada")
                        // se comía el slack y colapsaba a ~0 líneas en el tile
                        // chico; con iconSize recupera la 2da línea.
                        SizedBox(
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
                        ),
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
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
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
                top: 8,
                right: 8,
                child: Icon(Icons.wifi_off, size: 14, color: fgSub),
              ),
          ],
        ),
      ),
    );
  }
}
