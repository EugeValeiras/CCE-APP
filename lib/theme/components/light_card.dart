import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Card compacta estilo Hue (mismo tamaño que las scene cards): el BRILLO se
/// representa como un RELLENO de color que sube desde abajo (no como texto %).
/// Apagada = card oscura; encendida = relleno pastel del color real con altura
/// proporcional al brillo; sin conexión = color muteado + ícono wifi-off.
class LightCard extends StatelessWidget {
  const LightCard({
    super.key,
    required this.name,
    required this.icon,
    required this.on,
    this.brightness,
    this.color,
    this.reachable = true,
    this.stateLabel,
    this.height = 132,
    this.onToggle,
  });

  final String name;
  final Widget icon;
  final bool on;
  final double? brightness; // 0..1 → altura del relleno
  final Color? color; // color real de la luz (default CceColors.warm)
  final bool reachable;
  final String? stateLabel; // 'Apagada' | 'Sin conexión' | null (encendida)
  final double height;
  final ValueChanged<bool>? onToggle; // null ⇒ switch deshabilitado

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
    // Altura del relleno: brillo real (mínimo visible 0.10 para que se note).
    final double fill =
        on ? (brightness ?? 1.0).clamp(0.10, 1.0).toDouble() : 0.0;
    // Texto oscuro solo si el relleno cubre el centro de la card (~mitad).
    final darkText = on && fill >= 0.5;
    final fg = darkText ? CceTint.inkOnPastel : CceColors.textPrimary;
    final fgSub =
        darkText ? CceTint.inkOnPastelSub : CceColors.textSecondary;

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CceColors.cardOff,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
        ),
        child: Stack(
          children: [
            // Relleno de brillo: sube desde abajo, gradiente pastel del color.
            if (on)
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: fill,
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: CceGradients.huePastel([displayColor]),
                    ),
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
                        IconTheme.merge(
                          data: IconThemeData(color: fg, size: 24),
                          child: icon,
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
                // va centrado y grande.
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: on
                            ? Colors.black.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Transform.scale(
                    scale: 0.95,
                    child: Switch.adaptive(
                      value: on,
                      onChanged: onToggle,
                      activeTrackColor: darkText
                          ? CceTint.inkOnPastel.withValues(alpha: 0.30)
                          : null,
                      thumbColor:
                          const WidgetStatePropertyAll<Color>(Colors.white),
                    ),
                  ),
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
