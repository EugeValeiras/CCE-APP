import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';

/// Card "clima": temperatura + humedad actuales. Si [room] != null toma solo
/// los sensores de esa habitación; si es null, toda la casa. Se auto-oculta
/// si no hay lecturas. [compact] reduce el alto para vivir en el header.
class TemperatureSummaryCard extends StatelessWidget {
  final DevicesService service;
  final RoomRef? room;
  final bool compact;
  const TemperatureSummaryCard({
    super.key,
    required this.service,
    this.room,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Sensores en el alcance: los de la room (por deviceIds) o toda la casa.
    final scoped = room == null
        ? service.sensors
        : service.sensors
            .where((s) => room!.deviceIds.contains(s.id))
            .toList();
    final tempSensors =
        scoped.where((s) => s.sensor?.temperature != null).toList();
    final humSensors =
        scoped.where((s) => s.sensor?.humidity != null).toList();
    if (tempSensors.isEmpty && humSensors.isEmpty) return const SizedBox.shrink();

    final primary = tempSensors.isNotEmpty ? tempSensors.first : null;
    final primaryHumDevice = humSensors.firstWhere(
      (s) => s.id == primary?.id,
      orElse: () => humSensors.isNotEmpty ? humSensors.first : _dummy,
    );
    final primaryHum = primaryHumDevice.sensor?.humidity;
    final primaryTemp = primary?.sensor?.temperature;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 8),
      child: CceCard(
        padding: EdgeInsets.symmetric(
            horizontal: 22, vertical: compact ? 12 : 16),
        border: true,
        color: CceColors.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (primaryTemp != null)
              Expanded(
                child: _HeroReading(
                  icon: MdiIcons.thermometer,
                  value: primaryTemp.toStringAsFixed(1),
                  unit: '°C',
                  label: 'Temperatura',
                  color: _desaturate(_colorForTemp(primaryTemp)),
                  compact: compact,
                ),
              ),
            if (primaryTemp != null && primaryHum != null)
              Container(
                width: 1,
                height: compact ? 40 : 56,
                color: CceColors.stroke,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
            if (primaryHum != null)
              Expanded(
                child: _HeroReading(
                  icon: MdiIcons.waterPercent,
                  value: primaryHum.toStringAsFixed(0),
                  unit: '%',
                  label: 'Humedad',
                  color: CceColors.info,
                  compact: compact,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Desatura el color de la escala térmica (60% de la saturación original).
  static Color _desaturate(Color c) {
    final hsv = HSVColor.fromColor(c);
    return hsv
        .withSaturation((hsv.saturation * 0.6).clamp(0.0, 1.0).toDouble())
        .toColor();
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
  final bool compact;
  const _HeroReading({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: CceText.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 3 : 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: CceText.display.copyWith(
                fontSize: compact ? 30 : 38,
                height: 1.0,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
