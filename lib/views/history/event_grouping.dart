import '../../models/device.dart';
import 'numeric_readings.dart';
import '../../models/event_record.dart';
import '../../services/devices_service.dart';

/// Run de eventos adyacentes con la misma clave (mismo dispositivo + misma
/// semántica). `events.first` es siempre el más reciente (la lista llega
/// ordenada descendente del server y los live se insertan en índice 0).
class EventGroup {
  EventGroup(this.events) : assert(events.isNotEmpty);

  final List<EventRecord> events;

  EventRecord get latest => events.first;
  int get count => events.length;

  /// Timestamp del evento más viejo del run.
  DateTime get from => events.last.timestamp;

  /// Timestamp del evento más reciente del run.
  DateTime get to => events.first.timestamp;
}

/// Device ID crudo del payload (deviceId | lightId | globalId).
String rawDeviceId(EventRecord e) =>
    (e.payload?['deviceId'] ?? e.payload?['lightId'] ?? e.globalId ?? '')
        .toString();

/// Resuelve un ID (canónico o binding) a su [Device].
Device? resolveDeviceId(String id, DevicesService devices) {
  if (id.isEmpty) return null;
  final direct = devices.byId(id);
  if (direct != null) return direct;
  for (final d in devices.all) {
    if (d.bindingIds.contains(id)) return d;
  }
  return null;
}

/// Resuelve el dispositivo de un evento (byId + barrido de bindingIds).
Device? resolveDevice(EventRecord e, DevicesService devices) =>
    resolveDeviceId(rawDeviceId(e), devices);

/// ID canónico (`dev_*`) del dispositivo del evento; si no se puede resolver,
/// devuelve el crudo (eventos consecutivos del mismo aparato pueden alternar
/// deviceId mergeado vs bindingId — por eso se normaliza ANTES de comparar).
String canonicalDeviceId(EventRecord e, DevicesService devices) =>
    resolveDevice(e, devices)?.id ?? rawDeviceId(e);

/// Actividad del robot en un evento de estado, o null si el evento no es
/// telemetría del robot (o trae además un hecho propio, como `on`).
String? _vacuumActivity(EventRecord e) {
  if (e.eventName != 'device:state-changed' && e.eventName != 'light:changed') {
    return null;
  }
  final state = e.payload?['state'];
  if (state is! Map) return null;
  if (state['on'] != null || state['bri'] != null) return null;
  final act = state['vacuumActivity'] ?? state['vacuumState'];
  return act?.toString();
}

/// Acuse de un comando que el backend confirmó: el hecho ya está en el
/// cambio de estado que lo sigue. Sólo el fallo (timeout, error) es noticia.
bool isCommandEcho(EventRecord e) {
  if (e.eventName != 'device:command-result') return false;
  final status = (e.payload?['status'] ?? '').toString();
  return status.isEmpty || status == 'confirmed';
}

/// Saca el ECO de la lista: la telemetría repetida del robot y los acuses de
/// comando confirmados.
///
/// El robot, mientras carga, re-emite su estado entero cada ~20 s con la
/// misma actividad, intercalado con los eventos de los demás aparatos, así
/// que el colapso por adyacencia no alcanza (6 de cada 10 filas del historial
/// eran "cargando"). Sobrevive sólo el evento en el que la actividad CAMBIA
/// respecto del anterior del mismo dispositivo — eso es el hecho ("volvió a
/// la base"); lo demás es un latido.
///
/// [items] viene descendente (más nuevo primero); se compara cada evento con
/// el siguiente (más viejo) del mismo dispositivo. El más viejo de la lista
/// no tiene con qué compararse y se conserva.
List<EventRecord> stripRepeatedTelemetry(
  List<EventRecord> items,
  DevicesService devices,
) {
  final out = <EventRecord>[];
  // Última actividad vista por dispositivo, recorriendo de viejo a nuevo.
  final lastActivity = <String, String>{};
  for (var i = items.length - 1; i >= 0; i--) {
    final e = items[i];
    if (isCommandEcho(e)) continue;
    final act = _vacuumActivity(e);
    if (act == null) {
      out.add(e);
      continue;
    }
    final id = canonicalDeviceId(e, devices);
    if (lastActivity[id] == act) continue; // latido: misma actividad.
    lastActivity[id] = act;
    out.add(e);
  }
  return out.reversed.toList();
}

