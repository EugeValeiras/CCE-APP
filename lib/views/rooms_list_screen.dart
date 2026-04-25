import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../widgets/pulse_on_update.dart';
import 'room_detail_screen.dart';

class RoomsListScreen extends StatelessWidget {
  final DevicesService service;
  const RoomsListScreen({super.key, required this.service});

  /// Build rooms from floor plans (each plan = room), falling back to lightGroups
  /// if no plans have positions, falling back to a single "Todas" room as last resort.
  List<_Room> _buildRooms() {
    final fp = service.floorPlans;
    final rooms = <_Room>[];
    final seenDeviceIds = <String>{};

    if (fp != null && fp.plans.isNotEmpty) {
      for (final plan in fp.plans) {
        final positions = fp.positions[plan.id] ?? const {};
        final ids = positions.keys.where((id) => service.byId(id) != null).toList();
        if (ids.isEmpty) continue;
        seenDeviceIds.addAll(ids);
        rooms.add(_Room(id: plan.id, name: plan.name, deviceIds: ids));
      }
    }

    // Fallback to lightGroups if no plans had positions
    if (rooms.isEmpty && service.groups.isNotEmpty) {
      for (final g in service.groups) {
        final ids = g.lightIds.where((id) => service.byId(id) != null).toList();
        if (ids.isEmpty) continue;
        seenDeviceIds.addAll(ids);
        rooms.add(_Room(id: g.id, name: g.name, deviceIds: ids, iconName: g.icon));
      }
    }

    // Orphans bucket
    final orphans = service.all
        .where((d) => !seenDeviceIds.contains(d.id) && (d.isLight && !d.isSensorDevice || d.isSensorDevice))
        .map((d) => d.id)
        .toList();
    if (orphans.isNotEmpty) {
      rooms.add(_Room(id: '_orphans', name: rooms.isEmpty ? 'Todos' : 'Sin ubicación', deviceIds: orphans));
    }

    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.loading && service.all.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B1D38),
            body: Center(child: CircularProgressIndicator(color: Colors.white54)),
          );
        }

        final rooms = _buildRooms();
        return Scaffold(
          backgroundColor: const Color(0xFF0B1D38),
          appBar: AppBar(
            backgroundColor: const Color(0xFF152D54),
            title: const Text('Casa', style: TextStyle(color: Colors.white)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: service.refresh,
              ),
            ],
          ),
          body: rooms.isEmpty
              ? Center(
                  child: Text(
                    service.error ?? 'No hay habitaciones configuradas',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: service.refresh,
                  color: Colors.white,
                  backgroundColor: const Color(0xFF1E2A44),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rooms.length,
                    separatorBuilder: (context, idx) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final r = rooms[i];
                      return _RoomCard(room: r, service: service);
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _Room {
  final String id;
  final String name;
  final List<String> deviceIds;
  final String? iconName;
  _Room({required this.id, required this.name, required this.deviceIds, this.iconName});
}

class _RoomCard extends StatelessWidget {
  final _Room room;
  final DevicesService service;
  const _RoomCard({required this.room, required this.service});

  /// Average color of lights currently on, or amber default if any on.
  Color? _tintForOnLights(List<Device> lightsOn) {
    if (lightsOn.isEmpty) return null;
    final colored = lightsOn.where((l) => l.state.hue != null && l.state.sat != null && (l.state.sat ?? 0) > 40).toList();
    if (colored.isEmpty) return const Color(0xFFFFB74D);
    double sumH = 0, sumS = 0;
    for (final l in colored) {
      sumH += (l.state.hue! / 65535) * 360;
      sumS += (l.state.sat! / 254).clamp(0.0, 1.0);
    }
    return HSVColor.fromAHSV(1.0, sumH / colored.length, sumS / colored.length, 1.0).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final devices = room.deviceIds.map(service.byId).whereType<Device>().toList();
    final lights = devices.where((d) => d.isLight && !d.isSensorDevice).toList();
    final lightsOn = lights.where((l) => l.state.on).toList();
    final contactOpen = devices.any((d) => d.isContactSensor && d.sensor?.contact == true);
    final motionActive = devices.any((d) => d.isMotionSensor && d.sensor?.motion == true);
    final anyOn = lightsOn.isNotEmpty;
    final tint = _tintForOnLights(lightsOn);

    final pct = lights.isEmpty ? 0.0 : lightsOn.length / lights.length;

    // Trigger pulse when any device in the room receives a WS event.
    DateTime? mostRecent;
    for (final d in devices) {
      final t = d.lastEventAt;
      if (t != null && (mostRecent == null || t.isAfter(mostRecent))) {
        mostRecent = t;
      }
    }

    return PulseOnUpdate(
      triggerAt: mostRecent,
      color: anyOn && tint != null ? tint : const Color(0xFF4FC3F7),
      borderRadius: 22,
      child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RoomDetailScreen(
            title: room.name,
            deviceIds: room.deviceIds,
            service: service,
          ),
        ));
      },
      onLongPress: lights.isEmpty
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              for (final l in lights) {
                await service.toggleLight(l);
              }
            },
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A44),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: anyOn ? tint!.withValues(alpha: 0.7) : Colors.white12,
            width: 1.5,
          ),
          boxShadow: anyOn
              ? [BoxShadow(color: tint!.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: 1)]
              : null,
          gradient: anyOn
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [tint!.withValues(alpha: 0.25), const Color(0xFF1E2A44)],
                  stops: [pct, pct],
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: anyOn ? tint!.withValues(alpha: 0.3) : const Color(0xFF0B1D38),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: anyOn ? tint! : Colors.white12, width: 1.5),
              ),
              child: Icon(
                anyOn ? MdiIcons.lightbulbOn : MdiIcons.homeOutline,
                color: anyOn ? Colors.white : Colors.white54,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (lights.isNotEmpty)
                        _RoomChip(
                          icon: anyOn ? MdiIcons.lightbulbOn : MdiIcons.lightbulbOutline,
                          label: '${lightsOn.length}/${lights.length}',
                          color: anyOn ? Colors.amber : Colors.white54,
                        ),
                      if (contactOpen)
                        const _RoomChip(
                          icon: Icons.meeting_room,
                          label: 'Abierta',
                          color: Color(0xFFFF9800),
                        ),
                      if (motionActive)
                        const _RoomChip(
                          icon: Icons.directions_run,
                          label: 'Movimiento',
                          color: Color(0xFF2196F3),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 28),
          ],
        ),
      ),
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _RoomChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
