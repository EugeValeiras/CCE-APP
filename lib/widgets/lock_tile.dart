import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../views/lock_screen.dart';
import '../views/unified_device_screen.dart';
import 'pulse_on_update.dart';

/// Tile de cerradura (capability 'lock', provider ezviz). Espejo de
/// [SensorTile]: ícono grande extruido + nombre arriba, franja de estado
/// (Trabada/Destrabada) abajo. Al tocarla abre [LockScreen] (mismo control
/// neumórfico que el dashboard).
///
/// Convención de estado (igual que LockScreen): `state.on` = trabada
/// (isLocked). Ícono candado vendoreado de icons0.dev (CoreUI: cil:lock-locked
/// / cil:lock-unlocked, ya disponibles en [CceIcons]).
class LockTile extends StatelessWidget {
  final Device device;
  final DevicesService service;
  final TileSize size;

  const LockTile({
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
    // state.on = trabada. Trabada NO es alerta (verde); destrabada SÍ (ámbar).
    final bool locked = device.state.on;
    final String stateLabel = locked ? 'Trabada' : 'Destrabada';
    final Color color =
        locked ? CceColors.ok : CceColors.contact; // ámbar destrabada
    final bool alert = !locked;
    final String svg = locked ? CceIcons.lockLocked : CceIcons.lockUnlocked;

    // Mismo patrón visual que SensorTile: glyph grande extruido (sin círculo),
    // par de emboss fijo en no-alerta y derivado del color en alerta.
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
                            svg,
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
            // Franja inferior con el estado (dot + label), igual que SensorTile.
            Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: neo
                        ? Colors.black.withValues(alpha: 0.16)
                        : CceColors.strokeSoft,
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
                        fontSize: 13,
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
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LockScreen(device: device, service: service),
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
