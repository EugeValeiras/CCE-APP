import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Bottom-sheet que lista los termómetros disponibles para elegir cuál
/// mostrar como hero de clima. Con [room] == null lista TODA la casa (hero de
/// la home); con [room] != null solo los de esa habitación (header por room).
/// Devuelve el id del sensor elegido (o null si se cierra sin elegir).
/// [selectedId] marca el actual.
///
/// Vive escuchando a [service] (AnimatedBuilder) para que las lecturas de la
/// lista se mantengan frescas mientras el sheet está abierto.
class TemperatureSensorPickerSheet extends StatelessWidget {
  final DevicesService service;
  final String? selectedId;
  final RoomRef? room;

  const TemperatureSensorPickerSheet({
    super.key,
    required this.service,
    this.selectedId,
    this.room,
  });

  /// Abre el selector y resuelve con el id elegido (o null si se descartó).
  static Future<String?> show(
    BuildContext context, {
    required DevicesService service,
    String? selectedId,
    RoomRef? room,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TemperatureSensorPickerSheet(
          service: service, selectedId: selectedId, room: room),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        // Pool disponible: espejo EXACTO del de TemperatureSummaryCard
        // (termómetros primero, termostatos apendeados al final) para que
        // effectiveId / fila marcada coincidan con el hero. Los where
        // preservan el insertion order de service.sensors, y el fallback
        // "primero" se calcula ANTES de ordenar alfabéticamente para que la
        // fila marcada coincida con lo que muestra la card.
        final thermometers = service.sensors
            .where((s) => s.sensor?.temperature != null)
            .where((s) => room == null || room!.deviceIds.contains(s.id))
            .toList();
        final available = <Device>[
          ...thermometers,
          // Termostatos: solo si también hay termómetros (regla del dueño;
          // ver TemperatureSummaryCard). Elegir el termostato como hero de
          // una room DUPLICA la lectura junto a ThermostatHeaderCard —
          // aceptado por ser una elección explícita del usuario.
          if (thermometers.isNotEmpty)
            ...service.thermostats
                .where((d) => room == null || room!.deviceIds.contains(d.id))
                .where((d) => d.state.currentTemp != null),
        ];
        // Id efectivamente mostrado: el elegido si sigue disponible;
        // si no (o si nunca se eligió), el primero — idéntico al fallback de
        // TemperatureSummaryCard, así la fila marcada coincide con el hero.
        final effectiveId = (selectedId != null &&
                available.any((s) => s.id == selectedId))
            ? selectedId
            : (available.isNotEmpty ? available.first.id : null);
        final sensors = available
          ..sort((a, b) => service
              .displayName(a)
              .toLowerCase()
              .compareTo(service.displayName(b).toLowerCase()));

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: CceColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: CceColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Temperatura', style: CceText.title),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      room == null
                          ? 'Elegí cuál mostrar en la home'
                          : 'Elegí cuál mostrar en ${room!.name}',
                      style: CceText.caption,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (sensors.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No hay termómetros disponibles',
                            style: CceText.caption),
                      ),
                    )
                  else
                    for (final s in sensors) ...[
                      _SensorRow(
                        name: service.displayName(s),
                        // En modo scopeado la room es siempre la misma:
                        // omitimos el nombre redundante en cada fila.
                        room: room == null ? _roomNameFor(s.id) : null,
                        // Lectura unificada: termostato → state.currentTemp
                        // (su `sensor` suele ser null); termómetro →
                        // sensor.temperature. Non-null garantizado por los
                        // filtros de `available`.
                        temperature: (s.isThermostat
                            ? s.state.currentTemp
                            : s.sensor?.temperature)!,
                        humidity: s.sensor?.humidity,
                        selected: s.id == effectiveId,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(s.id);
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Nombre de la habitación que contiene al sensor (o null si es huérfano).
  String? _roomNameFor(String deviceId) {
    for (final RoomRef r in service.rooms) {
      if (r.deviceIds.contains(deviceId)) return r.name;
    }
    return null;
  }
}

/// Fila de un termómetro en el selector. Hundida (neoInset) cuando NO está
/// elegido; extruida con borde de acento cuando SÍ.
class _SensorRow extends StatelessWidget {
  final String name;
  final String? room;
  final double temperature;
  final double? humidity;
  final bool selected;
  final VoidCallback onTap;

  const _SensorRow({
    required this.name,
    required this.room,
    required this.temperature,
    required this.humidity,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _colorForTemp(temperature);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CceRadii.hueCard),
        child: Ink(
          decoration: BoxDecoration(
            color: CceColors.neoSunken,
            borderRadius: BorderRadius.circular(CceRadii.hueCard),
            boxShadow: CceShadows.neoInset(),
            border: selected
                ? Border.all(color: accent.withValues(alpha: 0.85), width: 1.5)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              CceIcon(CceIcons.thermometer,
                  size: 22, color: accent, emboss: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CceColors.textPrimary,
                      ),
                    ),
                    if (room != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        room!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CceText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${temperature.toStringAsFixed(1)}°',
                    style: CceText.title.copyWith(color: accent),
                  ),
                  if (humidity != null)
                    Text(
                      '${humidity!.toStringAsFixed(0)}% hum',
                      style: CceText.caption,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Marca de selección: check en acento cuando es el elegido; un
              // hueco tenue cuando no, para reservar el ancho (sin saltos).
              SizedBox(
                width: 22,
                child: selected
                    ? CceIcon(CceIcons.check,
                        size: 20, color: accent, emboss: false)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Misma escala térmica que TemperatureSummaryCard (sin desaturar: acá el
  // color es la señal principal de cada fila).
  static Color _colorForTemp(double t) {
    if (t < 15) return const Color(0xFF42A5F5);
    if (t < 20) return const Color(0xFF66BB6A);
    if (t < 25) return const Color(0xFFFFB74D);
    if (t < 30) return const Color(0xFFFF8A65);
    return const Color(0xFFE53935);
  }
}
