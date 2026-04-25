import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../utils/icon_resolver.dart';
import 'pulse_on_update.dart';

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
    Color color = Colors.white54;
    bool alert = false;

    if (device.isContactSensor) {
      final open = s?.contact == true;
      stateLabel = open ? 'Abierta' : 'Cerrada';
      color = open ? const Color(0xFFFF9800) : Colors.white60;
      alert = open;
    } else if (device.isMotionSensor) {
      final motion = s?.motion == true;
      stateLabel = motion ? 'Movimiento' : 'Sin movimiento';
      color = motion ? const Color(0xFF2196F3) : Colors.white60;
      alert = motion;
    } else if (s?.temperature != null) {
      stateLabel = '${s!.temperature!.toStringAsFixed(1)}°';
      color = const Color(0xFFFF7043);
    } else if (s?.humidity != null) {
      stateLabel = '${s!.humidity!.toStringAsFixed(0)}%';
      color = const Color(0xFF4FC3F7);
    }

    final icon = IconResolver.resolve(device, configuredIcon: service.iconFor(device.id), displayName: service.displayName(device));

    return PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: 24,
      child: Container(
      height: size.sensorTileHeight,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A44),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: alert ? color.withValues(alpha: 0.6) : Colors.white12,
          width: 1.5,
        ),
        boxShadow: alert
            ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: 1)]
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
                const Icon(Icons.battery_alert, color: Colors.redAccent, size: 20),
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
                  color: Colors.white,
                  fontSize: size.nameSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stateLabel,
                style: TextStyle(
                  color: color,
                  fontSize: size.stateSize + 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
