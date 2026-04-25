import 'package:flutter/material.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../widgets/sensor_tile.dart';
import '../widgets/temperature_summary_card.dart';

class SensorsTab extends StatelessWidget {
  final DevicesService service;
  final TileSize tileSize;
  const SensorsTab({super.key, required this.service, this.tileSize = TileSize.medium});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final sensors = service.sensors..sort((a, b) => a.name.compareTo(b.name));
        if (service.loading && sensors.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }
        if (sensors.isEmpty) {
          return Center(
            child: Text(
              service.error ?? 'No hay sensores',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: service.refresh,
          color: Colors.white,
          backgroundColor: const Color(0xFF1E2A44),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: TemperatureSummaryCard(service: service)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: tileSize.maxTileExtent,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    mainAxisExtent: tileSize.sensorTileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SensorTile(device: sensors[i], service: service, size: tileSize),
                    childCount: sensors.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
