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
    final b = (brightness ?? 1.0).clamp(0.0, 1.0).toDouble();

    // La card es SIEMPRE oscura (apagada y encendida). Cuando está ENCENDIDA el
    // color real de la luz NO llena el fondo: va en el ÍCONO + un borde y un
    // glow del color (estilo "alerta" del sensor de movimiento / dimmer), cuya
    // intensidad sube con el brillo. Apagada = card neutra raised.
    final fgSub = on ? displayColor : CceColors.textSecondary; // estado en color

    // Ícono: color de la luz cuando ON; blanco neutro cuando OFF. Relieve goma
    // (par fijo CceEmboss) en ambos casos porque la superficie es oscura.
    const double iconSize = 34;
    final Color glyphColor = on ? displayColor : CceColors.textPrimary;
    final embHi = CceEmboss.highlight.color;
    final embSh = CceEmboss.shadow.color;

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Card oscura SIEMPRE (superficie convexa). El color de la luz va al
          // borde + glow cuando ON (intensidad ∝ brillo); bevel hairline OFF.
          gradient: CceGradients.cardSurface(surfaceBase),
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: on
              ? Border.all(
                  color: displayColor.withValues(alpha: 0.50 + 0.30 * b),
                  width: 1.6,
                )
              : Border.all(color: CceColors.cardBevel),
          boxShadow: [
            if (neo) ...CceShadows.cardFloat(),
            if (on)
              BoxShadow(
                color: displayColor.withValues(alpha: 0.18 + 0.22 * b),
                blurRadius: 14 + 10 * b,
                spreadRadius: 0,
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
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              height: 1.15,
                              color: CceColors.textPrimary,
                            ),
                          ),
                        ),
                        if (stateLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            stateLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: fgSub,
                            ),
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
                  child: CceSwitch(value: on, onChanged: onToggle),
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
