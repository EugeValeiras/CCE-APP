import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';
import 'hue_badge.dart';
import 'light_card.dart';

/// Card del "grupo Hue": prende/apaga el room ENTERO (grouped_light) en una
/// sola llamada. Mismo molde que [LightCard] —ícono extruido y switch— para
/// que el grupo se maneje igual que una luz.
///
/// El ícono es el del `archetype` de la room (el mismo que tiene en la app de
/// Philips), NUNCA el logo de la marca: system.md manda que las marcas de
/// terceros vivan en el detalle del dispositivo, no en listas ni grillas.
/// En el layout vertical (tablet) el badge de Hue sigue ocupando el lugar del
/// nombre; en [compact] (grilla de dos columnas del teléfono) va el nombre
/// del room, como en cualquier otra luz.
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
    this.compact = false,
  });

  final String name;

  /// Estado del room: true = alguna luz encendida, false = todas apagadas,
  /// null = desconocido (room sin luces).
  final bool? on;

  /// `metadata.archetype` del room de Hue (living_room, bedroom, front_door…).
  final String? archetype;

  final bool busy;
  final bool neo;

  /// Fila de [LightCard.kCompactHeight] (grilla de dos columnas del phone).
  final bool compact;
  final VoidCallback onTap;

  static const double _iconSize = 34;

  /// Alto de la franja del switch. Mismo valor que [LightCard], para que el
  /// switch quede a la misma altura cuando las dos cards conviven.
  static const double _switchBar = 56;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        BorderRadius.circular(compact ? CceRadii.card : CceRadii.hueScene);
    final isOn = on == true;
    // Encendido = acento del sistema. El verde de Hue (`ok`) es el color
    // semántico de "correcto" en esta app: usarlo para "hay luz prendida"
    // decía otra cosa, y además metía un cuarto color en la grilla.
    final accent = isOn ? CceColors.accent : CceColors.textTertiary;
    final double iconSize = compact ? 24 : _iconSize;

    Widget glyph = SizedBox(
      width: iconSize,
      height: iconSize,
      child: Center(
        child: EmbossedGlyph(
          size: iconSize,
          color: accent,
          highlight: CceEmboss.highlight.color,
          shadow: CceEmboss.shadow.color,
          child: CceIcon(
            CceIcons.hueRoomIcon(archetype),
            size: iconSize,
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
          SizedBox(
            width: compact ? 18 : 22,
            height: compact ? 18 : 22,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: CceColors.textPrimary,
            ),
          ),
        ],
      );
    }

    final toggle = CceSwitch(
      value: isOn,
      accent: CceColors.accent,
      onChanged: busy ? null : (_) => onTap(),
    );

    final Widget body;
    if (compact) {
      body = Padding(
        padding: EdgeInsets.all(CceSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [glyph, const Spacer(), toggle]),
            const Spacer(),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.headline,
            ),
          ],
        ),
      );
    } else {
      body = Column(
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
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: CceColors.strokeSoft)),
            ),
            alignment: Alignment.center,
            child: toggle,
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
          child: body,
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
    // no puede liderar la jerarquía de una pantalla propia.
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
