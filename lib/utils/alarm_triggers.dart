/// Qué sensores disparan la alarma: el mapa `sensorAlarmTriggers` de la
/// config del backend (`GET /config/sensor-alarm-triggers`), leído siempre a
/// través de estos helpers.
///
/// El mapa está indexado POR DEVICE, pero mezcla ids canónicos (`dev_*`) con
/// ids de provider (`ewelink_*`, `matter_*`) según cuándo se guardó cada
/// entrada. Por eso "¿este device dispara?" no es `triggers[d.id]`: hay que
/// probar también los bindings. Filtrar sólo por el id canónico esconde
/// sensores que hoy están marcados, que es el error caro en una lista de
/// seguridad — mostrar de más se nota, mostrar de menos no.
library;

import '../models/alarm_mode.dart';
import '../models/device.dart';
import '../services/api_service.dart';

/// ¿Este device está marcado para disparar la alarma?
///
/// Prueba el id canónico y todos los `bindingIds`, igual que lo hacía a mano
/// el detalle de sensor antes de que esto existiera.
bool firesAlarm(Device device, Map<String, bool> triggers) {
  if (triggers.isEmpty) return false;
  if (triggers[device.id] == true) return true;
  for (final binding in device.bindingIds) {
    if (triggers[binding] == true) return true;
  }
  return false;
}

/// Las claves del mapa bajo las que ESTE device figura marcado. Vacío si no
/// dispara. Sirve para apagarlo de verdad: una entrada vieja guardada con el
/// bindingId no se borra escribiendo el id canónico.
List<String> firingKeys(Device device, Map<String, bool> triggers) => [
      for (final id in [device.id, ...device.bindingIds])
        if (triggers[id] == true) id,
    ];

/// En qué tipo de alarma participa este device (CCE#133).
///
/// Misma disciplina que [firesAlarm]: el mapa de niveles se indexa igual que
/// el de disparos, así que se prueba el id canónico Y los bindings. Sin nivel
/// escrito vale `interior` — el lado conservador para el perímetro.
SensorAlarmLevel levelOf(Device device, Map<String, String> levels) {
  for (final id in [device.id, ...device.bindingIds]) {
    final raw = levels[id];
    if (raw != null) return SensorAlarmLevel.fromWire(raw);
  }
  return SensorAlarmLevel.interior;
}

/// ¿Este device hace sonar la alarma con [mode] armada?
///
/// Las DOS preguntas juntas, que es como hay que hacerlas: participa
/// ([firesAlarm]) **y** su nivel entra en este tipo. Preguntar sólo la primera
/// es lo que hacía que la pantalla prometiera protección que no existe.
bool firesAlarmInMode(
  Device device,
  Map<String, bool> triggers,
  Map<String, String> levels,
  AlarmMode mode,
) =>
    firesAlarm(device, triggers) &&
    sensorFiresInMode(mode, levelOf(device, levels));

/// El nivel sugerido por lo que el sensor sabe medir: una apertura es
/// perímetro, un movimiento es interior. Es el mismo reparto que hace el
/// backend al marcar sin decir el nivel, y el que la pantalla propone.
SensorAlarmLevel suggestedLevel(Device device) => device.isContactSensor
    ? SensorAlarmLevel.perimeter
    : SensorAlarmLevel.interior;

/// Cambia el NIVEL de este device y devuelve el mapa ya actualizado.
///
/// Escribe SIEMPRE el id canónico, igual que prender el disparo, y limpia de
/// paso las claves legacy bajo las que el device tuviera un nivel viejo: dos
/// niveles para el mismo sensor es una pregunta sin respuesta, y el backend
/// resolvería la que encuentre primero.
Future<Map<String, String>> writeSensorAlarmLevel(
  ApiService api,
  Device device,
  Map<String, String> levels, {
  required SensorAlarmLevel level,
}) async {
  await api.setSensorAlarmLevel(device.id, level);
  final next = Map<String, String>.from(levels);
  for (final binding in device.bindingIds) {
    next.remove(binding);
  }
  next[device.id] = level.wire;
  return next;
}

/// Prende o apaga que este device dispare la alarma, y devuelve el mapa ya
/// actualizado (no muta el que recibe).
///
/// Prender escribe SIEMPRE el id canónico: es el que el backend consulta
/// (`sensor-alarm.service.ts` resuelve el evento a su deviceId canónico antes
/// de mirar el mapa). Apagar, en cambio, borra TODAS las claves bajo las que
/// el device figuraba —canónica y bindings—: si sólo se escribiera la
/// canónica, una entrada legacy quedaría marcada y el sensor volvería a la
/// lista al recargar.
///
/// `level` (CCE#133) viaja con el prendido y sigue la MISMA disciplina que la
/// marca: se manda junto al PUT para que el sensor nazca con un nivel escrito
/// en vez de caer en el default `interior`, que lo dejaría fuera del perímetro
/// sin que nadie lo haya pedido.
Future<Map<String, bool>> writeFiresAlarm(
  ApiService api,
  Device device,
  Map<String, bool> triggers, {
  required bool fires,
  SensorAlarmLevel? level,
}) async {
  final next = Map<String, bool>.from(triggers);
  if (fires) {
    await api.setSensorAlarmTrigger(device.id, true, level: level);
    next[device.id] = true;
  } else {
    for (final key in firingKeys(device, triggers)) {
      await api.setSensorAlarmTrigger(key, false);
      next.remove(key);
    }
    // Sin ninguna clave marcada igual se manda el apagado del id canónico:
    // deja el backend explícitamente en "no dispara" aunque la app haya
    // leído un mapa desactualizado.
    if (firingKeys(device, triggers).isEmpty) {
      await api.setSensorAlarmTrigger(device.id, false);
    }
    next.remove(device.id);
  }
  return next;
}
