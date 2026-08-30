import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/room_ref.dart';
import '../../services/devices_service.dart';
import '../../services/temp_sensor_prefs.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_logo.dart';
import '../../theme/components/room_card.dart';
import '../../utils/room_ambient.dart';
import '../../utils/room_icon.dart';
import '../../utils/room_temperature.dart';
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
    this.deviceCards = const <Widget>[],
  });

  final DevicesService service;
  final String? selectedRoomId;
  final ValueChanged<String?> onSelect; // null = Toda la casa
  final bool neo;

  /// Cards de dispositivos dedicados (TV, JBL) que se insertan en la lista
  /// DESPUÉS de "Toda la casa" y antes de las salas, para que aparezcan como
  /// parte de la lista (no como una sección separada).
  final List<Widget> deviceCards;

  @override
  State<RoomsSidebar> createState() => _RoomsSidebarState();
}

class _RoomsSidebarState extends State<RoomsSidebar> {
  // Toggle de "Toda la casa" deshabilitado durante la ráfaga (máx 1.5 s).
  bool _allHouseBusy = false;
  Timer? _allHouseTimer;

  @override
  void initState() {
    super.initState();
    // Termómetro elegido por habitación: alimenta el badge de cada RoomCard.
    // Se carga una vez y queda cacheado (el build lo necesita síncrono).
    TempSensorPrefs.instance.ensureLoaded();
  }

  @override
  void dispose() {
    _allHouseTimer?.cancel();
    super.dispose();
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

  /// Encabezado de sección (CceText.section, UPPERCASE): separa grupos del
  /// header sin meter cajas, idéntico a la home del teléfono. Padding-left chico
  /// para alinearlo ópticamente con el contenido de las cards (que tienen su
  /// propio padding interno).
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: CceText.section),
    );
  }

  /// RoomCard de una sala con su PulseOnUpdate (halo al recibir un evento) y
  /// todos los handlers intactos: selección, toggle optimista y commit de brillo
  /// (el slider embebido es exclusivo del sidebar tablet).
  Widget _buildRoomCard(DevicesService service, RoomRef room) {
    final stats = service.statsFor(room);
    return PulseOnUpdate(
      triggerAt: stats.latestEventAt,
      borderRadius: CceRadii.card,
      child: RoomCard(
        title: room.name,
        iconBuilder: roomGlyphBuilder(room, service),
        lightsOn: stats.lightsOn,
        lightsTotal: stats.lightsTotal,
        anyOn: stats.anyOn,
        tint: stats.tint,
        tintColors: stats.tintColors,
        brightness: stats.avgBrightness,
        selected: widget.selectedRoomId == room.id,
        motion: stats.anyMotion,
        contactOpen: stats.anyContactOpen,
        // Badge de temperatura: MISMO helper y MISMA elección de termómetro
        // que el header del detalle de la habitación. null (sin sensor) ⇒ la
        // card se ve igual que antes. OJO: la fila "Toda la casa" de abajo NO
        // es una habitación y por eso no pasa este parámetro.
        temperature: RoomTemperature.forRoom(
          service,
          room,
          selectedSensorId: TempSensorPrefs.instance.idFor(room.id),
        ),
        // Chips de sensores para las salas sin luces (CCE#57), igual que en la
        // home del teléfono: el sidebar monta la MISMA card y no puede
        // divergir. La fila "Toda la casa" de abajo no es una habitación y por
        // eso tampoco los pasa.
        chips: stats.lightsTotal == 0
            ? RoomAmbient.forRoom(
                service,
                room,
                selectedSensorId: TempSensorPrefs.instance.idFor(room.id),
              )
            : const [],
        neo: widget.neo,
        onTap: () => widget.onSelect(room.id),
        onToggle: (v) => _toggleRoom(room, v),
        onBrightnessCommitted: (v) => service.setRoomBrightness(room, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // merge: además de los eventos de sensor (service), el badge de
      // temperatura depende del termómetro elegido para cada room — elegirlo
      // en el detalle debe reflejarse en el sidebar sin recargar nada.
      animation: Listenable.merge([widget.service, TempSensorPrefs.instance]),
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
            // Logo de la app arriba de todo (igual que en la home del teléfono),
            // en vez del texto "CCE". Tinte titleInk (gris-claro de "material"):
            // iguala la tinta de todos los títulos embossed del appbar/home, en
            // vez del casi-blanco anterior que brillaba de más.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: CceLogo(height: 22, color: CceText.titleInk),
            ),
            Expanded(
              // Misma jerarquía por AIRE que la home del teléfono (no por cajas):
              // "Toda la casa" (hero) → [gap 20] → label DESTACADOS → cards de
              // dispositivos (TV/JBL, gap 12 entre sí) → [gap 20] → label
              // HABITACIONES → grilla de salas (gap 12). Gaps mayores ENTRE
              // grupos (20) que DENTRO de un grupo (12) crean la jerarquía sin
              // bordes. Toda la funcionalidad (selección/toggle/onTap/brillo) se
              // conserva intacta.
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  // HERO: vista general de toda la casa.
                  RoomCard(
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
                  ),
                  // Grupo "destacados" (dispositivos dedicados): solo se muestra
                  // el encabezado si hay al menos una card de dispositivo.
                  if (widget.deviceCards.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('Destacados'),
                    const SizedBox(height: 10),
                    for (var j = 0; j < widget.deviceCards.length; j++) ...[
                      if (j > 0) const SizedBox(height: 12),
                      widget.deviceCards[j],
                    ],
                  ],
                  // Grupo "habitaciones": encabezado de la grilla de salas.
                  if (rooms.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('Habitaciones'),
                    const SizedBox(height: 10),
                    for (var j = 0; j < rooms.length; j++) ...[
                      if (j > 0) const SizedBox(height: 12),
                      _buildRoomCard(service, rooms[j]),
                    ],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
