import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/device.dart';
import '../../models/room_ref.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/room_card.dart';
import '../../utils/icon_resolver.dart';
import '../../widgets/pulse_on_update.dart';

/// Sidebar de habitaciones estilo Hue (tablet): entrada fija "Toda la casa"
/// + una [RoomCard] por habitacion derivada de [DevicesService.rooms].
/// Los estados de puerta/movimiento van como dots integrados al subtítulo
/// (motion/contactOpen de RoomCard); los toggles son optimistas con error
/// real: si alguna luz falla, SnackBar con Reintentar.
class RoomsSidebar extends StatefulWidget {
  const RoomsSidebar({
    super.key,
    required this.service,
    required this.selectedRoomId,
    required this.onSelect,
    this.neo = false,
  });

  final DevicesService service;
  final String? selectedRoomId;
  final ValueChanged<String?> onSelect; // null = Toda la casa
  final bool neo;

  @override
  State<RoomsSidebar> createState() => _RoomsSidebarState();
}

class _RoomsSidebarState extends State<RoomsSidebar> {
  // Toggle de "Toda la casa" deshabilitado durante la ráfaga (máx 1.5 s).
  bool _allHouseBusy = false;
  Timer? _allHouseTimer;

  @override
  void dispose() {
    _allHouseTimer?.cancel();
    super.dispose();
  }

  Widget _roomIcon(RoomRef room) {
    final device =
        room.deviceIds.map(widget.service.byId).whereType<Device>().firstOrNull;
    if (device == null) return const CceIcon(CceIcons.room);
    return Icon(IconResolver.resolve(
      device,
      configuredIcon: room.iconName ?? widget.service.iconFor(device.id),
      displayName: widget.service.displayName(device),
    ));
  }

  void _showRetrySnack(String message, VoidCallback retry) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Reintentar', onPressed: retry),
      ),
    );
  }

  Future<void> _toggleRoom(RoomRef room, bool on) async {
    final ok = await widget.service.setRoomOn(room, on);
    if (ok) return;
    _showRetrySnack(
      "No se pudo ${on ? 'prender' : 'apagar'} ${room.name}",
      () => _toggleRoom(room, on),
    );
  }

  Future<void> _toggleAllHouse(bool on) async {
    if (_allHouseBusy) return;
    setState(() => _allHouseBusy = true);
    // Tope duro de 1.5 s: si la ráfaga tarda más, el switch se rehabilita
    // igual (sin spinner).
    _allHouseTimer?.cancel();
    _allHouseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _allHouseBusy) setState(() => _allHouseBusy = false);
    });

    final rooms = widget.service.rooms;
    final results = await Future.wait(
      rooms.map((r) => widget.service.setRoomOn(r, on)),
    );
    _allHouseTimer?.cancel();
    if (!mounted) return;
    setState(() => _allHouseBusy = false);
    if (results.any((ok) => !ok)) {
      _showRetrySnack(
        "No se pudo ${on ? 'prender' : 'apagar'} toda la casa",
        () => _toggleAllHouse(on),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final rooms = service.rooms;
        final allLights = service.lights;
        final allOnCount = allLights.where((l) => l.state.on).length;
        final motionRooms =
            rooms.where((r) => service.statsFor(r).anyMotion).length;
        final allSubtitle = '$allOnCount/${allLights.length}'
            '${motionRooms > 0 ? ' · $motionRooms con movimiento' : ''}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text('CCE', style: CceText.display),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: rooms.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // Entrada fija: vista general de la casa.
                    return RoomCard(
                      title: 'Toda la casa',
                      icon: const CceIcon(CceIcons.allHouse),
                      lightsOn: allOnCount,
                      lightsTotal: allLights.length,
                      anyOn: allOnCount > 0,
                      brightness: null,
                      selected: widget.selectedRoomId == null,
                      subtitleOverride: allSubtitle,
                      toggleEnabled: !_allHouseBusy,
                      neo: widget.neo,
                      onTap: () => widget.onSelect(null),
                      onToggle: _toggleAllHouse,
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
                      tintColors: stats.tintColors,
                      brightness: stats.avgBrightness,
                      selected: widget.selectedRoomId == room.id,
                      motion: stats.anyMotion,
                      contactOpen: stats.anyContactOpen,
                      neo: widget.neo,
                      onTap: () => widget.onSelect(room.id),
                      onToggle: (v) => _toggleRoom(room, v),
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
