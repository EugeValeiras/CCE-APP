import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/device.dart';
import '../../models/room_ref.dart';
import '../../services/devices_service.dart';
import '../../services/ui_settings_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_segmented.dart';
import '../../theme/components/section_header.dart';
import '../../widgets/light_tile.dart';
import '../../widgets/scenes_section.dart';
import '../../widgets/sensor_tile.dart';
import '../floor_plan_tab.dart';

enum RoomPanelMode { lights, plan }

/// Panel derecho de la tab Casa cuando hay una habitacion seleccionada:
/// escenas + grilla de luces/sensores, con vista alternable al plano de la
/// habitacion (solo si deriva de un floor plan, es decir planId != null).
class RoomPanel extends StatefulWidget {
  const RoomPanel({
    super.key,
    required this.service,
    required this.room,
    required this.tileSize,
    required this.onCycleTileSize,
    required this.onRefresh,
  });

  final DevicesService service;
  final RoomRef room;
  final TileSize tileSize;
  final VoidCallback onCycleTileSize;
  final VoidCallback onRefresh;

  @override
  State<RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends State<RoomPanel> {
  RoomPanelMode _mode = RoomPanelMode.lights;

  @override
  void didUpdateWidget(covariant RoomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar de habitacion (o si la nueva no tiene plano) volver a Luces.
    if (oldWidget.room.id != widget.room.id || widget.room.planId == null) {
      _mode = RoomPanelMode.lights;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final room = widget.room;
        final stats = widget.service.statsFor(room);
        final showPlanToggle = room.planId != null;
        final mode =
            showPlanToggle ? _mode : RoomPanelMode.lights;

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
                      width: 220,
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
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton.tonal(
                    onPressed: stats.lightsTotal == 0
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            widget.service.setRoomOn(room, !stats.anyOn);
                          },
                    child: Text(stats.anyOn ? 'Apagar todo' : 'Encender'),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Tamaño: ${widget.tileSize.label}',
                    child: IconButton(
                      icon: Icon(_sizeIcon(widget.tileSize)),
                      onPressed: widget.onCycleTileSize,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: widget.onRefresh,
                  ),
                ],
              ),
            ),
            Expanded(
              child: mode == RoomPanelMode.plan
                  ? FloorPlanPanel(
                      service: widget.service,
                      planId: room.planId,
                      showPlanChips: false,
                      dotSize: widget.tileSize.floorPlanDotSize,
                    )
                  : _buildLights(room),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLights(RoomRef room) {
    final devices =
        room.deviceIds.map(widget.service.byId).whereType<Device>().toList();
    final lights =
        devices.where((d) => d.isLight && !d.isSensorDevice).toList();
    final sensors = devices.where((d) => d.isSensorDevice).toList();
    final tileSize = widget.tileSize;

    if (devices.isEmpty) {
      return const Center(
        child: Text('Esta habitación no tiene dispositivos',
            style: CceText.caption),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: ScenesSection(service: widget.service, room: room),
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
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListenableBuilder(
                  listenable: widget.service,
                  builder: (context, _) {
                    final d = widget.service.byId(lights[i].id) ?? lights[i];
                    return LightTile(
                      device: d,
                      service: widget.service,
                      size: tileSize,
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
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListenableBuilder(
                  listenable: widget.service,
                  builder: (context, _) {
                    final d = widget.service.byId(sensors[i].id) ?? sensors[i];
                    return SensorTile(
                      device: d,
                      service: widget.service,
                      size: tileSize,
                    );
                  },
                ),
                childCount: sensors.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
