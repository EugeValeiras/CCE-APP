import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import 'temperature_sensor_picker_sheet.dart';
import 'temperature_summary_card.dart';

/// Header de clima de UNA habitación (phone y tablet): TemperatureSummaryCard
/// scopeada a [room] + persistencia del termómetro elegido por room
/// (key `home.tempSensorId.<room.id>`, mismo namespace que el hero de la home).
/// La card resuelve sola el resto: >1 sensor → tappable con chevron (abre el
/// picker filtrado a la room), 1 sensor → estática, 0 → se auto-oculta.
class RoomTemperatureHeader extends StatefulWidget {
  final DevicesService service;
  final RoomRef room;
  final bool compact;
  final bool neo;

  const RoomTemperatureHeader({
    super.key,
    required this.service,
    required this.room,
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

  String get _prefKey => 'home.tempSensorId.${widget.room.id}';

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
    if (oldWidget.room.id != widget.room.id) {
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
    if (picked == null || !mounted || widget.room.id != room.id) return;
    _save(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TemperatureSummaryCard(
      service: widget.service,
      room: widget.room,
      compact: widget.compact,
      neo: widget.neo,
      selectedSensorId: _tempSensorId,
      onTap: _openPicker,
    );
  }
}
