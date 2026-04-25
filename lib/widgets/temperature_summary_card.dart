import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/device.dart';
import '../services/devices_service.dart';

/// Big "weather-card style" widget summarising current temperature + humidity
/// from whichever sensors are reporting them. Shows the highest-coverage readings.
class TemperatureSummaryCard extends StatelessWidget {
  final DevicesService service;
  const TemperatureSummaryCard({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final tempSensors = service.sensors.where((s) => s.sensor?.temperature != null).toList();
    final humSensors = service.sensors.where((s) => s.sensor?.humidity != null).toList();
    if (tempSensors.isEmpty && humSensors.isEmpty) return const SizedBox.shrink();

    final primary = tempSensors.isNotEmpty ? tempSensors.first : null;
    final primaryHumDevice = humSensors.firstWhere(
      (s) => s.id == primary?.id,
      orElse: () => humSensors.isNotEmpty ? humSensors.first : _dummy,
    );
    final primaryHum = primaryHumDevice.sensor?.humidity;
    final primaryTemp = primary?.sensor?.temperature;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _colorForTemp(primaryTemp).withValues(alpha: 0.45),
              const Color(0xFF1E2A44),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (primaryTemp != null)
              Expanded(
                child: _HeroReading(
                  icon: MdiIcons.thermometer,
                  value: primaryTemp.toStringAsFixed(1),
                  unit: '°C',
                  label: primary != null ? service.displayName(primary) : 'Temperatura',
                  color: _colorForTemp(primaryTemp),
                ),
              ),
            if (primaryTemp != null && primaryHum != null)
              Container(width: 1, height: 72, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 16)),
            if (primaryHum != null)
              Expanded(
                child: _HeroReading(
                  icon: MdiIcons.waterPercent,
                  value: primaryHum.toStringAsFixed(0),
                  unit: '%',
                  label: primaryHumDevice.id.isEmpty ? 'Humedad' : service.displayName(primaryHumDevice),
                  color: const Color(0xFF4FC3F7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _colorForTemp(double? t) {
    if (t == null) return Colors.grey;
    if (t < 15) return const Color(0xFF42A5F5);
    if (t < 20) return const Color(0xFF66BB6A);
    if (t < 25) return const Color(0xFFFFB74D);
    if (t < 30) return const Color(0xFFFF8A65);
    return const Color(0xFFE53935);
  }

  static final Device _dummy = Device(id: '', name: '', type: '', state: DeviceState());
}

class _HeroReading extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;
  const _HeroReading({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
