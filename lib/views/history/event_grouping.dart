import '../../models/device.dart';
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

/// Agrupa runs ADYACENTES sobre la lista YA filtrada (recomputar al cambiar
/// el filtro). Reglas de colapso:
///
/// | Caso                              | Colapsar | Gap máx |
/// |-----------------------------------|----------|---------|
/// | `motion:true` repetido            | sí       | 10 min  |
/// | `temperature`/`humidity` mismo dev| sí       | 30 min  |
/// | solo `bri` (drag)                 | sí       | 60 s    |
/// | `lastKey` misma key               | sí       | 5 s     |
/// | `on` true/false alternado         | no       | —       |
/// | `contact`                         | nunca    | —       |
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
        return _RunKey(
          kind: 'motion:$motion',
          deviceId: deviceId,
          collapsible: motion,
          maxGap: const Duration(minutes: 10),
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
      if (sensor['temperature'] != null) {
        return _RunKey(
          kind: 'temperature',
          deviceId: deviceId,
          collapsible: true,
          maxGap: const Duration(minutes: 30),
        );
      }
      if (sensor['humidity'] != null) {
        return _RunKey(
          kind: 'humidity',
          deviceId: deviceId,
          collapsible: true,
          maxGap: const Duration(minutes: 30),
        );
      }
    }

    if (state is Map) {
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
    }

    return _RunKey(
      kind: 'state:other',
      deviceId: deviceId,
      collapsible: false,
    );
  }
}
