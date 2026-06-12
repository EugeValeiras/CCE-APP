import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/automation.dart';
import '../models/light_group.dart';
import '../models/server_config.dart';
import '../utils/time_format.dart';
import 'devices_service.dart';
import 'socket_service.dart';

enum SaveStatus { ok, conflict, error }

class SaveResult {
  const SaveResult(this.status, {this.message, this.serverCopy});

  final SaveStatus status;

  /// Para SnackBar en error.
  final String? message;

  /// En conflict: versión fresca del server, alimenta el sheet
  /// Sobrescribir/Descartar.
  final Map<String, dynamic>? serverCopy;

  bool get ok => status == SaveStatus.ok;
}

class RunResult {
  const RunResult({required this.ok, this.degraded = false, this.warning});

  final bool ok;

  /// true si alguna acción no se pudo replicar client-side (jbl,
  /// notificación, acción avanzada desconocida).
  final bool degraded;
  final String? warning;
}

/// Servicio de automatizaciones contra `GET/PUT /config/automations`.
///
/// La API NO tiene endpoints granulares ni versionado: toda mutación es
/// GET fresco → merge por id → PUT del array COMPLETO, serializada por una
/// cola de escritura única ([_enqueue]) para que dos toggles rápidos o
/// toggle+undo no interleen GET/PUT y resuciten items borrados.
class AutomationsService extends ChangeNotifier {
  AutomationsService({required this.config, required this.devices}) {
    _liveSub = devices.socket.onLiveEvent.listen(_onLiveEvent);
    refresh();
    _bootstrapLastExecuted();
  }

  final ServerConfig config;
  final DevicesService devices;

  static const _eq = DeepCollectionEquality();
  static const _timeout = Duration(seconds: 8);

  List<Automation> _automations = [];
  bool _loading = false;
  String? _error;

  final Map<String, DateTime> _lastExecuted = {};
  Map<String, dynamic>? _deletedSnapshot;

  // Supresión de eco propio: todo PUT dispara config:changed del server.
  int _ownWritesInFlight = 0;
  DateTime? _lastPutAt;
  List<Map<String, dynamic>>? _lastPutBody;

  // Cola de escritura única (mutex): un solo GET→merge→PUT in-flight.
  Future<void> _tail = Future.value();

  // Probe del endpoint server-side de ejecución manual (una vez por sesión).
  bool _runEndpointMissing = false;
  bool _runEndpointAvailable = false;

  StreamSubscription<LiveEvent>? _liveSub;

  List<Automation> get automations => _automations;
  bool get loading => _loading;
  String? get error => _error;
  bool get canUndoDelete => _deletedSnapshot != null;

