import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/room_card.dart';
import '../utils/icon_resolver.dart';
import '../widgets/pulse_on_update.dart';
import '../widgets/temperature_summary_card.dart';
import 'room_detail_screen.dart';

/// Lista de habitaciones estilo Hue (phone). Las habitaciones y sus stats
/// salen SIEMPRE de DevicesService (rooms / statsFor) — acá no se deriva nada.
class RoomsListScreen extends StatelessWidget {
  final DevicesService service;
  const RoomsListScreen({super.key, required this.service});

  /// Ícono de la habitación: el configurado (iconName) resuelto vía
  /// IconResolver con un device representativo, o el genérico de sala.
  Widget _roomIcon(RoomRef room) {
    final rep =
        room.deviceIds.map(service.byId).whereType<Device>().firstOrNull;
    if (room.iconName != null && room.iconName!.isNotEmpty && rep != null) {
      return Icon(
        IconResolver.resolve(rep,
            configuredIcon: room.iconName, displayName: room.name),
      );
    }
    return const CceIcon(CceIcons.room);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.loading && service.all.isEmpty) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: CceColors.textTertiary),
            ),
          );
        }

        final rooms = service.rooms;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: const Text('Mi casa', style: CceText.display),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: CceColors.textSecondary),
                onPressed: service.refresh,
              ),
            ],
          ),
          body: rooms.isEmpty
              ? Center(
                  child: Text(
                    service.error ?? 'No hay habitaciones configuradas',
                    style: CceText.caption,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: service.refresh,
                  color: CceColors.textPrimary,
                  backgroundColor: CceColors.surfaceHigh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rooms.length + 1,
                    separatorBuilder: (context, idx) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        // Resumen de clima de toda la casa (se auto-oculta
                        // si no hay sensores de temperatura/humedad).
                        return TemperatureSummaryCard(service: service);
                      }
                      final room = rooms[i - 1];
                      return _buildRoomCard(context, room);
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _buildRoomCard(BuildContext context, RoomRef room) {
    final stats = service.statsFor(room);
    return PulseOnUpdate(
      triggerAt: stats.latestEventAt,
      color: stats.anyOn && stats.tint != null ? stats.tint! : CceColors.info,
      borderRadius: CceRadii.card,
      child: RoomCard(
        title: room.name,
        icon: _roomIcon(room),
        lightsOn: stats.lightsOn,
        lightsTotal: stats.lightsTotal,
        anyOn: stats.anyOn,
        tint: stats.tint,
        tintColors: stats.tintColors,
        // compact nunca muestra slider; el brillo por sala vive en el detalle.
        brightness: null,
        compact: true,
        motion: stats.anyMotion,
        contactOpen: stats.anyContactOpen,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RoomDetailScreen(
              title: room.name,
              deviceIds: room.deviceIds,
              service: service,
              room: room,
            ),
          ));
        },
        onToggle: (v) => service.setRoomOn(room, v),
      ),
    );
  }
}
