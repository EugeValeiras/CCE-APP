import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';
import 'hue_badge.dart';

/// Card del "grupo Hue": prende/apaga el room ENTERO (grouped_light) en una
/// sola llamada. Mismo molde que [LightCard] —ícono grande extruido y franja
/// inferior con [CceSwitch]— para que el grupo se maneje igual que una luz.
///
/// A diferencia de LightCard NO muestra el nombre: en su lugar va el badge de
/// Hue. La room ya está identificada por el plano en el que estás parado y por
/// el ícono de su `archetype` (el mismo que tiene en la app de Philips), así que
/// el texto sólo sumaba ruido; [name] sobrevive como semantics.
///
/// Encendida, lleva hairline de acento y el glyph prende en acento — igual que
/// cualquier card activa del sistema. Apagada no lleva borde, como el resto.
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

  static const double _iconSize = 34;

  /// Alto de la franja del switch. Mismo valor que [LightCard], para que el
  /// switch quede a la misma altura cuando las dos cards conviven.
  static const double _switchBar = 56;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(CceRadii.hueScene);
    final isOn = on == true;
    // Encendido = acento del sistema. El verde de Hue (`ok`) es el color
    // semántico de "correcto" en esta app: usarlo para "hay luz prendida"
    // decía otra cosa, y además metía un cuarto color en la grilla.
    final accent = isOn ? CceColors.accent : CceColors.textTertiary;

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
                      // El badge OCUPA el lugar del nombre. La room ya está
                      // identificada por el plano en el que estás parado y por
                      // el ícono de su archetype: repetir el texto sólo sumaba
                      // ruido. Queda como semantics para el lector de pantalla,
                      // que no tiene ese contexto visual.
                      Semantics(
                        label: name,
                        child: const HueBadge(width: 40, height: 20),
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
                      color: CceColors.strokeSoft,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: CceSwitch(
                  value: isOn,
                  accent: CceColors.accent,
                  onChanged: busy ? null : (_) => onTap(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Encendida: hairline de acento, igual que cualquier otra card activa del
    // sistema.
    //
    // Antes el borde era el arcoíris completo de Philips más un glow verde.
    // El resultado era que la card más llamativa de la pantalla —la que se
    // llevaba la mirada antes que la temperatura, las escenas o cualquier luz—
    // era la marca de un proveedor. Una marca de terceros puede identificar,
    // no puede liderar la jerarquía de una pantalla propia; el badge de Hue,
    // que sigue adentro, ya dice de quién es el grupo.
    //
    // Sin alto propio: lo fija el grid que la hospeda.
    if (!isOn) return card;
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: CceColors.accent, width: 1.5),
          borderRadius: borderRadius,
        ),
        child: card,
      ),
    );
  }
}
