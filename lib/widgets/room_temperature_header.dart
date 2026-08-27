import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../services/temp_sensor_prefs.dart';
import '../utils/room_temperature.dart';
import 'thermostat_header_card.dart';
import 'temperature_sensor_picker_sheet.dart';
import 'temperature_summary_card.dart';

/// Header de clima de UNA habitación (phone y tablet): TemperatureSummaryCard
/// scopeada a [room] + persistencia del termómetro elegido por room
/// (key `home.tempSensorId.<room.id>`, mismo namespace que el hero de la home).
/// Con [room] == null el scope es TODA LA CASA (hero del tablet) y persiste
/// en la MISMA key que el hero del phone (`home.tempSensorId`): un solo
/// termómetro elegido para ambos form factors.
/// La card resuelve sola el resto: >1 sensor → tappable (abre el picker
/// filtrado a la room), 1 sensor → estática, 0 → se auto-oculta.
/// Header ÚNICO de clima: muestra lo que el usuario eligió — un termómetro
/// (lectura) o el TERMOSTATO (control con +/−). El selector se abre con
/// LONG-PRESS (el tap queda para la acción propia de cada card: abrir el
/// detalle del termostato).
///
/// Antes la room mostraba DOS cards (lectura + termostato) con la misma
/// temperatura duplicada; ahora es una sola y la elige el usuario.
///
/// La elección vive en [TempSensorPrefs] (cache compartido) y la resolución en
/// [RoomTemperature]: el badge de la home entra por las mismas dos puertas, así
/// que muestra el mismo número que este header.
class RoomTemperatureHeader extends StatefulWidget {
  final DevicesService service;
  final RoomRef? room;
  final bool compact;
  final bool neo;

  /// Tercera columna con las luces encendidas de toda la casa (hero de la
  /// home). Sólo aplica cuando el header cae a [TemperatureSummaryCard].
  final bool showLightsOn;

  const RoomTemperatureHeader({
    super.key,
    required this.service,
    this.room,
    this.compact = false,
    this.neo = false,
    this.showLightsOn = false,
  });

  @override
  State<RoomTemperatureHeader> createState() => _RoomTemperatureHeaderState();
}

class _RoomTemperatureHeaderState extends State<RoomTemperatureHeader> {
  TempSensorPrefs get _prefs => TempSensorPrefs.instance;

  /// Id del termómetro elegido para ESTA room (null ⇒ primero). Se lee del
  /// cache compartido en cada build, así que el RoomPanel del tablet puede
  /// reconstruirse con OTRA room en la misma posición del árbol sin arrastrar
  /// la selección de la anterior (antes hacía falta un didUpdateWidget).
  String? get _tempSensorId => _prefs.idFor(widget.room?.id);

  @override
  void initState() {
    super.initState();
    _prefs.ensureLoaded();
  }

  Future<void> _openPicker() async {
    // Captura la room ANTES del await: en tablet el RoomPanel puede
    // reconstruirse con OTRA room mientras el sheet está abierto; si eso
    // pasa, el resultado se descarta para no contaminar la key de la room
    // nueva con un sensor ajeno.
    final room = widget.room;
    final picked = await TemperatureSensorPickerSheet.show(
      context,
      service: widget.service,
      selectedId: _tempSensorId,
      room: room,
    );
    if (picked == null || !mounted || widget.room?.id != room?.id) return;
    _prefs.select(room?.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // merge: además de los eventos de sensor (service), el header se
      // reconstruye cuando cambia el termómetro elegido — la elección ya no es
      // estado local, la comparte con el badge de la home.
      animation: Listenable.merge([widget.service, _prefs]),
      builder: (context, _) {
        final selectedId = _tempSensorId;
        final Device? thermostat = RoomTemperature.thermostat(
          widget.service,
          widget.room,
          selectedSensorId: selectedId,
        );
        if (thermostat != null) {
          // Control con +/− accionable. Long-press abre el selector.
          return ThermostatHeaderCard(
            device: thermostat,
            service: widget.service,
            neo: widget.neo,
            onLongPress: _openPicker,
          );
        }
        return TemperatureSummaryCard(
          service: widget.service,
          room: widget.room,
          compact: widget.compact,
          neo: widget.neo,
          selectedSensorId: selectedId,
          showLightsOn: widget.showLightsOn,
          onLongPress: _openPicker,
        );
      },
    );
  }
}
