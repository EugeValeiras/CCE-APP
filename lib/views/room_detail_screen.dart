import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/section_header.dart';
import '../widgets/light_tile.dart';
import '../widgets/scenes_section.dart';
import '../widgets/sensor_tile.dart';

class RoomDetailScreen extends StatelessWidget {
  final String title;
  final List<String> deviceIds;
  final DevicesService service;
  final RoomRef? room; // opcional: habilita la sección de escenas

  const RoomDetailScreen({
    super.key,
    required this.title,
    required this.deviceIds,
    required this.service,
    this.room,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final devices = deviceIds.map(service.byId).whereType<Device>().toList();
        final lights = devices.where((d) => d.isLight && !d.isSensorDevice).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final sensors = devices.where((d) => d.isSensorDevice).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final onCount = lights.where((l) => l.state.on).length;

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (lights.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    for (final l in lights) {
                      await service.toggleLight(l);
                    }
                  },
                  icon: Icon(
                    onCount > 0 ? Icons.power_settings_new : Icons.power_off,
                    color: onCount > 0 ? CceColors.warm : CceColors.textTertiary,
                  ),
                  label: Text(
                    onCount > 0 ? 'Apagar todo' : 'Encender',
                    style: TextStyle(
                      color: onCount > 0 ? CceColors.warm : CceColors.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: service.refresh,
            color: CceColors.textPrimary,
            backgroundColor: CceColors.surfaceHigh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (room != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ScenesSection(service: service, room: room),
                    ),
                  ),
                if (sensors.isNotEmpty) ...[
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(title: 'Sensores'),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: TileSize.medium.maxTileExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: TileSize.medium.sensorTileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ListenableBuilder(
                          listenable: service,
                          builder: (ctx, _) {
                            final d = service.byId(sensors[i].id) ?? sensors[i];
                            return SensorTile(device: d, service: service, size: TileSize.medium);
                          },
                        ),
                        childCount: sensors.length,
                      ),
                    ),
                  ),
                ],
                if (lights.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        title: 'Luces · $onCount de ${lights.length} encendidas',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: TileSize.medium.maxTileExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: TileSize.medium.tileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ListenableBuilder(
                          listenable: service,
                          builder: (ctx, _) {
                            final d = service.byId(lights[i].id) ?? lights[i];
                            return LightTile(device: d, service: service, size: TileSize.medium);
                          },
                        ),
                        childCount: lights.length,
                      ),
                    ),
                  ),
                ],
                if (devices.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Este plano no tiene dispositivos',
                        style: TextStyle(color: CceColors.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
