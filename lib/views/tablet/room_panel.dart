import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/device.dart';
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
import '../../widgets/light_tile.dart';
import '../../widgets/lock_tile.dart';
import '../../widgets/scenes_section.dart';
import '../../widgets/sensor_tile.dart';
import '../../widgets/temperature_summary_card.dart';
import '../../widgets/thermostat_header_card.dart';
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
  /// control inline en el panel derecho (igual que "Toda la casa").
  final TvService? tv;
  final JblService? jbl;
  final VoidCallback? onOpenTv;
  final VoidCallback? onOpenJbl;

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
                  if (neo) ...[
                    CceNeoIconButton(
                      icon: _sizeIcon(tileSize),
                      tooltip: 'Tamaño: ${tileSize.label}',
                      onPressed: onCycleTileSize,
                    ),
                    const SizedBox(width: 8),
                    CceNeoIconButton(
                      icon: Icons.refresh,
                      tooltip: 'Actualizar',
                      onPressed: onRefresh,
                    ),
                  ] else ...[
                    Tooltip(
                      message: 'Tamaño: ${tileSize.label}',
                      child: IconButton(
                        icon: Icon(_sizeIcon(tileSize)),
                        onPressed: onCycleTileSize,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: onRefresh,
                    ),
                  ],
                ],
              ),
            ),
            // Banner de clima de la habitación (se auto-oculta si la room no
            // tiene termómetro/higrómetro).
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: TemperatureSummaryCard(
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
                      dotSize: tileSize.floorPlanDotSize,
                      neo: neo,
                      tv: tv,
                      jbl: jbl,
                      onOpenTv: onOpenTv,
                      onOpenJbl: onOpenJbl,
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

    if (devices.isEmpty) {
      return const Center(
        child: Text('Esta habitación no tiene dispositivos',
            style: CceText.caption),
      );
    }

    return CustomScrollView(
      // Orden: Termostato (header) → Escenas → Luces → Sensores → Cerraduras.
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
        if (sensors.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: const SliverToBoxAdapter(
              child: SectionHeader(title: 'Sensores'),
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
                    final d = service.byId(sensors[i].id) ?? sensors[i];
                    return SensorTile(
                      device: d,
                      service: service,
                      size: tileSize,
                      neo: neo,
                    );
                  },
                ),
                childCount: sensors.length,
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
