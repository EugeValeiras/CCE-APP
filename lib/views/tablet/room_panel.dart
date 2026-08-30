import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/device.dart';
import '../../models/floor_plan.dart';
import '../../models/room_ref.dart';
import '../../services/devices_service.dart';
import '../../services/jbl_service.dart';
import '../../services/tv_service.dart';
import '../../services/ui_settings_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_button.dart';
import '../../theme/components/cce_segmented.dart';
import '../../theme/components/section_header.dart';
import '../../utils/room_icon.dart';
import '../../widgets/light_tile.dart';
import '../../widgets/lock_tile.dart';
import '../../widgets/media_device_tile.dart';
import '../../widgets/room_temperature_header.dart';
import '../../widgets/scenes_section.dart';
import '../../widgets/sensor_tile.dart';
import '../../widgets/thermostat_header_card.dart';
import '../../widgets/thermostat_tile.dart';
import '../floor_plan_tab.dart';

/// Panel derecho de la tab Casa cuando hay una habitacion seleccionada:
/// escenas + grilla de luces/sensores, con vista alternable al plano de la
/// habitacion (solo si deriva de un floor plan, es decir planId != null).
/// El modo Luces/Plano se persiste por habitacion en [UiSettingsService]
/// (ya no se resetea al cambiar de sala).
class RoomPanel extends StatelessWidget {
  const RoomPanel({
    super.key,
    required this.service,
    required this.ui,
    required this.room,
    required this.tileSize,
    required this.onCycleTileSize,
    required this.onRefresh,
    this.neo = false,
    this.tv,
    this.jbl,
    this.onOpenTv,
    this.onOpenJbl,
    this.onOpenThermostat,
  });

  final DevicesService service;
  final UiSettingsService ui;
  final RoomRef room;
  final TileSize tileSize;
  final VoidCallback onCycleTileSize;
  final VoidCallback onRefresh;
  final bool neo;

  /// Servicios + callbacks de los dispositivos dedicados (item 6): se
  /// reenvían a [FloorPlanPanel] para que el plano de la sala muestre los
  /// markers de TV / JBL si están ubicados en ESE plano y el tap abra el
  /// control inline en el panel derecho (igual que "Toda la casa"). También
  /// alimentan las filas de TV/JBL de la sección "Devices" (_buildLights).
  final TvService? tv;
  final JblService? jbl;
  final VoidCallback? onOpenTv;
  final VoidCallback? onOpenJbl;

  /// TABLET: abre el termostato INLINE en el panel derecho (igual que TV/JBL).
  /// Si es null (teléfono / RoomDetail), el header card cae a su push de ruta.
  final ValueChanged<Device>? onOpenThermostat;

  IconData _sizeIcon(TileSize s) {
    switch (s) {
      case TileSize.small:
        return Icons.view_comfy;
      case TileSize.medium:
        return Icons.grid_view;
      case TileSize.large:
        return Icons.view_module;
    }
  }

