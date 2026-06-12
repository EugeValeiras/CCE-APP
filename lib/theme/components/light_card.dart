import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Card visual de una luz (SOLO presentacion; los gestos los pone LightTile).
/// Card VERTICAL estilo Hue: zona superior con ícono/nombre/estado centrados
/// y franja inferior apenas más oscura con el toggle a la izquierda. Cuando
/// la luz está encendida, toda la card se tiñe con el pastel de su color
/// real (gradiente vertical claro→profundo); sin conexión = pastel muteado.
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
    this.height = 200,
    this.onToggle,
  });

  final String name;
  final Widget icon;
  final bool on;
  final double? brightness; // 0..1 (solo informa el stateLabel del caller)
  final Color? color; // color real de la luz (default CceColors.warm)
  final bool reachable;
  final String? stateLabel; // '80%' | 'Apagada' | 'Sin conexión'
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
    final tinted = on;
    final fg = tinted ? CceTint.inkOnPastel : CceColors.textPrimary;
    final fgSub = tinted ? CceTint.inkOnPastelSub : CceColors.textSecondary;

    return SizedBox(
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tinted ? null : CceColors.cardOff,
          gradient: tinted ? CceGradients.huePastel([displayColor]) : null,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Zona superior: ícono + nombre + estado, centrados.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(color: fg),
                          child: icon,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            height: 1.15,
                            color: fg,
                          ),
                        ),
                        if (stateLabel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            stateLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: fgSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Franja inferior con el toggle a la izquierda (look Hue).
                Container(
                  height: 46,
                  color: tinted
                      ? Colors.black.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.045),
                  padding: const EdgeInsets.only(left: 8),
                  alignment: Alignment.centerLeft,
                  child: Transform.scale(
                    scale: 0.78,
                    alignment: Alignment.centerLeft,
                    child: Switch.adaptive(
                      value: on,
                      onChanged: onToggle,
                      activeTrackColor: tinted
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
                top: 10,
                right: 10,
                child: Icon(Icons.wifi_off, size: 15, color: fgSub),
              ),
          ],
        ),
      ),
    );
  }
}
