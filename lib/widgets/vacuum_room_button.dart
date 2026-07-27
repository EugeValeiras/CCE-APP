import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/floor_plan.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/status_dot.dart';
import '../utils/icon_resolver.dart';

/// Botón "Limpiar esta habitación" de la pantalla de una room.
///
/// El vínculo room ↔ habitación del mapa del robot se configura en el dashboard
/// (igual que el ícono de la room y el room de Hue) y acá sólo se consume: si
/// el plano de esta room tiene un `vacuumRoom`, aparece este botón y manda a
/// limpiar ESE segmento.
///
/// Devuelve un `SizedBox.shrink()` cuando no hay vínculo, robot o habitación
/// resoluble, así el caller puede insertarlo sin condicionales.
class VacuumRoomButton extends StatelessWidget {
  final DevicesService service;

  /// Plano de la room abierta (de ahí sale el vínculo). Puede ser null en las
  /// rooms de fallback (grupos / huérfanos), que no tienen plano.
  final FloorPlan? plan;

  /// OPT-IN: relieve neumórfico (home teléfono / sidebar tablet).
  final bool neo;

  const VacuumRoomButton({
    super.key,
    required this.service,
    required this.plan,
    this.neo = false,
  });

  @override
  Widget build(BuildContext context) {
    final link = plan?.vacuumRoom;
    if (link == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final device = service.byId(link.deviceId);
        if (device == null) return const SizedBox.shrink();

        // El nombre sale del mapa VIVO del robot, no de una copia guardada: si
        // renombrás la habitación en la app de Roborock, acá se actualiza sola.
        final room = device.state.rooms?.where((r) => r.segmentId == link.segmentId).firstOrNull;
        if (room == null) return const SizedBox.shrink();

        final queue = device.state.roomQueue;
        // Con una cola en curso manda el tramo actual; si no, alcanza con que
        // el robot esté limpiando.
        final cleaning = queue != null
            ? queue.currentSegment == link.segmentId
            : device.state.vacuumState == 'cleaning';
        final accent = cleaning ? CceColors.ok : CceColors.textSecondary;

        return CceCard(
          onTap: cleaning
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  final ok = await service.cleanVacuumRooms(device, [link.segmentId]);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No pude mandar a limpiar ${room.name}')),
                    );
                  }
                },
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: neo ? 28 : 32,
                    color: accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    // Ícono CONFIGURADO del robot (el mismo del tile y el plano),
                    // no uno fijo: si lo cambiás en el dashboard, esto lo sigue.
                    child: IconResolver.widget(
                      device,
                      configuredIcon: service.iconFor(device.id),
                      customIcons: service.customIcons,
                      displayName: service.displayName(device),
                      size: 28,
                      color: accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleaning ? 'Limpiando…' : 'Limpiar esta habitación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: neo
                          ? CceText.title.copyWith(fontSize: 15)
                          : const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: CceColors.textPrimary,
                            ),
                    ),
                    SizedBox(height: neo ? 4 : 2),
                    Row(
                      children: [
                        if (cleaning) ...[
                          StatusDot(accent, pulse: true, semanticLabel: 'Limpiando'),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            _subtitle(room.name, queue, link.segmentId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CceText.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Cuando la habitación es parte de una cola, el turno importa más que el
  /// nombre solo: decir "2 de 5" evita que parezca que no arrancó.
  String _subtitle(String roomName, VacuumRoomQueue? queue, int segmentId) {
    if (queue == null) return roomName;
    final position = queue.segments.indexOf(segmentId);
    if (position < 0) return roomName;
    return '$roomName · ${position + 1} de ${queue.segments.length}';
  }
}
