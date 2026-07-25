import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../utils/vacuum_modes.dart';
import '../views/vacuum_screen.dart';
import '../views/unified_device_screen.dart';
import 'pulse_on_update.dart';

/// Tile del robot aspiradora (capability 'vacuum', Roborock vía Matter).
/// Espejo de [LockTile]: glyph grande extruido + nombre, franja de estado
/// abajo (Limpiando/En base/…). Al tocarlo abre [VacuumScreen].
///
/// Colores de estado: limpiando = info (azul, con pulse), en base = ok,
/// pausada = ámbar, volviendo = motion, error = danger (única alerta).
class VacuumTile extends StatelessWidget {
  final Device device;
  final DevicesService service;
  final TileSize size;

  const VacuumTile({
    super.key,
    required this.device,
    required this.service,
    this.size = TileSize.medium,
    this.neo = false,
  });

  /// OPT-IN: relieve neumórfico de la card (default false).
  final bool neo;

  static Color stateColor(String? state) {
    switch (state) {
      case 'cleaning':
        return CceColors.info;
      case 'docked':
        return CceColors.ok;
      case 'paused':
        return const Color(0xFFFF9F0A); // ámbar (mismo que lock destrabada)
      case 'returning':
        return CceColors.motion;
      case 'error':
        return CceColors.danger;
      default:
        return CceColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? vacState = device.state.vacuumState;
    final String stateLabel = vacuumStateLabel(vacState);
    final Color color = stateColor(vacState);
    // Solo el error es alerta visual (borde + glow); limpiar es actividad
    // normal y se comunica con el pulse del dot.
    final bool alert = vacState == 'error';
    final bool active = vacState == 'cleaning' || vacState == 'returning';

    final double glyphSize = size.iconSize + 8;
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
        child: Column(
          children: [
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
                          highlight: embHi,
                          shadow: embSh,
                          child: CceIcon(
                            CceIcons.robotVacuum,
                            size: 24,
                            color: glyphColor,
                            emboss: false,
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
            // Franja inferior con el estado (dot + label), igual que LockTile.
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
                  StatusDot(color,
                      pulse: alert || active, semanticLabel: stateLabel),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      stateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: (alert || active)
                            ? color
                            : CceColors.textSecondary,
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VacuumScreen(device: device, service: service),
        ),
      ),
      onLongPress: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UnifiedDeviceScreen(device: device, service: service),
        ),
      ),
      child: tile,
    );
  }
}
