import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../widgets/temp_sparkline.dart';

/// Pantalla de detalle de un TERMÓMETRO (sensor ambiente de temperatura /
/// humedad, distinto del termostato Tuya). Muestra la temperatura y la humedad
/// grandes arriba, la batería si existe, y abajo el gráfico de historial
/// ([TempSparkline]) reusando el mismo mecanismo (GET /api/events) que el
/// termostato. Estilo neumórfico coherente con [ThermostatScreen]: fondo
/// neoBase, cápsulas hundidas con relieve.
class ThermometerScreen extends StatelessWidget {
  final Device device;
  final DevicesService service;
  const ThermometerScreen({
    super.key,
    required this.device,
    required this.service,
  });

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(service.displayName(device), style: CceText.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: CceColors.textSecondary),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final d = service.byId(device.id) ?? device;
            final s = d.sensor;
            final temp = s?.temperature;
            final humidity = s?.humidity;
            final battery = s?.battery;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lectura principal: temperatura grande en cápsula hundida.
                  _Readout(
                    label: 'TEMPERATURA',
                    value: temp != null ? '${_fmt(temp)}°' : '—',
                    color: const Color(0xFFFF8A5C),
                  ),
                  if (humidity != null) ...[
                    const SizedBox(height: 14),
                    _Readout(
                      label: 'HUMEDAD',
                      value: '${humidity.toStringAsFixed(0)}%',
                      color: CceColors.info,
                    ),
                  ],
                  if (battery != null) ...[
                    const SizedBox(height: 14),
                    _BatteryChip(battery: battery),
                  ],
                  // Gráfico de historial (últimos 7 días). Sin binding o sin
                  // datos suficientes, TempSparkline se oculta solo.
                  if (d.bindingIds.isNotEmpty)
                    TempSparkline(
                      config: service.config,
                      globalId: d.bindingIds.first,
                      // Termómetro: la temp viaja en payload.sensor.temperature.
                      reader: (p) {
                        final sensor = p['sensor'];
                        final v =
                            (sensor is Map) ? sensor['temperature'] : null;
                        return v is num ? v.toDouble() : null;
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Cápsula hundida con un rótulo y un valor grande centrado.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(22),
        boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: CceText.caption.copyWith(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: CceColors.neoTextSub,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: CceText.display.copyWith(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de estado de batería (relieve convexo).
class _BatteryChip extends StatelessWidget {
  const _BatteryChip({required this.battery});

  final String battery;

  @override
  Widget build(BuildContext context) {
    final low = battery.toLowerCase() == 'low';
    final color = low ? CceColors.danger : CceColors.textSecondary;
    final label = low ? 'Batería baja' : 'Batería: $battery';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(16),
        boxShadow: CceShadows.neo(blur: 12, offset: 5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            low ? Icons.battery_alert : Icons.battery_full,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: CceText.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
