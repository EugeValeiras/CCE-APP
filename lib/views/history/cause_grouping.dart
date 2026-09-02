import '../../models/event_record.dart';
import '../../services/devices_service.dart';
import 'event_grouping.dart';

/// AGRUPAMIENTO POR CAUSA (CCE#75).
///
/// [groupEvents] colapsa repeticiones: eventos ADYACENTES del mismo aparato
/// con la misma semántica. Eso achica un run, pero no junta cuatro luces
/// distintas ni tres propiedades distintas — por eso prender el Hall se veía
/// como doce filas a la misma hora. Este módulo agrega la capa de arriba: junta
/// los runs que son EL MISMO HECHO, y se apoya en el de adyacencia en vez de
/// reemplazarlo.
///
/// Hay dos maneras de saber que dos cambios son el mismo hecho:
///
///  1. **La causa**, cuando el backend la manda (CCE-API: `correlationId` +
///     `actor` en el payload de `device:state-changed`). Es la buena: los cinco
///     ecos de un roomcast traen el mismo `correlationId` porque salieron del
///     mismo comando. No hay que adivinar nada.
///  2. **El fallback**, para todo lo anterior a ese cambio —que es TODO el
///     historial ya persistido— y para lo que de verdad pasó solo: mismo
///     aparato, ventana corta, semántica compatible.
///
/// El fallback es una heurística y se mantiene deliberadamente chica: dos
/// comandos distintos al mismo aparato con un segundo de diferencia caerían en
/// la misma ventana, así que el grupo se CORTA cuando la semántica se invierte
/// (encendió → apagó). Un grupo de más esconde un hecho; una fila de más sólo
/// ocupa lugar.

/// Ventana del fallback (y de la absorción del eco hermano). Corta a propósito:
/// es el tiempo en el que los ecos de un mismo comando terminan de llegar.
const Duration kFallbackWindow = Duration(seconds: 2);

/// Corte de un mismo `correlationId`. El id ya identifica la causa; esta
/// ventana sólo evita que dos ráfagas separadas en el tiempo que reusaran un id
/// terminen en la misma fila. Generosa porque el reintento de CCE#74 reenvía
/// con el correlationId del comando original y su eco puede llegar segundos
/// después del primer intento.
const Duration kCauseWindow = Duration(seconds: 60);

