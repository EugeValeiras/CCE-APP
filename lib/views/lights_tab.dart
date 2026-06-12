import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../models/light_group.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../utils/icon_resolver.dart';
import '../widgets/light_tile.dart';

class LightsTab extends StatelessWidget {
  final DevicesService service;
  final TileSize tileSize;
  const LightsTab({super.key, required this.service, this.tileSize = TileSize.medium});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final allLights = service.lights..sort((a, b) => a.name.compareTo(b.name));
        if (service.loading && allLights.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }
        if (allLights.isEmpty) {
          return Center(
            child: Text(
              service.error ?? 'No hay luces',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        final sections = _groupLights(allLights, service.groups);

        return RefreshIndicator(
          onRefresh: service.refresh,
          color: Colors.white,
          backgroundColor: const Color(0xFF1E2A44),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: sections.length,
            itemBuilder: (context, i) {
              final section = sections[i];
              return _RoomSection(section: section, service: service, tileSize: tileSize);
            },
          ),
        );
      },
    );
  }

  /// Build sections from groups; fall back to a single "Todas" section when no groups.
  List<_Section> _groupLights(List<Device> lights, List<LightGroup> groups) {
    if (groups.isEmpty) {
      return [_Section(name: 'Todas', lightGroupId: null, lights: lights)];
    }

    final byId = {for (final l in lights) l.id: l};
    final used = <String>{};
    final sections = <_Section>[];

    for (final g in groups) {
      final groupLights = g.lightIds
          .where(byId.containsKey)
          .map((id) => byId[id]!)
          .toList();
      if (groupLights.isEmpty) continue;
      used.addAll(groupLights.map((l) => l.id));
      sections.add(_Section(name: g.name, lightGroupId: g.id, lights: groupLights, iconName: g.icon));
    }

    // Catch-all for lights not in any group
    final orphans = lights.where((l) => !used.contains(l.id)).toList();
    if (orphans.isNotEmpty) {
      sections.add(_Section(name: 'Otras', lightGroupId: null, lights: orphans));
    }

    return sections;
  }
}

class _Section {
  final String name;
  final String? lightGroupId;
  final String? iconName;
  final List<Device> lights;
  _Section({required this.name, required this.lightGroupId, required this.lights, this.iconName});
}

class _RoomSection extends StatelessWidget {
  final _Section section;
  final DevicesService service;
  final TileSize tileSize;
  const _RoomSection({required this.section, required this.service, required this.tileSize});

  @override
  Widget build(BuildContext context) {
    final onCount = section.lights.where((l) => l.state.on).length;
    final allOn = onCount == section.lights.length;
    final anyOn = onCount > 0;
    final groupObj = section.lightGroupId != null
        ? service.groups.firstWhere((g) => g.id == section.lightGroupId, orElse: () => LightGroup(id: '', name: '', lightIds: const []))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
          child: Row(
            children: [
              if (section.iconName != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _GroupIcon(iconName: section.iconName),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$onCount de ${section.lights.length} encendida${section.lights.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (groupObj != null && groupObj.id.isNotEmpty)
                _MasterToggle(
                  anyOn: anyOn,
                  allOn: allOn,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    service.setGroupOn(groupObj, !anyOn);
                  },
                ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: tileSize.maxTileExtent,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: tileSize.tileHeight,
          ),
          itemCount: section.lights.length,
          itemBuilder: (context, i) => LightTile(device: section.lights[i], service: service, size: tileSize),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _GroupIcon extends StatelessWidget {
  final String? iconName;
  const _GroupIcon({required this.iconName});
  @override
  Widget build(BuildContext context) {
    if (iconName == null || iconName!.isEmpty) return const SizedBox.shrink();
    // Use the resolver on a fake device with the icon name as "configuredIcon"
    // For groups we can just look up the map directly — the resolver is for devices.
    // Use the name-based heuristics by passing a minimal Device-like path is overkill;
    // just show a small icon via dummy.
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A44),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_mdiFromName(iconName!), color: Colors.white70, size: 18),
    );
  }

  IconData _mdiFromName(String name) {
    // Quick fallback through resolver's private map via creating a dummy device.
    // Simpler: rely on common group icons.
    final normalized = name.toLowerCase().replaceFirst('mdi:', '').replaceFirst('mdi-', '');
    return IconResolver.resolve(
      // Minimal device; resolver will try configuredIcon first.
      _dummy,
      configuredIcon: normalized,
    );
  }

  static final Device _dummy = Device(
    id: '_',
    name: '',
    type: 'Dimmable light',
    state: DeviceState(on: false),
  );
}

class _MasterToggle extends StatelessWidget {
  final bool anyOn;
  final bool allOn;
  final VoidCallback onTap;
  const _MasterToggle({required this.anyOn, required this.allOn, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = allOn ? Colors.amber : (anyOn ? Colors.amber.withValues(alpha: 0.6) : Colors.white38);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: anyOn ? Colors.amber.withValues(alpha: 0.18) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(anyOn ? Icons.power_settings_new : Icons.power_off, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              anyOn ? 'Apagar' : 'Encender',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
