import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../views/thermostat_screen.dart';
import 'pulse_on_update.dart';

/// Tile de termostato (Tuya cat 'wk'). Muestra el setpoint grande + la temp
/// ambiente en la franja inferior; el acento sale del modo de sistema
/// (calor = cálido/llama, frío = info/copo). Tap abre [ThermostatScreen].
/// Mismo lenguaje visual que [SensorTile] (glyph extruido + franja de estado).
class ThermostatTile extends StatelessWidget {
  final Device device;
  final DevicesService service;
  final TileSize size;

  const ThermostatTile({
    super.key,
    required this.device,
    required this.service,
    this.size = TileSize.medium,
    this.neo = false,
    this.onOpen,
  });

  /// OPT-IN: relieve neumórfico de la card (default false).
  final bool neo;

  /// TABLET: abre el control INLINE en el panel derecho (igual que TV/JBL). Si
  /// es null (teléfono), cae al `Navigator.push(ThermostatScreen)` de siempre.
  final VoidCallback? onOpen;

  bool _isCool(DeviceState s) {
    final m = (s.systemMode ?? '').toLowerCase();
    return m.contains('cool') || m.contains('frio') || m.contains('frío');
  }

  @override
  Widget build(BuildContext context) {
    final s = device.state;
    final on = s.on;
    final cool = _isCool(s);
    // Acento semántico: ON usa el color del modo; OFF gris neutro.
    final Color color =
        on ? (cool ? CceColors.info : CceColors.warm) : CceColors.textSecondary;
    final String svg = cool ? CceIcons.snowflake : CceIcons.flame;

    final target = s.targetTemp;
    final current = s.currentTemp;
    final String targetLabel =
        target != null ? '${target.toStringAsFixed(1)}°' : '—';
    final String stateLabel = !s.reachable
        ? 'Sin conexión'
        : (on
            ? (current != null
                ? 'Actual ${current.toStringAsFixed(1)}°'
                : 'Encendido')
            : 'Apagado');

    final double glyphSize = size.iconSize + 8;
    final Color glyphColor = on ? color : CceColors.textTertiary;

    final tile = PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: CceRadii.hueCard,
      child: Container(
        height: size.sensorTileHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: CceGradients.cardSurface(
              neo ? CceColors.neoBase : CceColors.cardOff),
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: Border.all(color: CceColors.cardBevel),
          boxShadow: neo ? CceShadows.cardFloat() : null,
        ),
        child: Column(
          children: [
            // Zona superior: ícono de modo extruido + setpoint grande.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: EmbossedGlyph(
                          size: glyphSize,
                          color: glyphColor,
                          highlight: CceEmboss.highlight.color,
                          shadow: CceEmboss.shadow.color,
                          child: CceIcon(svg, size: 24, color: glyphColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      targetLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: on ? color : CceColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      service.displayName(device),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CceColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Franja inferior: estado (ambiente / power).
            Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: neo
                        ? Colors.black.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(color, semanticLabel: stateLabel),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      stateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CceColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen ??
          () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ThermostatScreen(device: device, service: service),
                ),
              ),
      child: tile,
    );
  }
}
