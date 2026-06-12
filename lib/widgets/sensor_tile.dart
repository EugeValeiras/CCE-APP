import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../utils/icon_resolver.dart';
import '../views/switch_detail_screen.dart';
import 'pulse_on_update.dart';

/// Tile de sensor (contacto, movimiento, temperatura, humedad). Los devices
/// tipo switch muestran su estado on/off y abren su pantalla al tocarlos.
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

    // Switch/control: muestra encendido/apagado y es tocable.
    final isSwitch = device.isSwitch;
    if (isSwitch) {
      final on = device.state.on;
      stateLabel = on ? 'Encendido' : 'Apagado';
      color = on ? CceColors.warm : CceColors.textSecondary;
    } else if (device.isContactSensor) {
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

    // Lectura numérica grande para temp/humedad (los binarios y switches ya
    // comunican su estado en la franja inferior).
    final String? bigReading =
        device.isContactSensor || device.isMotionSensor || isSwitch
            ? null
            : stateLabel;

    final tile = PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: CceRadii.hueCard,
      child: Container(
        height: size.sensorTileHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CceColors.cardOff,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: alert
              ? Border.all(color: color.withValues(alpha: 0.6), width: 1.5)
              : null,
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
        child: Stack(
          children: [
            Column(
              children: [
                // Zona superior centrada (misma familia que LightCard). El
                // FittedBox evita overflow en la card compacta (132 px).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                          height: size.iconSize,
                          child: Center(
                            child: IconResolver.widget(
                              device,
                              configuredIcon: service.iconFor(device.id),
                              customIcons: service.customIcons,
                              displayName: service.displayName(device),
                              size: size.iconSize,
                              color: color,
                            ),
                          ),
                        ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 124,
                            child: Text(
                              service.displayName(device),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: CceColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (bigReading != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              bigReading,
                              maxLines: 1,
                              style: TextStyle(
                                color: CceColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Franja inferior: dot de estado + label (sensores no se
                // togglean — acá va el estado en lugar del switch).
                Container(
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.045),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      StatusDot(color, semanticLabel: stateLabel),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          stateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: alert ? color : CceColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (s?.battery == 'low')
              const Positioned(
                top: 10,
                right: 10,
                child: Icon(Icons.battery_alert,
                    color: CceColors.danger, size: 18),
              ),
          ],
        ),
      ),
    );

    if (!isSwitch) return tile;
    // Switch: tocá la card para abrir su pantalla con el switch grande.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SwitchDetailScreen(device: device, service: service),
        ),
      ),
      child: tile,
    );
  }
}
