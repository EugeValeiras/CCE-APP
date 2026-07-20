import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
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
class RoomTemperatureHeader extends StatefulWidget {
  final DevicesService service;
  final RoomRef? room;
  final bool compact;
  final bool neo;

  const RoomTemperatureHeader({
    super.key,
    required this.service,
    this.room,
    this.compact = false,
    this.neo = false,
  });

  @override
  State<RoomTemperatureHeader> createState() => _RoomTemperatureHeaderState();
}

class _RoomTemperatureHeaderState extends State<RoomTemperatureHeader> {
  /// Id del termómetro elegido para ESTA room (null ⇒ primero). La card cae
  /// al primero si el id guardado ya no existe (mismo fallback que la home).
  String? _tempSensorId;

  // room == null ⇒ comparte 'home.tempSensorId' con el hero del phone
  // (rooms_list_screen): un solo termómetro de la casa para ambos heros.
  String get _prefKey {
    final r = widget.room;
    return r == null ? 'home.tempSensorId' : 'home.tempSensorId.${r.id}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RoomTemperatureHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El RoomPanel del tablet se reconstruye con OTRA room en la misma
    // posición del árbol al cambiar la selección: reseteamos y recargamos
    // para no mostrar la selección de la room anterior.
    if (oldWidget.room?.id != widget.room?.id) {
      setState(() => _tempSensorId = null);
      _load();
    }
  }

  Future<void> _load() async {
    // Captura la key ANTES del await: si la room cambia mientras carga, el
    // resultado viejo se descarta (guarda de carrera).
    final key = _prefKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved != null && mounted && key == _prefKey) {
        setState(() => _tempSensorId = saved);
      }
    } catch (_) {}
  }

  Future<void> _save(String id) async {
    if (mounted) setState(() => _tempSensorId = id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, id);
    } catch (_) {}
  }

  Future<void> _openPicker() async {
    // Captura la room ANTES del await: en tablet el RoomPanel puede
    // reconstruirse con OTRA room mientras el sheet está abierto; si eso
    // pasa, el resultado se descarta para no contaminar la key de la room
    // nueva con un sensor ajeno (misma guarda que _load).
    final room = widget.room;
    final picked = await TemperatureSensorPickerSheet.show(
      context,
      service: widget.service,
      selectedId: _tempSensorId,
      room: room,
    );
    if (picked == null || !mounted || widget.room?.id != room?.id) return;
    _save(picked);
  }

  /// Termostatos en el alcance (room o casa).
  List<Device> get _thermostats {
    final r = widget.room;
    return widget.service.thermostats
        .where((d) => r == null || r.deviceIds.contains(d.id))
        .toList();
  }

  /// El termostato a mostrar como control, o null si corresponde la lectura.
  ///
  /// - Elegido explícitamente ⇒ ese.
  /// - Sin elección previa y hay termostato en la room ⇒ el termostato (así la
  ///   room sigue mostrando el control con +/− como antes, ahora como header
  ///   ÚNICO en vez de duplicar la temperatura).
  Device? get _selectedThermostat {
    final list = _thermostats;
    if (list.isEmpty) return null;
    final id = _tempSensorId;
    if (id != null) {
      for (final d in list) {
        if (d.id == id) return d;
      }
      return null; // eligió un termómetro
    }
    return widget.room == null ? null : list.first;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final thermostat = _selectedThermostat;
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
          selectedSensorId: _tempSensorId,
          onLongPress: _openPicker,
        );
      },
    );
  }
}