  DateTime? lastExecuted(String automationId) => _lastExecuted[automationId];

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  // ==========================================================================
  // Lectura
  // ==========================================================================

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final fresh = await _fetchRaw();
      // Doble check de eco: si el GET coincide con el último body PUTeado
      // por nosotros, el estado local ya es ese (optimista) — no notificar.
      final isOwnEcho =
          _lastPutBody != null && _eq.equals(fresh, _lastPutBody);
      _applyRaw(fresh, notify: !isOwnEcho);
    } catch (e) {
      _error = 'Error cargando automatizaciones';
      debugPrint('AutomationsService refresh error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _applyRaw(List<Map<String, dynamic>> list, {required bool notify}) {
    _automations = [for (final m in list) Automation.fromJson(m)];
    if (notify) notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _fetchRaw() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config/automations'))
        .timeout(_timeout);
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    if (data is! List) return [];
    return [
      for (final a in data)
        if (a is Map) Map<String, dynamic>.from(a),
    ];
  }

  Future<void> _putRaw(List<Map<String, dynamic>> array) async {
    _ownWritesInFlight++;
    try {
      final resp = await http
          .put(
            Uri.parse('${config.baseUrl}/config/automations'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(array),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception('Error ${resp.statusCode}');
      }
      _lastPutBody = [
        for (final m in array)
          Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map),
      ];
      _lastPutAt = DateTime.now();
    } finally {
      _ownWritesInFlight--;
    }
  }

  /// Cola de escritura: encadena [op] al final de [_tail]; los errores se
  /// propagan SOLO al caller, la cola sigue viva.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ==========================================================================
  // Escritura (todas encoladas, todas GET fresco → merge → PUT)
  // ==========================================================================

  /// Guarda [a] (update o create). Con [force] saltea el chequeo de
  /// conflicto (botón "Sobrescribir" del sheet).
  Future<SaveResult> save(Automation a, {bool force = false}) {
    return _enqueue(() async {
      try {
        final fresh = await _fetchRaw();
        final idx =
            fresh.indexWhere((m) => (m['id'] ?? '').toString() == a.id);
        if (!force && idx >= 0 && !_eq.equals(fresh[idx], a.original)) {
          return SaveResult(SaveStatus.conflict, serverCopy: fresh[idx]);
        }
        final body = a.toJson();
        final merged = [...fresh];
        if (idx >= 0) {
          merged[idx] = body;
        } else {
          merged.add(body);
        }
        await _putRaw(merged);
        _applyRaw(merged, notify: true);
        return const SaveResult(SaveStatus.ok);
      } catch (e) {
        debugPrint('AutomationsService save error: $e');
        return const SaveResult(SaveStatus.error,
            message: 'No se pudo guardar la automatización');
      }
    });
  }

  /// Habilita/deshabilita: optimista local + GET→flip→PUT encolado.
  Future<SaveResult> setEnabled(String id, bool enabled) {
    final local = _automations.firstWhereOrNull((a) => a.id == id);
    final prev = local?.enabled;
    if (local != null) {
      local.enabled = enabled;
      notifyListeners();
    }
    return _enqueue(() async {
      try {
        final fresh = await _fetchRaw();
        final idx = fresh.indexWhere((m) => (m['id'] ?? '').toString() == id);
        if (idx < 0) {
          return const SaveResult(SaveStatus.error,
              message: 'La automatización ya no existe en el servidor');
        }
        fresh[idx]['enabled'] = enabled;
        await _putRaw(fresh);
        return const SaveResult(SaveStatus.ok);
      } catch (e) {
        debugPrint('AutomationsService setEnabled error: $e');
        if (local != null && prev != null) {
          local.enabled = prev;
          notifyListeners();
        }
        return const SaveResult(SaveStatus.error,
            message: 'No se pudo cambiar el estado');
      }
    });
  }

  /// Borra con snapshot para [undoDelete] (SnackBar DESHACER).
  Future<SaveResult> delete(String id) {
    final local = _automations.firstWhereOrNull((a) => a.id == id);
    _deletedSnapshot = local?.toJson();
    // Optimista: desaparece de la lista ya.
    _automations = [for (final a in _automations) if (a.id != id) a];
    notifyListeners();
    return _enqueue(() async {
      try {
        final fresh = await _fetchRaw();
        final merged = [
          for (final m in fresh)
            if ((m['id'] ?? '').toString() != id) m,
        ];
        await _putRaw(merged);
        return const SaveResult(SaveStatus.ok);
      } catch (e) {
        debugPrint('AutomationsService delete error: $e');
        await refresh();
        return const SaveResult(SaveStatus.error,
            message: 'No se pudo eliminar');
      }
    });
  }

  /// Re-inserta la última borrada (GET+PUT, encolado).
  Future<void> undoDelete() {
    final snap = _deletedSnapshot;
    _deletedSnapshot = null;
    if (snap == null) return Future.value();
    return _enqueue(() async {
      try {
        final fresh = await _fetchRaw();
        final id = (snap['id'] ?? '').toString();
        if (!fresh.any((m) => (m['id'] ?? '').toString() == id)) {
          fresh.add(snap);
        }
        await _putRaw(fresh);
        _applyRaw(fresh, notify: true);
      } catch (e) {
        debugPrint('AutomationsService undoDelete error: $e');
      }
    });
  }

  // ==========================================================================
  // Eventos live
  // ==========================================================================

  void _onLiveEvent(LiveEvent ev) {
    if (ev.eventName == 'automation:executed') {
      // El payload es {automationId, trigger, sensorId, timestamp} y NO
      // trae name (gateway verificado).
      final id = ev.payload['automationId']?.toString();
      if (id != null && id.isNotEmpty) {
        _lastExecuted[id] = DateTime.now();
        notifyListeners();
      }
      return;
    }
    if (ev.eventName == 'config:changed') {
      // Supresión de eco propio: nuestro PUT dispara config:changed y un
      // refresh acá pisaría el estado optimista / el editor recién guardado.
      if (_ownWritesInFlight > 0) return;
      final lastPut = _lastPutAt;
      if (lastPut != null &&
          DateTime.now().difference(lastPut) <
              const Duration(milliseconds: 1500)) {
        return;
      }
      refresh();
    }
  }

  /// Bootstrap de "Última vez": eventos automation:executed históricos.
  Future<void> _bootstrapLastExecuted() async {
    try {
      final resp = await http
          .get(Uri.parse(
              '${config.baseUrl}/events?eventName=automation:executed&limit=100'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final items = data is Map ? data['items'] : null;
      if (items is! List) return;
      var changed = false;
      for (final it in items) {
        if (it is! Map) continue;
        final payload = it['payload'];
        final id =
            payload is Map ? payload['automationId']?.toString() : null;
        final time = it['time']?.toString();
        if (id == null || id.isEmpty || time == null) continue;
        // ISO UTC sin 'Z' del server: SIEMPRE vía TimeFormat.parseEventTime.
        final ts = TimeFormat.parseEventTime(time);
        final existing = _lastExecuted[id];
        if (existing == null || ts.isAfter(existing)) {
          _lastExecuted[id] = ts;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('AutomationsService bootstrapLastExecuted error: $e');
    }
  }

  // ==========================================================================
  // "Probar" honesto — matriz de degradación completa
  // ==========================================================================

  /// Warning previo a una ejecución client-side (pill ámbar ANTES de
  /// ejecutar). null = nada degrada o la ejecución será server-side.
  String? clientReplayWarning(Automation a) {
    if (_runEndpointAvailable) return null;
    if (a.trigger.type == 'sensor' &&
        a.trigger.sensorTriggers.any((t) => t.sensorField == 'lastKey')) {
      // simulate-button ejecuta server-side completo.
      return null;
    }
    if (a.source != 'custom') return null;
    final warnings = <String>{};
    for (final act in a.actions) {
      switch (act.kind) {
        case AutomationActionKind.notification:
          warnings.add('La prueba no envía notificaciones');
        case AutomationActionKind.jbl:
          warnings.add('La prueba no controla el parlante');
        case AutomationActionKind.advanced:
          if (act.on != 'bri_up' && act.on != 'bri_down') {
            warnings.add('Hay acciones que la prueba no puede ejecutar');
          }
        default:
          break;
      }
    }
    if (warnings.isEmpty) return null;
    return warnings.join(' · ');
  }

  /// Ejecuta [a] AHORA, con la matriz de degradación documentada:
  /// 1) probe del endpoint server-side (`POST /automations/:id/run`, cacheo
  ///    del 404 por sesión); 2) trigger de botón → simulate-button
  ///    (server-side completo); 3) replay client-side por tipo de acción.
  /// Nunca ejecuta parcialmente en silencio: lo no replicable acumula
  /// warning y marca degraded.
  Future<RunResult> runNow(Automation a) async {
    // 1. Probe del endpoint dedicado (una vez por sesión).
    if (!_runEndpointMissing) {
      try {
        final resp = await http
            .post(Uri.parse('${config.baseUrl}/automations/${a.id}/run'))
            .timeout(_timeout);
        if (resp.statusCode == 404) {
          _runEndpointMissing = true;
        } else if (resp.statusCode >= 200 && resp.statusCode < 300) {
          _runEndpointAvailable = true;
          return const RunResult(ok: true);
        } else {
          return RunResult(
              ok: false, warning: 'El servidor respondió ${resp.statusCode}');
        }
      } on TimeoutException {
        return const RunResult(
            ok: false, warning: 'El servidor no respondió');
      } catch (_) {
        if (!_runEndpointMissing) {
          return const RunResult(
              ok: false, warning: 'Sin conexión con el servidor');
        }
      }
    }

    // 2. Trigger de botón → simulate-button (server-side completa).
    if (a.trigger.type == 'sensor') {
      final button = a.trigger.sensorTriggers
          .firstWhereOrNull((t) => t.sensorField == 'lastKey');
      if (button != null && button.sensorId.isNotEmpty) {
        try {
          final resp = await http
              .post(
                Uri.parse(
                    '${config.baseUrl}/devices/${Uri.encodeComponent(button.sensorId)}/simulate-button'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'key': button.sensorValue,
                  if (button.sensorOutlet != null)
                    'outlet': button.sensorOutlet,
                }),
              )
              .timeout(_timeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            return const RunResult(ok: true);
          }
          return RunResult(
              ok: false,
              warning: 'No se pudo simular el botón (${resp.statusCode})');
        } catch (e) {
          return const RunResult(
              ok: false, warning: 'No se pudo simular el botón');
        }
      }
    }

    // 3. Replay client-side.
    final warnings = <String>{};
    var degraded = false;
    try {
      switch (a.source) {
        case 'scene':
          final scene =
              devices.scenes.firstWhereOrNull((s) => s.id == a.sourceId);
          if (scene == null) {
            return const RunResult(
                ok: false, warning: 'No se encontró la escena');
          }
          for (final l in scene.lights) {
            await _putState(l.lightId, l.toStateBody());
          }
        case 'hueScene':
          final sid = a.sourceId;
          if (sid == null) {
            return const RunResult(
                ok: false, warning: 'La automatización no tiene escena');
          }
          final resp = await http
              .post(
                Uri.parse(
                    '${config.baseUrl}/hue/scenes/${Uri.encodeComponent(sid)}/recall'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'smart': a.sourceSmart}),
              )
              .timeout(_timeout);
          if (resp.statusCode != 200 && resp.statusCode != 201) {
            return RunResult(
                ok: false,
                warning: 'No se pudo activar la escena (${resp.statusCode})');
          }
        case 'group':
          final sid = a.sourceId;
          if (sid == null) {
            return const RunResult(
                ok: false, warning: 'La automatización no tiene grupo');
          }
          await _applyGroup(sid, a.sourceAction);
        default: // custom
          for (final act in a.actions) {
            switch (act.kind) {
              case AutomationActionKind.notification:
                warnings.add('La prueba no envía notificaciones');
                degraded = true;
              case AutomationActionKind.jbl:
                // ApiService (legible) no expone rutas JBL: degradar
                // explícito, jamás saltear en silencio.
                warnings.add('La prueba no controla el parlante');
                degraded = true;
              case AutomationActionKind.alarm:
                await _applyAlarm(act.alarmAction);
              case AutomationActionKind.group:
                final gid = act.groupId;
                if (gid == null) {
                  warnings.add('Hay un grupo sin configurar');
                  degraded = true;
                } else {
                  await _applyGroup(gid, act.groupAction);
                }
              case AutomationActionKind.light:
                await _applyLightAction(act);
              case AutomationActionKind.advanced:
                if (act.on == 'bri_up' || act.on == 'bri_down') {
                  await _applyBriDelta(act);
                } else {
                  warnings.add('Hay acciones que la prueba no puede ejecutar');
                  degraded = true;
                }
            }
          }
      }
    } catch (e) {
      debugPrint('AutomationsService runNow replay error: $e');
      return const RunResult(
          ok: false, warning: 'Falló la ejecución de prueba');
    }
    return RunResult(
      ok: true,
      degraded: degraded,
      warning: warnings.isEmpty ? null : warnings.join(' · '),
    );
  }

  Future<void> _putState(String deviceId, Map<String, dynamic> state) async {
    await http
        .put(
          Uri.parse(
              '${config.baseUrl}/devices/${Uri.encodeComponent(deviceId)}/state'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(state),
        )
        .timeout(_timeout);
  }

  Future<void> _applyLightAction(AutomationAction act) async {
    final on = act.on;
    if (on == 'toggle') {
      final current = devices.byId(act.lightId)?.state.on ?? false;
      await _putState(act.lightId, {'on': !current});
      return;
    }
    final wantOn = on == true;
    final body = <String, dynamic>{'on': wantOn};
    if (wantOn) {
      if (act.bri != null) body['bri'] = act.bri!.clamp(1, 254);
      if (act.hue != null) body['hue'] = act.hue!.clamp(0, 65535);
      if (act.sat != null) body['sat'] = act.sat!.clamp(0, 254);
      if (act.ct != null) body['ct'] = act.ct;
    }
    await _putState(act.lightId, body);
  }

  Future<void> _applyBriDelta(AutomationAction act) async {
    final current = devices.byId(act.lightId)?.state.bri ?? 128;
    final delta = act.briDelta;
    final next =
        act.on == 'bri_up' ? current + delta : current - delta;
    if (act.on == 'bri_down' && next < 1) {
      // Semántica del executor: bri_down que cae bajo 1 apaga.
      await _putState(act.lightId, {'on': false});
      return;
    }
    await _putState(act.lightId, {'on': true, 'bri': next.clamp(1, 254)});
  }

  Future<void> _applyAlarm(String action) async {
    bool target;
    if (action == 'arm') {
      target = true;
    } else if (action == 'disarm') {
      target = false;
    } else {
      // toggle: GET previo y PUT del inverso.
      final resp = await http
          .get(Uri.parse('${config.baseUrl}/config/alarm-armed'))
          .timeout(_timeout);
      final current =
          resp.statusCode == 200 && jsonDecode(resp.body)['armed'] == true;
      target = !current;
    }
    await http
        .put(
          Uri.parse('${config.baseUrl}/config/alarm-armed'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'armed': target}),
        )
        .timeout(_timeout);
  }

  Future<List<LightGroup>> _fetchGroups() async {
    try {
      final resp = await http
          .get(Uri.parse('${config.baseUrl}/config/groups'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List) {
          return [
            for (final g in data)
              if (g is Map) LightGroup.fromJson(Map<String, dynamic>.from(g)),
          ];
        }
      }
    } catch (e) {
      debugPrint('AutomationsService _fetchGroups error: $e');
    }
    // Fallback: grupos ya cargados en DevicesService.
    return devices.groups;
  }

  Future<void> _applyGroup(String groupId, String action) async {
    final groups = await _fetchGroups();
    final group = groups.firstWhereOrNull((g) => g.id == groupId);
    if (group == null) throw Exception('Grupo $groupId no encontrado');
    bool on;
    if (action == 'toggle') {
      // toggle = si alguna está prendida, apaga todas.
      final anyOn = group.lightIds
          .any((id) => devices.byId(id)?.state.on == true);
      on = !anyOn;
    } else {
      on = action != 'off';
    }
    for (final id in group.lightIds) {
      await _putState(id, {'on': on});
    }
  }
}
