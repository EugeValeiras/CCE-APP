import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../widgets/light_tile.dart';
import '../widgets/sensor_tile.dart';

class RoomDetailScreen extends StatelessWidget {
  final String title;
  final List<String> deviceIds;
  final DevicesService service;

  const RoomDetailScreen({
    super.key,
    required this.title,
    required this.deviceIds,
    required this.service,
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
          backgroundColor: const Color(0xFF0B1D38),
          appBar: AppBar(
            backgroundColor: const Color(0xFF152D54),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white70),
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
                    color: onCount > 0 ? Colors.amber : Colors.white54,
                  ),
                  label: Text(
                    onCount > 0 ? 'Apagar todo' : 'Encender',
                    style: TextStyle(
                      color: onCount > 0 ? Colors.amber : Colors.white54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: service.refresh,
            color: Colors.white,
            backgroundColor: const Color(0xFF1E2A44),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (sensors.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: _SectionLabel('Sensores'),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 150,
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: _SectionLabel('Luces · $onCount de ${lights.length} encendidas'),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 160,
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
                        style: TextStyle(color: Colors.white54),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
      ),
    );
  }
}
