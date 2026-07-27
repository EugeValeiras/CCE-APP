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
        // Índice de ESTA habitación dentro de la cola (-1 = no está en la cola).
        final index = queue?.segments.indexOf(link.segmentId) ?? -1;
        final enCola = index >= 0;
        final cleaning = enCola
            ? index == queue!.current
            : queue == null && device.state.vacuumState == 'cleaning';
        // Cuántas hay que limpiar ANTES que esta. Sirve igual venga de una
        // limpieza total o de haberla encolado a mano.
        final faltan = enCola ? index - queue!.current : 0;
        final accent = cleaning
            ? CceColors.ok
            : (enCola ? CceColors.warm : CceColors.textSecondary);

        return CceCard(
          // Ya NO se bloquea mientras el robot trabaja: tocarlo la ENCOLA. Sólo
          // queda inerte si esta habitación ya es la que se está limpiando.
          onTap: cleaning
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  final ok = await service.cleanVacuumRooms(device, [link.segmentId]);
                  if (!context.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No pude mandar a limpiar ${room.name}')),
                    );
                  } else if (enCola) {
                    // Ya estaba: se avisa en vez de dejar creer que se sumó otra vez.
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${room.name} ya está en la cola')),
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
                      _title(cleaning: cleaning, enCola: enCola, faltan: faltan),
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
                        if (cleaning || enCola) ...[
                          StatusDot(accent,
                              pulse: cleaning,
                              semanticLabel: cleaning ? 'Limpiando' : 'En cola'),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            _subtitle(room.name, queue, index),
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

  /// El título dice el ESTADO, que es lo primero que se mira.
  ///
  /// Con el robot ocupado el botón ya no se bloquea: sumarla a la cola es una
  /// acción válida, así que el texto tiene que decir qué va a pasar si lo tocás
  /// y, si ya está encolada, cuánto falta para que le toque.
  String _title({required bool cleaning, required bool enCola, required int faltan}) {
    if (cleaning) return 'Limpiando…';
    if (!enCola) return 'Limpiar esta habitación';
    if (faltan <= 0) return 'En cola · es la próxima';
    if (faltan == 1) return 'En cola · falta 1 antes';
    return 'En cola · faltan $faltan antes';
  }

  /// El subtítulo ancla el nombre de la habitación y, dentro de una cola, su
  /// número: "Kitchen · 2 de 5". Sin cola es sólo el nombre.
  String _subtitle(String roomName, VacuumRoomQueue? queue, int index) {
    if (queue == null || index < 0) return roomName;
    return '$roomName · ${index + 1} de ${queue.segments.length}';
  }
}
