import 'package:flutter/material.dart';

import '../cce_tokens.dart';
import 'cce_switch.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Card compacta estilo Hue (mismo tamaño que las scene cards): encendida =
/// card SIEMPRE llena con gradiente vertical del color real (CceGradients
/// .lightFull); el BRILLO modula lightness/saturación, NO la altura (sin línea
/// dura). Apagada = card oscura; sin conexión = gris apagado + ícono wifi-off.
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
    // Color representativo del fill (promedio top/mid) para decidir contraste.
    final fgBase = on
        ? CceGradients.lightFullSampleColor(displayColor, brightness ?? 1.0, reachable)
        : (neo ? CceColors.neoBase : CceColors.cardOff);
    final fg = on ? CceTint.textOn(fgBase) : CceColors.textPrimary;
    final fgSub = on ? CceTint.subTextOn(fgBase) : CceColors.textSecondary;

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: neo ? CceColors.neoBase : CceColors.cardOff,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          boxShadow: neo ? CceShadows.neo() : null,
        ),
        child: Stack(
          children: [
            // Fill COMPLETO estilo Hue: card siempre llena cuando on, gradiente
            // vertical modulado por brillo (sin línea dura). Off/neo intactos.
            if (on)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: CceGradients.lightFull(
                        displayColor, brightness ?? 1.0, reachable),
                  ),
                ),
              ),
            // Contenido.
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 26,
                          child: Center(child: iconBuilder(fg)),
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              height: 1.15,
                              color: fg,
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
                        color: (on && fgBase.computeLuminance() > 0.45)
                            ? Colors.black.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.10),
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
