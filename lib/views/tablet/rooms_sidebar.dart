import 'package:flutter/material.dart';
import '../../models/device.dart';
import '../../models/room_ref.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/room_card.dart';
import '../../theme/components/status_pill.dart';
import '../../utils/icon_resolver.dart';
import '../../widgets/pulse_on_update.dart';

/// Sidebar de habitaciones estilo Hue (tablet): entrada fija "Toda la casa"
/// + una [RoomCard] por habitacion derivada de [DevicesService.rooms].
class RoomsSidebar extends StatelessWidget {
  const RoomsSidebar({
    super.key,
    required this.service,
    required this.selectedRoomId,
    required this.onSelect,
  });

  final DevicesService service;
  final String? selectedRoomId;
  final ValueChanged<String?> onSelect; // null = Toda la casa

  Widget _roomIcon(RoomRef room) {
    final device =
        room.deviceIds.map(service.byId).whereType<Device>().firstOrNull;
    if (device == null) return const CceIcon(CceIcons.room);
    return Icon(IconResolver.resolve(
      device,
      configuredIcon: room.iconName ?? service.iconFor(device.id),
      displayName: service.displayName(device),
    ));
  }

  List<Widget> _chipsFor(RoomStats stats) {
    return <Widget>[
      if (stats.anyContactOpen)
        const StatusPill(
          label: 'Abierta',
          color: CceColors.contact,
          foreground: Color(0xFF2B1500),
        ),
      if (stats.anyMotion)
        const StatusPill(
          label: 'Movimiento',
          color: CceColors.motion,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final rooms = service.rooms;
        final allLights = service.lights;
        final allOnCount = allLights.where((l) => l.state.on).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text('Mi casa', style: CceText.display),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: rooms.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // Entrada fija: vista general de la casa (plano completo).
                    return RoomCard(
                      title: 'Toda la casa',
                      icon: const CceIcon(CceIcons.allHouse),
                      lightsOn: allOnCount,
                      lightsTotal: allLights.length,
                      anyOn: allOnCount > 0,
                      brightness: null,
                      selected: selectedRoomId == null,
                      onTap: () => onSelect(null),
                      onToggle: (v) {
                        for (final r in rooms) {
                          service.setRoomOn(r, v);
                        }
                      },
                    );
                  }

                  final room = rooms[i - 1];
                  final stats = service.statsFor(room);
                  return PulseOnUpdate(
                    triggerAt: stats.latestEventAt,
                    borderRadius: CceRadii.card,
                    child: RoomCard(
                      title: room.name,
                      icon: _roomIcon(room),
                      lightsOn: stats.lightsOn,
                      lightsTotal: stats.lightsTotal,
                      anyOn: stats.anyOn,
                      tint: stats.tint,
                      brightness: stats.avgBrightness,
                      selected: selectedRoomId == room.id,
                      statusChips: _chipsFor(stats),
                      onTap: () => onSelect(room.id),
                      onToggle: (v) => service.setRoomOn(room, v),
                      onBrightnessCommitted: (v) =>
                          service.setRoomBrightness(room, v),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
