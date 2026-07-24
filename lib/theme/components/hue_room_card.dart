import 'package:flutter/material.dart';

import '../cce_tokens.dart';
import 'hue_badge.dart';

/// Card del "grupo Hue": prende/apaga el room ENTERO (grouped_light) en una
/// sola llamada. Mismo molde que [SceneCard] (132 de alto, círculo + nombre)
/// pero con la identidad de Hue: badge de marca arriba-izquierda + borde
/// naranja. El círculo se pone verde cuando el room está encendido (any_on,
/// igual que la app de Philips Hue) y gris cuando está apagado.
class HueRoomCard extends StatelessWidget {
  const HueRoomCard({
    super.key,
    required this.name,
    required this.on,
    required this.onTap,
    this.busy = false,
    this.neo = false,
  });

  final String name;

  /// Estado del room: true = alguna luz encendida, false = todas apagadas,
  /// null = desconocido (room sin luces).
  final bool? on;
  final bool busy;
  final bool neo;
  final VoidCallback onTap;

  static const double _height = 132;
  static const double _circle = 60;

  /// Naranja de marca de Philips Hue (mismo #FF6A00 del badge/dashboard).
  static const Color _hueOrange = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(CceRadii.hueScene);
    final isOn = on == true;
    final accent = isOn ? CceColors.ok : CceColors.textTertiary;

    Widget circle = Container(
      width: _circle,
      height: _circle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.cardOffHigh,
        border: Border.all(
          color: isOn
              ? CceColors.ok.withValues(alpha: 0.55)
              : CceColors.stroke,
          width: 1.2,
        ),
      ),
      child: Icon(Icons.power_settings_new, color: accent, size: 26),
    );
    if (busy) {
      circle = Stack(
        alignment: Alignment.center,
        children: [
          circle,
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
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                    child: Column(
                      children: [
                        circle,
                        const SizedBox(height: 8),
                        Expanded(
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
                // Badge de marca Hue (arriba-izquierda, como el pill "auto").
                const Positioned(top: 8, left: 8, child: HueBadge(width: 30, height: 15)),
                // Estado ON/OFF (arriba-derecha).
                if (on != null)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Text(
                      isOn ? 'ON' : 'OFF',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