/// `correlationId` del evento, si el backend lo mandó. Ausente = pasó solo.
String? eventCorrelationId(EventRecord e) {
  final v = e.payload?['correlationId'];
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// `actor` del evento: quién pidió el comando (`user:app`, `automation:<id>`,
/// `alexa`…). Crudo — la traducción a castellano es cosa de la presentación.
String? eventActor(EventRecord e) {
  final v = e.payload?['actor'];
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Un HECHO del historial: uno o más runs que comparten causa.
///
/// Con [correlationId] el grupo es un hecho PROBADO (el backend dice que estos
/// cambios son el eco de un mismo comando). Sin él es un hecho INFERIDO por la
/// ventana del fallback. La diferencia importa: sólo el primero puede afirmar
/// quién lo hizo.
class CauseGroup {
  CauseGroup({
    required this.runs,
    required this.deviceIds,
    this.correlationId,
    this.actor,
  }) : assert(runs.isNotEmpty);

  /// Runs que componen el hecho, del más reciente al más viejo.
  final List<EventGroup> runs;

  /// Ids canónicos de los aparatos que cambiaron. Es lo que da el «4 luces».
  final Set<String> deviceIds;

  final String? correlationId;
  final String? actor;

  /// Un solo run sin causa: el caso que se ve exactamente como antes.
  factory CauseGroup.single(EventGroup run, DevicesService devices) =>
      CauseGroup(
        runs: [run],
        deviceIds: {canonicalDeviceId(run.latest, devices)},
        correlationId: eventCorrelationId(run.latest),
        actor: eventActor(run.latest),
      );

  EventRecord get latest => runs.first.latest;

  /// Todos los eventos individuales, del más reciente al más viejo. Es lo que
  /// se despliega al tocar la fila.
  List<EventRecord> get events {
    final out = [for (final r in runs) ...r.events];
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  int get eventCount => runs.fold(0, (n, r) => n + r.count);
  int get deviceCount => deviceIds.length;

  /// Vale la pena poder desplegarlo: hay más de un evento adentro.
  bool get expandable => eventCount > 1;

  DateTime get to => runs.first.to;
  DateTime get from =>
      runs.map((r) => r.from).reduce((a, b) => a.isBefore(b) ? a : b);

  /// Identidad estable para recordar el estado expandido mientras la vista
  /// está abierta.
  String get key => latest.id;
}

/// Agrupa por causa los runs que devolvió [groupEvents]. La lista entra y sale
/// del más reciente al más viejo.
List<CauseGroup> groupByCause(
  List<EventGroup> runs,
  DevicesService devices,
) {
  final drafts = <_Draft>[];
  final sinCausa = <EventGroup>[];

  // PASADA 1 — lo que trae causa. Un correlationId es una afirmación del
  // backend, así que manda sobre cualquier heurística de tiempo.
  for (final run in runs) {
    final cid = _runCause(run);
    if (cid == null) {
      sinCausa.add(run);
      continue;
    }
    _Draft? abierto;
    for (final d in drafts) {
      if (d.correlationId != cid) continue;
      if (d.gapTo(run) > kCauseWindow) continue;
      abierto = d;
      break;
    }
    if (abierto != null) {
      abierto.add(run, devices);
    } else {
      drafts.add(_Draft(run, devices, correlationId: cid, actor: _runActor(run)));
    }
  }

  // PASADA 2 — lo que no la trae.
  for (final run in sinCausa) {
    final dev = canonicalDeviceId(run.latest, devices);

    // (a) EL ECO DEL BINDING HERMANO. Un aparato con dos bindings (hue+matter,
    // ewelink+matter) reporta el mismo cambio dos veces, y el registry del
    // backend sólo puede etiquetar el que volvió por el binding que comandó —
    // el hermano sale sin causa aunque su causa exista (límite conocido de
    // CCE#74, documentado en ExpectedEchoRegistry.observe). Acá, del lado de
    // la presentación, se lo absorbe: MISMO aparato que ya está en el grupo,
    // dentro de la ventana corta y sin invertir la semántica. No se le inventa
    // causa a un aparato que no estaba en el grupo.
    _Draft? destino;
    for (final d in drafts) {
      if (d.correlationId == null) continue;
      if (!d.deviceIds.contains(dev)) continue;
      if (d.gapTo(run) > kFallbackWindow) continue;
      if (d.opposes(run)) continue;
      destino = d;
      break;
    }

    // (b) FALLBACK: mismo aparato, ventana corta. Es lo que convierte las tres
    // filas de «Hall 4» (encendido, brillo, temperatura de color) en una.
    if (destino == null) {
      for (final d in drafts) {
        if (d.correlationId != null) continue;
        if (d.deviceIds.length != 1 || !d.deviceIds.contains(dev)) continue;
        if (d.gapTo(run) > kFallbackWindow) continue;
        if (d.opposes(run)) continue;
        destino = d;
        break;
      }
    }

    if (destino != null) {
      destino.add(run, devices);
    } else {
      drafts.add(_Draft(run, devices));
    }
  }

  // El orden de la lista lo fija el evento más reciente de cada hecho: los
  // grupos absorben eventos que estaban salteados, así que hay que reordenar.
  drafts.sort((a, b) => b.to.compareTo(a.to));
  return [for (final d in drafts) d.build()];
}

/// Causa del run: el `correlationId` que comparten sus eventos. Si dos eventos
/// del mismo run vienen de comandos distintos (un drag de brillo son N
/// comandos), no hay una sola causa que contar y se resuelve por fallback.
String? _runCause(EventGroup run) {
  String? cid;
  for (final e in run.events) {
    final c = eventCorrelationId(e);
    if (c == null) continue;
    if (cid != null && cid != c) return null;
    cid = c;
  }
  return cid;
}

String? _runActor(EventGroup run) {
  for (final e in run.events) {
    final a = eventActor(e);
    if (a != null) return a;
  }
  return null;
}

/// Estados booleanos del evento. Son los que NO se pueden colapsar cuando se
/// invierten: encendido/apagado, movimiento/sin movimiento, abierto/cerrado.
Map<String, bool> _flags(EventRecord e) {
  final out = <String, bool>{};
  final state = e.payload?['state'];
  if (state is Map && state['on'] is bool) out['on'] = state['on'] as bool;
  final sensor = e.payload?['sensor'];
  if (sensor is Map) {
    if (sensor['motion'] is bool) out['motion'] = sensor['motion'] as bool;
    if (sensor['contact'] is bool) out['contact'] = sensor['contact'] as bool;
  }
  return out;
}

/// Grupo en construcción.
class _Draft {
  _Draft(
    EventGroup run,
    DevicesService devices, {
    this.correlationId,
    this.actor,
  }) {
    add(run, devices);
  }

  final List<EventGroup> runs = [];
  final Set<String> deviceIds = {};
  final String? correlationId;
  final String? actor;

  late DateTime to;
  late DateTime from;

  void add(EventGroup run, DevicesService devices) {
    runs.add(run);
    deviceIds.add(canonicalDeviceId(run.latest, devices));
    if (runs.length == 1) {
      to = run.to;
      from = run.from;
      return;
    }
    if (run.to.isAfter(to)) to = run.to;
    if (run.from.isBefore(from)) from = run.from;
  }

  /// Distancia entre el run y el intervalo del grupo (cero si se solapan).
  Duration gapTo(EventGroup run) {
    if (run.to.isBefore(from)) return from.difference(run.to);
    if (run.from.isAfter(to)) return run.from.difference(to);
    return Duration.zero;
  }

  /// ¿El run invierte algo que este grupo ya afirma? Encendió y apagó no son
  /// el mismo hecho por más juntos que hayan pasado.
  bool opposes(EventGroup run) {
    final entrante = _flags(run.latest);
    if (entrante.isEmpty) return false;
    for (final r in runs) {
      for (final e in r.events) {
        final propios = _flags(e);
        for (final entry in entrante.entries) {
          final mio = propios[entry.key];
          if (mio != null && mio != entry.value) return true;
        }
      }
    }
    return false;
  }

  CauseGroup build() {
    runs.sort((a, b) => b.to.compareTo(a.to));
    return CauseGroup(
      runs: List.unmodifiable(runs),
      deviceIds: Set.unmodifiable(deviceIds),
      correlationId: correlationId,
      actor: actor,
    );
  }
}
