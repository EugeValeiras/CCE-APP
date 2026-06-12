import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_pill.dart';
import '../utils/icon_resolver.dart';
import 'pulse_on_update.dart';

/// Tile de sensor (contacto, movimiento, temperatura, humedad), sin gestos.
class SensorTile extends StatelessWidget {
  final Device device;
  final DevicesService service;
  final TileSize size;

  const SensorTile({
    super.key,
    required this.device,
    required this.service,
    this.size = TileSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final s = device.sensor;
    String stateLabel = '—';
    Color color = CceColors.textTertiary;
    bool alert = false;

    if (device.isContactSensor) {
      final open = s?.contact == true;
      stateLabel = open ? 'Abierta' : 'Cerrada';
      color = open ? CceColors.contact : CceColors.textSecondary;
      alert = open;
    } else if (device.isMotionSensor) {
      final motion = s?.motion == true;
      stateLabel = motion ? 'Movimiento' : 'Sin movimiento';
      color = motion ? CceColors.motion : CceColors.textSecondary;
      alert = motion;
    } else if (s?.temperature != null) {
      stateLabel = '${s!.temperature!.toStringAsFixed(1)}°';
      color = const Color(0xFFFF8A5C);
    } else if (s?.humidity != null) {
      stateLabel = '${s!.humidity!.toStringAsFixed(0)}%';
      color = CceColors.info;
    }

    final icon = IconResolver.resolve(
      device,
      configuredIcon: service.iconFor(device.id),
      displayName: service.displayName(device),
    );

    return PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: CceRadii.tile,
      child: Container(
        height: size.sensorTileHeight,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CceColors.surface,
          borderRadius: BorderRadius.circular(CceRadii.tile),
          border: Border.all(
            color: alert ? color.withValues(alpha: 0.6) : CceColors.stroke,
            width: alert ? 1.5 : 1,
          ),
          boxShadow: alert
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: size.iconSize),
                if (s?.battery == 'low')
                  const Icon(Icons.battery_alert,
                      color: CceColors.danger, size: 20),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.displayName(device),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CceColors.textPrimary,
                    fontSize: size.nameSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                StatusPill(
                  label: stateLabel,
                  color: color.withValues(alpha: 0.16),
                  foreground: color,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