/// Agrupa runs ADYACENTES sobre la lista YA filtrada (recomputar al cambiar
/// el filtro). Reglas de colapso:
///
/// | Caso                              | Colapsar | Gap máx |
/// |-----------------------------------|----------|---------|
/// | `motion:true` repetido            | sí       | 10 min  |
/// | `motion:false` repetido           | sí       | 2 min   |
/// | `temperature`/`humidity` mismo dev| sí       | 30 min  |
/// | solo `bri` (drag)                 | sí       | 60 s    |
/// | `lastKey` misma key               | sí       | 5 s     |
/// | robot, misma actividad            | sí       | 60 min  |
/// | otro estado sin frase propia      | sí       | 30 min  |
/// | `on` true/false alternado         | no       | —       |
/// | `contact`                         | nunca    | —       |
///
/// El robot re-emite su estado entero cada ~20 s mientras carga: sin colapso,
/// seis de cada diez filas del historial eran la misma telemetría.
List<EventGroup> groupEvents(
  List<EventRecord> filtered,
  DevicesService devices,
) {
  final groups = <EventGroup>[];
  List<EventRecord>? current;
  _RunKey? currentKey;

  for (final e in filtered) {
    final key = _RunKey.of(e, devices);
    if (current != null &&
        currentKey != null &&
        key.collapsible &&
        key.sameRun(currentKey)) {
      final maxGap = key.maxGap;
      // La lista viene descendente: el gap es prev (más nuevo) − actual.
      final gap = current.last.timestamp.difference(e.timestamp);
      if (maxGap != null && !gap.isNegative && gap <= maxGap) {
        current.add(e);
        continue;
      }
    }
    current = [e];
    currentKey = key;
    groups.add(EventGroup(current));
  }
  return groups;
}

/// Clave de run: (eventName normalizado, device.id canónico, key dominante).
/// Key dominante — sensor: contact > motion > lastKey > temperature >
/// humidity; state: on > bri.
class _RunKey {
  const _RunKey({
    required this.kind,
    required this.deviceId,
    required this.collapsible,
    this.maxGap,
  });

  final String kind;
  final String deviceId;
  final bool collapsible;
  final Duration? maxGap;

  bool sameRun(_RunKey other) =>
      kind == other.kind && deviceId == other.deviceId;

  static _RunKey of(EventRecord e, DevicesService devices) {
    final deviceId = canonicalDeviceId(e, devices);
    // Normalización: device:state-changed y light:changed son el mismo canal.
    final isStateEvent = e.eventName == 'device:state-changed' ||
        e.eventName == 'light:changed';
    if (!isStateEvent) {
      return _RunKey(kind: e.eventName, deviceId: deviceId, collapsible: false);
    }

    final p = e.payload ?? const <String, dynamic>{};
    final sensor = p['sensor'];
    final state = p['state'];

    if (sensor is Map && sensor.isNotEmpty) {
      if (sensor['contact'] != null) {
        // Seguridad: contact NUNCA se colapsa.
        return _RunKey(
          kind: 'contact:${sensor['contact']}',
          deviceId: deviceId,
          collapsible: false,
        );
      }
      if (sensor['motion'] != null) {
        final motion = sensor['motion'] == true;
        // motion:true repetido = alguien sigue ahí (10 min). motion:false
        // se emite dos veces seguidas (una pelada y otra con batería/luz):
        // el mismo hecho, colapsado en una ventana corta.
        return _RunKey(
          kind: 'motion:$motion',
          deviceId: deviceId,
          collapsible: true,
          maxGap: motion
              ? const Duration(minutes: 10)
              : const Duration(minutes: 2),
        );
      }
      if (sensor['lastKey'] != null) {
        return _RunKey(
          kind: 'key:${sensor['lastKey']}:${sensor['outlet'] ?? ''}',
          deviceId: deviceId,
          collapsible: true,
          maxGap: const Duration(seconds: 5),
        );
      }
      // Lecturas numéricas (temperatura, humedad, luz): una corrida por la
      // primera lectura presente, con 30 min de gap. La lista es LA tabla del
      // historial (numeric_readings.dart), la misma que las dibuja (CCE#112).
      for (final key in numericReadingKeys) {
        if (sensor[key] != null) {
          return _RunKey(
            kind: key,
            deviceId: deviceId,
            collapsible: true,
            maxGap: const Duration(minutes: 30),
          );
        }
      }
    }

    if (state is Map) {
      // Robot: un run por actividad ("cargando" × 53 es UNA fila; pasar a
      // "limpiando" abre otra). La clave lleva la actividad para que el
      // cambio real corte el run.
      final activity = state['vacuumActivity'] ?? state['vacuumState'];
      if (activity != null) {
        return _RunKey(
          kind: 'vacuum:$activity',
          deviceId: deviceId,
          collapsible: true,
          maxGap: const Duration(minutes: 60),
        );
      }
      if (state['on'] != null) {
        // on true/false alternado: no colapsar (la clave incluye el valor
        // igual, por las dudas de runs idénticos).
        return _RunKey(
          kind: 'on:${state['on']}',
          deviceId: deviceId,
          collapsible: false,
        );
      }
      if (state['bri'] != null) {
        // Drag de brillo: colapsar y mostrar solo el valor final.
        return _RunKey(
          kind: 'bri',
          deviceId: deviceId,
          collapsible: true,
          maxGap: const Duration(seconds: 60),
        );
      }
      if (state['reachable'] != null && state.length == 1) {
        // Cae/vuelve la conexión: cada transición es un hecho propio.
        return _RunKey(
          kind: 'reachable:${state['reachable']}',
          deviceId: deviceId,
          collapsible: false,
        );
      }
    }

    // Telemetría sin frase propia (volumen, potencia, modo…): consecutivos
    // del mismo aparato en una sola fila.
    return _RunKey(
      kind: 'state:other',
      deviceId: deviceId,
      collapsible: true,
      maxGap: const Duration(minutes: 30),
    );
  }
}
