import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';
import 'hue_badge.dart';

/// Card del "grupo Hue": prende/apaga el room ENTERO (grouped_light) en una
/// sola llamada. Mismo molde que [LightCard] —ícono grande extruido, nombre y
/// franja inferior con [CceSwitch]— para que el grupo se maneje igual que una
/// luz, más la identidad de Hue: el badge de marca acompaña al nombre y, cuando
/// la room está ENCENDIDA, el borde es el gradiente arcoíris de Philips. Apagada
/// no lleva borde, como el resto de las cards. El ícono es el del `archetype`
/// del room, o sea el mismo que la room tiene en la app de Philips Hue, y prende
/// en verde cuando el room está encendido (any_on, igual que Hue).
class HueRoomCard extends StatelessWidget {
  const HueRoomCard({
    super.key,
    required this.name,
    required this.on,
    required this.onTap,
    this.archetype,
    this.busy = false,
    this.neo = false,
  });

  final String name;

  /// Estado del room: true = alguna luz encendida, false = todas apagadas,
  /// null = desconocido (room sin luces).
  final bool? on;

  /// `metadata.archetype` del room de Hue (living_room, bedroom, front_door…).
  final String? archetype;

  final bool busy;
  final bool neo;
  final VoidCallback onTap;

  static const double _height = 132;
  static const double _iconSize = 34;

  /// Alto de la franja del switch. Mismo valor que [LightCard], para que el
  /// switch quede a la misma altura cuando las dos cards conviven.
  static const double _switchBar = 56;

  /// Grosor del borde de marca cuando la room está encendida.
  static const double _borderWidth = 1.4;

  /// Gradiente de marca de Philips Hue: los MISMOS stops del logo (ver
  /// [HueBadge]), para que el borde y el badge sean el mismo arcoíris y no dos
  /// interpretaciones parecidas. De izquierda a derecha, igual que el logo.
  static const LinearGradient _hueBrandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF00B1F3),
      Color(0xFF40D6AC),
      Color(0xFF9FD045),
      Color(0xFFFFC500),
      Color(0xFFFFA200),
      Color(0xFFFE3503),
    ],
    stops: [0.0, 0.274, 0.391, 0.611, 0.749, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(CceRadii.hueScene);
    final isOn = on == true;
    // Encendido tiñe de verde (ícono + switch); apagado deja el glyph neutro,
    // igual que LightCard con una luz apagada.
    final accent = isOn ? CceColors.ok : CceColors.textPrimary;

    Widget glyph = SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Center(
        child: EmbossedGlyph(
          size: _iconSize,
          color: accent,
          highlight: CceEmboss.highlight.color,
          shadow: CceEmboss.shadow.color,
          child: CceIcon(
            CceIcons.hueRoomIcon(archetype),
            size: _iconSize,
            color: accent,
            emboss: false, // el relieve lo pone EmbossedGlyph
          ),
        ),
      ),
    );
    if (busy) {
      glyph = Stack(
        alignment: Alignment.center,
        children: [
          glyph,
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    // Borde con el GRADIENTE de marca sólo cuando está encendida. Flutter no
    // sabe pintar un Border con gradiente, así que el truco es un Container con
    // el gradiente + _borderWidth de padding, y la card real encima tapando el
    // centro: lo que asoma por los bordes ES el borde. Apagada no lleva
    // contenedor externo y queda sin borde, como el resto de las cards.
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: CceGradients.cardSurface(
          neo ? CceColors.neoBase : CceColors.cardOffHigh,
        ),
        borderRadius: borderRadius,
        boxShadow: neo && !isOn ? CceShadows.cardFloat() : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: borderRadius,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      glyph,
                      const SizedBox(height: 6),
                      // El badge va EN LA LÍNEA del nombre, no flotando
                      // en la esquina: ahí rompía la simetría de la card
                      // (era el único elemento fuera del eje central).
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const HueBadge(width: 26, height: 13),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                  height: 1.15,
                                  color: CceColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Franja inferior con el switch, igual que LightCard: es el
              // switch el que comunica el estado, así que la card ya no
              // necesita el texto ON/OFF que tenía arriba a la derecha.
              Container(
                height: _switchBar,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: CceSwitch(
                  value: isOn,
                  accent: CceColors.ok,
                  onChanged: busy ? null : (_) => onTap(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Encendida: el borde ES el gradiente de marca, con un glow suave del mismo
    // color para que se lea a distancia en la grilla.
    if (!isOn) return SizedBox(height: _height, child: card);
    return SizedBox(
      height: _height,
      child: Container(
        padding: const EdgeInsets.all(_borderWidth),
        decoration: BoxDecoration(
          gradient: _hueBrandGradient,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF40D6AC).withValues(alpha: 0.22),
              blurRadius: 14,
            ),
          ],
        ),
        child: card,
      ),
    );
  }
}
