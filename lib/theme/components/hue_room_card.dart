import 'package:flutter/material.dart';

import '../cce_icons.dart';
import '../cce_tokens.dart';
import 'cce_switch.dart';
import 'hue_badge.dart';

/// Card del "grupo Hue": prende/apaga el room ENTERO (grouped_light) en una
/// sola llamada. Mismo molde que [LightCard] —ícono grande extruido, nombre y
/// franja inferior con [CceSwitch]— para que el grupo se maneje igual que una
/// luz, más la identidad de Hue: badge de marca arriba-izquierda + borde
/// naranja. El ícono es el del `archetype` del room, o sea el mismo que la room
/// tiene en la app de Philips Hue, y prende en verde cuando el room está
/// encendido (any_on, igual que Hue).
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

  /// Naranja de marca de Philips Hue (mismo #FF6A00 del badge/dashboard).
  static const Color _hueOrange = Color(0xFFFF6A00);

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
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ],
      );
    }

    return SizedBox(
      height: _height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: CceGradients.cardSurface(
              neo ? CceColors.neoBase : CceColors.cardOffHigh),
          borderRadius: borderRadius,
          border: Border.all(color: _hueOrange.withValues(alpha: 0.55), width: 1.2),
          boxShadow: neo ? CceShadows.cardFloat() : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: borderRadius,
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            glyph,
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
                // Badge de marca Hue (arriba-izquierda, como el pill "auto").
                const Positioned(top: 8, left: 8, child: HueBadge(width: 30, height: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
