import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../utils/icon_resolver.dart';
import '../views/dial_switch_screen.dart';
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
    this.neo = false,
  });

  /// OPT-IN: relieve neumórfico de la card (default false).
  final bool neo;

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

    // ÍCONO GRANDE EXTRUIDO (sin círculo), mismo patrón que RoomCard. `color`
    // es el color SEMÁNTICO de estado (warm/contact/motion/info/temp), que en
    // alert es exactamente el fill visible de la card.
    //  - NO-ALERT (superficie oscura cardSurface): par FIJO de CceEmboss; el
    //    glyph conserva su color semántico de estado, ahora extruido en goma.
    //  - ALERT (fill = `color`): relieve MOLDEADO derivado de `color` y glyph en
    //    CceTint.textOn(color) (ink de contraste sobre el fill saturado).
    // El tamaño escala con TileSize para no comerse el slack vertical del tile
    // chico (138) cuando el nombre wrapea a 2 líneas.
    final double glyphSize = size.iconSize + 8; // 30 / 34 / 38
    final Color glyphColor = alert ? CceTint.textOn(color) : color;
    final Color embHi, embSh;
    if (alert) {
      final (h, s) = EmbossedGlyph.surfaceEmboss(color);
      embHi = h;
      embSh = s;
    } else {
      embHi = CceEmboss.highlight.color;
      embSh = CceEmboss.shadow.color;
    }

    final tile = PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: CceRadii.hueCard,
      child: Container(
        height: size.sensorTileHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: alert ? (neo ? CceColors.neoBase : CceColors.cardOff) : null,
          gradient: alert
              ? null
              : CceGradients.cardSurface(
                  neo ? CceColors.neoBase : CceColors.cardOff),
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: alert
              ? Border.all(color: color.withValues(alpha: 0.6), width: 1.5)
              : Border.all(color: CceColors.cardBevel),
          boxShadow: alert
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : (neo ? CceShadows.cardFloat() : null),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Zona superior centrada — MISMA estructura que LightCard:
                // ícono + nombre (el estado vive en la franja inferior).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Ícono GRANDE extruido, SIN círculo (igual que
                        // RoomCard). EmbossedGlyph aplana/recolorea el glyph a
                        // [glyphColor] y lo extruye con 2 capas ghost; FittedBox
                        // re-escala el IconResolver (size:24) a glyphSize, así el
                        // size intrínseco es indiferente. Caja cuadrada; el delta
                        // lo absorbe el Flexible del nombre en los 3 altos.
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: EmbossedGlyph(
                              size: glyphSize,
                              color: glyphColor,
                              highlight: embHi,
                              shadow: embSh,
                              child: IconResolver.widget(
                                device,
                                configuredIcon: service.iconFor(device.id),
                                customIcons: service.customIcons,
                                displayName: service.displayName(device),
                                size: 24,
                                color: glyphColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
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
                      ],
                    ),
                  ),
                ),
                // Franja inferior con borde superior (como el switch de la luz);
                // acá va el estado del sensor centrado (dot + label).
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
                      StatusDot(color, pulse: alert, semanticLabel: stateLabel),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          stateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
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
    // Switch: multi-botón (Tap Dial) → pantalla del dial; resto → switch grande.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => device.isMultiButton
              ? DialSwitchScreen(device: device, service: service)
              : SwitchDetailScreen(device: device, service: service),
        ),
      ),
      child: tile,
    );
  }
}