  Future<void> _toggleRoom(BuildContext context, bool on) async {
    final ok = await service.setRoomOn(room, on);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text("No se pudo ${on ? 'prender' : 'apagar'} ${room.name}"),
        action: SnackBarAction(
          label: 'Reintentar',
          onPressed: () => _toggleRoom(context, on),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([service, ui]),
      builder: (context, _) {
        final stats = service.statsFor(room);
        final showPlanToggle = room.planId != null;
        final mode =
            showPlanToggle ? ui.panelModeFor(room.id) : RoomPanelMode.lights;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Row(
                children: [
                  // Icono de la habitación (mismo que el sidebar y el dashboard).
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: roomGlyphBuilder(room, service, size: 30)(
                          CceColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.display,
                    ),
                  ),
                  if (showPlanToggle) ...[
                    SizedBox(
                      width: 260,
                      child: CceSegmented<RoomPanelMode>(
                        value: mode,
                        segments: const [
                          CceSegment(
                            value: RoomPanelMode.lights,
                            label: 'Luces',
                            icon: CceIcon(CceIcons.lights),
                          ),
                          CceSegment(
                            value: RoomPanelMode.plan,
                            label: 'Plano',
                            icon: CceIcon(CceIcons.floorPlan),
                          ),
                        ],
                        onChanged: (m) => ui.setPanelMode(room.id, m),
                        neo: neo,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Encender/Apagar: el haptic lo dispara el call-site (el
                  // botón neumórfico no trae haptic propio).
                  if (neo)
                    CceNeoActionButton(
                      label: stats.anyOn ? 'Apagar todo' : 'Encender',
                      onPressed: stats.lightsTotal == 0
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _toggleRoom(context, !stats.anyOn);
                            },
                    )
                  else
                    FilledButton.tonal(
                      onPressed: stats.lightsTotal == 0
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _toggleRoom(context, !stats.anyOn);
                            },
                      child: Text(stats.anyOn ? 'Apagar todo' : 'Encender'),
                    ),
                  const SizedBox(width: 8),
                  // En modo Plano el control de tamaño ajusta los markers de
                  // ESTE plano (markerScale por plano, compartido con el
                  // dashboard); el ciclo de TileSize queda para las cards.
                  if (mode == RoomPanelMode.plan)
                    PlanMarkerScaleButtons(
                      service: service,
                      ui: ui,
                      planId: room.planId,
                      neo: neo,
                    )
                  else if (neo)
                    CceNeoIconButton(
                      icon: _sizeIcon(tileSize),
                      tooltip: 'Tamaño: ${tileSize.label}',
                      onPressed: onCycleTileSize,
                    )
                  else
                    Tooltip(
                      message: 'Tamaño: ${tileSize.label}',
                      child: IconButton(
                        icon: Icon(_sizeIcon(tileSize)),
                        onPressed: onCycleTileSize,
                      ),
                    ),
                  if (neo) ...[
                    const SizedBox(width: 8),
                    CceNeoIconButton(
                      icon: Icons.refresh,
                      tooltip: 'Actualizar',
                      onPressed: onRefresh,
                    ),
                  ] else
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: onRefresh,
                    ),
                ],
              ),
            ),
            // Banner de clima de la habitación (se auto-oculta si la room no
            // tiene termómetro/higrómetro). Con >1 termómetro es tappable y
            // abre el selector scopeado a la room; la elección persiste por
            // room (RoomTemperatureHeader).
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: RoomTemperatureHeader(
                service: service,
                room: room,
                compact: true,
                neo: neo,
              ),
            ),
            Expanded(
              child: mode == RoomPanelMode.plan
                  ? FloorPlanPanel(
                      service: service,
                      ui: ui,
                      planId: room.planId,
                      showPlanChips: false,
                      neo: neo,
                      tv: tv,
                      jbl: jbl,
                      onOpenTv: onOpenTv,
                      onOpenJbl: onOpenJbl,
                      onOpenThermostat: onOpenThermostat,
                    )
                  : _buildLights(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLights() {
    final devices =
        room.deviceIds.map(service.byId).whereType<Device>().toList();
    final lights = devices
        .where((d) => d.isLight && !d.isSensorDevice && !d.isThermostat)
        .toList();
    // Termostato del room → header fijo arriba del contenido (igual que el
    // teléfono en room_detail_screen.dart): NO es una sección "Clima". Tomamos
    // el primario (alfabético) si hay varios.
    final thermostats = devices.where((d) => d.isThermostat).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final primaryThermostat =
        thermostats.isNotEmpty ? thermostats.first : null;
    final sensors = devices
        .where((d) => (d.isSensorDevice || d.isSwitch) && !d.isThermostat && !d.isLock)
        .toList();
    final locks = devices.where((d) => d.isLock).toList();
    // Pertenencia de TV/JBL derivada de los DEVICES del room ("todos son
    // dispositivos", espejo del phone en room_detail_screen.dart): desde
    // CCE#54 `rooms` mete los dedicados en los deviceIds de la habitación cuyo
    // plano los ubica —además de las rooms de fallback groups/_orphans—, así
    // que alcanza con mirar los devices y cada Samsung tiene su tile donde
    // está. El gate viejo exigía planId != null y las rooms de fallback jamás
    // mostraban TV/JBL.
    final tvsInRoom = devices
        .where((d) => DevicesService.isDedicatedDevice(d, DedicatedFamily.tv))
        .toList();
    final jblsInRoom = devices
        .where((d) => DevicesService.isDedicatedDevice(d, DedicatedFamily.jbl))
        .toList();
    final hasTv = tv != null && tvsInRoom.isNotEmpty;
    final hasJbl = jbl != null && jblsInRoom.isNotEmpty;
    // TODOS los termostatos entran a la sección Devices como tiles (pedido
    // del dueño v1.62): el primario aparece dos veces a propósito — como
    // ThermostatHeaderCard fijo arriba Y como tile en la lista.
    final extraThermostats = thermostats;
    final extraCount = extraThermostats.length +
        (hasTv ? tvsInRoom.length : 0) +
        (hasJbl ? jblsInRoom.length : 0);

    if (devices.isEmpty && !hasTv && !hasJbl) {
      return const Center(
        child: Text('Esta habitación no tiene dispositivos',
            style: CceText.caption),
      );
    }

    return CustomScrollView(
      // Orden: Termostato (header) → Escenas → Luces → Devices → Cerraduras.
      slivers: [
        // Termostato del room: header fijo arriba del contenido (espejo del
        // teléfono), junto al lector de temperatura (no es sección "Clima").
        if (primaryThermostat != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final d = service.byId(primaryThermostat.id) ??
                      primaryThermostat;
                  return ThermostatHeaderCard(
                    device: d,
                    service: service,
                    neo: neo,
                    onOpen: onOpenThermostat == null
                        ? null
                        : () => onOpenThermostat!(d),
                  );
                },
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: ScenesSection(service: service, room: room, neo: neo),
          ),
        ),
        if (lights.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: const SliverToBoxAdapter(
              child: SectionHeader(title: 'Luces'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: tileSize.maxTileExtent,
                mainAxisExtent: tileSize.tileHeight,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListenableBuilder(
                  listenable: service,
                  builder: (context, _) {
                    final d = service.byId(lights[i].id) ?? lights[i];
                    return LightTile(
                      device: d,
                      service: service,
                      size: tileSize,
                      neo: neo,
                    );
                  },
                ),
                childCount: lights.length,
              ),
            ),
          ),
        ],
        // "Devices" (ex "Sensores"): sensores → termostatos extra → TV → JBL,
        // en UN solo grid indexado (espejo del phone). Tap de los tiles nuevos
        // = control INLINE en el panel derecho vía los callbacks ya cableados
        // (si son null caen a su push de ruta — fallback inocuo).
        if (sensors.isNotEmpty || extraCount > 0) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: const SliverToBoxAdapter(
              child: SectionHeader(title: 'Dispositivos'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: tileSize.maxTileExtent,
                mainAxisExtent: tileSize.sensorTileHeight,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  if (i < sensors.length) {
                    return ListenableBuilder(
                      listenable: service,
                      builder: (context, _) {
                        final d = service.byId(sensors[i].id) ?? sensors[i];
                        return SensorTile(
                          device: d,
                          service: service,
                          size: tileSize,
                          neo: neo,
                        );
                      },
                    );
                  }
                  var j = i - sensors.length;
                  if (j < extraThermostats.length) {
                    final t = extraThermostats[j];
                    return ListenableBuilder(
                      listenable: service,
                      builder: (context, _) {
                        final d = service.byId(t.id) ?? t;
                        return ThermostatTile(
                          device: d,
                          service: service,
                          size: tileSize,
                          neo: neo,
                          onOpen: onOpenThermostat == null
                              ? null
                              : () => onOpenThermostat!(d),
                        );
                      },
                    );
                  }
                  j -= extraThermostats.length;
                  if (hasTv) {
                    if (j < tvsInRoom.length) {
                      return TvDeviceTile(
                        service: tv!,
                        devices: service,
                        deviceId: tvsInRoom[j].id,
                        size: tileSize,
                        neo: neo,
                        onOpen: onOpenTv,
                      );
                    }
                    j -= tvsInRoom.length;
                  }
                  return JblDeviceTile(
                    service: jbl!,
                    size: tileSize,
                    neo: neo,
                    onOpen: onOpenJbl,
                  );
                },
                childCount: sensors.length + extraCount,
              ),
            ),
          ),
        ],
        if (locks.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: const SliverToBoxAdapter(
              child: SectionHeader(title: 'Cerraduras'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: tileSize.maxTileExtent,
                mainAxisExtent: tileSize.sensorTileHeight,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListenableBuilder(
                  listenable: service,
                  builder: (context, _) {
                    final d = service.byId(locks[i].id) ?? locks[i];
                    return LockTile(
                      device: d,
                      service: service,
                      size: tileSize,
                      neo: neo,
                    );
                  },
                ),
                childCount: locks.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
