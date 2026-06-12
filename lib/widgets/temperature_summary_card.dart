import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';

/// Card "clima de la casa": temperatura + humedad actuales tomadas de los
/// sensores que reporten. Se auto-oculta si no hay lecturas.
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CceCard(
        padding: const EdgeInsets.all(22),
        border: true,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            // Pipeline de tint: nunca pintar el color de escala crudo.
            CceTint.normalize(_desaturate(_colorForTemp(primaryTemp)))
                .withValues(alpha: 0.45),
            CceColors.surface,
          ],
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
                  color: _desaturate(_colorForTemp(primaryTemp)),
                ),
              ),
            if (primaryTemp != null && primaryHum != null)
              Container(
                width: 1,
                height: 72,
                color: CceColors.stroke,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
            if (primaryHum != null)
              Expanded(
                child: _HeroReading(
                  icon: MdiIcons.waterPercent,
                  value: primaryHum.toStringAsFixed(0),
                  unit: '%',
                  label: primaryHumDevice.id.isEmpty ? 'Humedad' : service.displayName(primaryHumDevice),
                  color: CceColors.info,
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
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: CceText.caption.copyWith(fontWeight: FontWeight.w600),
              ),
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
              style: CceText.display.copyWith(
                fontSize: 48,
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
