import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';

/// "¿Qué temperatura corresponde a esta habitación?" — ÚNICA implementación.
///
/// Antes esta pregunta vivía embebida en `TemperatureSummaryCard` (filtrado por
/// `room.deviceIds` + lectura unificada termómetro/termostato) y su regla de
/// desempate estaba repartida entre esa card, el picker y
/// `RoomTemperatureHeader`. Con el badge de la home habría quedado una cuarta
/// copia: la home y el detalle podían terminar mostrando números distintos para
/// la misma habitación. Todos los call-sites entran ahora por acá.
///
/// El termómetro elegido por el usuario para cada room se persiste aparte
/// (`TempSensorPrefs`, key `home.tempSensorId.<room.id>`); acá entra como
/// parámetro [selectedSensorId] para que el helper quede puro y testeable.
abstract final class RoomTemperature {
  /// Lectura unificada: termómetro (`sensor.temperature`) o termostato
  /// (`state.currentTemp` — en los termostatos `sensor` suele ser null, la
  /// lectura ambiente vive en el estado del equipo).
  static double? reading(Device d) =>
      d.isThermostat ? d.state.currentTemp : d.sensor?.temperature;

  /// Devices con temperatura en el alcance de [room] (null ⇒ toda la casa).
  ///
  /// Termómetros PRIMERO (preservando el insertion order de `service.sensors`)
  /// y termostatos AL FINAL: ese orden es el que define el fallback "primero",
  /// así que moverlo cambiaría qué sensor se muestra en las rooms sin elección
  /// explícita. El picker espeja este mismo pool.
  static List<Device> pool(DevicesService service, RoomRef? room) {
    bool inScope(Device d) => room == null || room.deviceIds.contains(d.id);
    return <Device>[
      ...service.sensors
          .where((s) => s.sensor?.temperature != null)
          .where(inScope),
      ...service.thermostats
          .where((d) => d.state.currentTemp != null)
          .where(inScope),
    ];
  }

  /// Device de LECTURA a mostrar: el elegido por el usuario si sigue en el
  /// pool, si no el primero (fallback histórico). null si no hay ninguno.
  static Device? primary(
    DevicesService service,
    RoomRef? room, {
    String? selectedSensorId,
  }) {
    final available = pool(service, room);
    if (available.isEmpty) return null;
    return available.firstWhere(
      (s) => s.id == selectedSensorId,
      orElse: () => available.first,
    );
  }

  /// Termostato que corresponde renderizar como CONTROL (+/−), o null si
  /// corresponde la lectura. Regla histórica de `RoomTemperatureHeader`:
  ///
  /// - Elegido explícitamente ⇒ ese.
  /// - Elección que ya no matchea ningún termostato ⇒ null (eligió un
  ///   termómetro, o el id guardado murió).
  /// - Sin elección y la room tiene termostato ⇒ el primero (así la room sigue
  ///   mostrando el control con +/− como header único).
  /// - Sin elección y scope = toda la casa ⇒ null (el hero es lectura).
  ///
  /// A diferencia de [pool] NO exige `currentTemp`: un termostato sin lectura
  /// ambiente igual se controla.
  static Device? thermostat(
    DevicesService service,
    RoomRef? room, {
    String? selectedSensorId,
  }) {
    final list = service.thermostats
        .where((d) => room == null || room.deviceIds.contains(d.id))
        .toList();
    if (list.isEmpty) return null;
    if (selectedSensorId != null) {
      for (final d in list) {
        if (d.id == selectedSensorId) return d;
      }
      return null;
    }
    return room == null ? null : list.first;
  }

  /// Device cuya temperatura VE el usuario al abrir la habitación: el control
  /// del termostato gana sobre la lectura (es lo que monta el header).
  static Device? displayed(
    DevicesService service,
    RoomRef? room, {
    String? selectedSensorId,
  }) =>
      thermostat(service, room, selectedSensorId: selectedSensorId) ??
      primary(service, room, selectedSensorId: selectedSensorId);

  /// Temperatura a mostrar para [room] en °C, o null si la habitación no tiene
  /// ningún sensor con lectura. Es el valor que alimenta el badge del
  /// `RoomCard`, y coincide con el que muestra `RoomTemperatureHeader` al
  /// abrir esa habitación.
  static double? forRoom(
    DevicesService service,
    RoomRef? room, {
    String? selectedSensorId,
  }) {
    final shown = displayed(service, room, selectedSensorId: selectedSensorId);
    final value = shown == null ? null : reading(shown);
    if (value != null) return value;
    // Termostato elegido que no reporta lectura ambiente: el badge cae al pool
    // de lectura en vez de quedarse mudo teniendo un termómetro en la room.
    final fallback = primary(service, room, selectedSensorId: selectedSensorId);
    return fallback == null ? null : reading(fallback);
  }
}
