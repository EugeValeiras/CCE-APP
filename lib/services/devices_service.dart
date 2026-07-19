import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/color_preset.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../models/light_group.dart';
import '../models/room_ref.dart';
import '../models/scene.dart';
import '../models/server_config.dart';
import '../theme/cce_tokens.dart';
import '../utils/light_color.dart';
import 'api_service.dart';
import 'app_messenger.dart';
import 'socket_service.dart';

class DevicesService extends ChangeNotifier {
  final ServerConfig config;
  final ApiService _api;
  final SocketService _socket;

  final Map<String, Device> _byId = {};
  final Map<String, Device> _byBindingId = {};
  FloorPlansData? _floorPlans;
  List<LightGroup> _groups = const [];
  Map<String, String> _lightIcons = const {};
  // Íconos vendoreados de icons0.dev: 'icons0:<prefix>:<name>' -> SVG completo
  // (mismo formato que guarda el dashboard en config.customIcons).
  Map<String, String> _customIcons = const {};
  Map<String, String> _lightNames = const {};
  Map<String, String> _automationNames = const {};
  List<ColorPreset> _colorPresets = const [];
  List<CceScene> _scenes = const [];
  List<HueScene> _hueScenes = const [];
  // Orden unificado de acciones por plano (compartido con el dashboard web):
  // planId -> ['scene:<id>', 'hueScene:<id>', 'group:<id>', ...].
  Map<String, List<String>> _actionOrder = const {};
  bool _loading = false;
  String? _error;

  StreamSubscription? _deviceSub;
  StreamSubscription? _connSub;
  StreamSubscription? _armedSub;
  bool _wasConnected = false;
  bool _alarmArmed = false;

  DevicesService({required this.config, required SocketService socket})
      : _api = ApiService(config),
        _socket = socket {
    _deviceSub = _socket.onDeviceChanged.listen(_applyDeviceEvent);
    _connSub = _socket.onConnectionChanged.listen((connected) {
      // On reconnect, pull fresh state — WS events during the gap are not replayed.
      if (connected && !_wasConnected) {
        debugPrint('[DevicesService] Socket reconectado, refrescando devices');
        refresh();
      }
      _wasConnected = connected;
    });
    // Estado de la alarma en vivo: el header del home colorea el ícono con esto.
    _armedSub = _socket.onArmedChanged.listen((armed) {
      if (_alarmArmed != armed) {
        _alarmArmed = armed;
        notifyListeners();
      }
    });
  }

  /// True si la alarma está armada (seed en [refresh] + push por WebSocket).
  bool get alarmArmed => _alarmArmed;

  SocketService get socket => _socket;

  // Listas visibles: excluyen devices marcados como hidden en backend.
  // _byId sigue con todo para lookups internos (WS, comandos sobre grupos, etc.).
  List<Device> get all => _byId.values.where((d) => !d.hidden).toList();
  // dev_jbl/dev_tv ahora existen en /merged (F13) y entran a _byId para que el
  // historial y los comandos genéricos los resuelvan; se EXCLUYEN de las listas
  // de UI (su control lo renderiza Jbl/TvService), de ahí el !isMediaDevice.
  List<Device> get lights =>
      all.where((d) => d.isLight && !d.isSensorDevice && !d.isThermostat && !d.isMediaDevice).toList();
  List<Device> get sensors =>
      all.where((d) => (d.isSensorDevice || d.isSwitch) && !d.isThermostat && !d.isLock && !d.isMediaDevice && !d.isVacuum).toList();
  List<Device> get thermostats => all.where((d) => d.isThermostat).toList();
  List<Device> get locks => all.where((d) => d.isLock).toList();
  List<Device> get vacuums => all.where((d) => d.isVacuum).toList();
  FloorPlansData? get floorPlans => _floorPlans;
  List<LightGroup> get groups => _groups;
  Map<String, String> get lightIcons => _lightIcons;
  Map<String, String> get customIcons => _customIcons;
  List<ColorPreset> get colorPresets => _colorPresets;
  List<CceScene> get scenes => _scenes;
  List<HueScene> get hueScenes => _hueScenes;
  bool get loading => _loading;
  String? get error => _error;
  Device? byId(String id) => _byId[id];

  String? iconFor(String deviceId) => _lightIcons[deviceId];

  /// User-configured display name if set, otherwise the manufacturer model name.
  String displayName(Device d) {
    final custom = _lightNames[d.id]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return d.name;
  }

  /// Resolves an automation ID to its configured name.
  String automationName(String? id) {
    if (id == null || id.isEmpty) return 'Automatización';
    return _automationNames[id] ?? id;
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final devicesFuture = _api.getDevices();
      final plansFuture = _api.getFloorPlans();
      final configFuture = _api.getConfig();
      // Escenas Hue en paralelo; si el bridge no está configurado o falla,
      // degrada a [] sin romper el refresh.
      final hueScenesFuture = _api.getHueScenes().catchError((Object e) {
        debugPrint('getHueScenes error (degrada a []): $e');
        return <HueScene>[];
      });
      // Estado de alarma en paralelo; si falla mantiene el valor previo.
      final armedFuture = _api.getAlarmState().catchError((Object e) {
        debugPrint('getAlarmState error (mantiene previo): $e');
        return _alarmArmed;
      });
      final devices = await devicesFuture;
      _byId
        ..clear()
        ..addEntries(devices.map((d) => MapEntry(d.id, d)));
      _byBindingId.clear();
      for (final d in devices) {
        for (final bid in d.bindingIds) {
          _byBindingId[bid] = d;
        }
      }
      _floorPlans = await plansFuture;
      final cfg = await configFuture;
      final rawGroups = cfg['lightGroups'];
      _groups = rawGroups is List
          ? rawGroups
              .whereType<Map>()
              .map((g) => LightGroup.fromJson(Map<String, dynamic>.from(g)))
              .toList()
          : const [];
      final rawIcons = cfg['lightIcons'];
      _lightIcons = rawIcons is Map
          ? rawIcons.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {};
      final rawCustom = cfg['customIcons'];
      _customIcons = rawCustom is Map
          ? {
              for (final e in rawCustom.entries)
                if (e.value is Map && (e.value as Map)['svg'] != null)
                  e.key.toString(): (e.value as Map)['svg'].toString()
            }
          : const {};
      final rawNames = cfg['lightNames'];
      _lightNames = rawNames is Map
          ? rawNames.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {};
      final rawAutos = cfg['automations'];
      _automationNames = rawAutos is List
          ? {
              for (final a in rawAutos)
                if (a is Map && a['id'] != null)
                  a['id'].toString(): (a['name'] ?? a['id']).toString()
            }
          : const {};
      final rawPresets = cfg['colorPresets'];
      _colorPresets = rawPresets is List
          ? rawPresets
              .whereType<Map>()
              .map((p) => ColorPreset.fromJson(Map<String, dynamic>.from(p)))
              .toList()
          : const [];
      final rawScenes = cfg['scenes'];
      _scenes = rawScenes is List
          ? rawScenes
              .whereType<Map>()
              .map((s) => CceScene.fromJson(Map<String, dynamic>.from(s)))
              .toList()
          : const [];
      _actionOrder = _parseActionOrder(cfg['actionOrder']);
      _hueScenes = await hueScenesFuture;
      _alarmArmed = await armedFuture;
    } catch (e) {
      _error = 'Error cargando dispositivos';
      debugPrint('DevicesService error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Aviso global de comando fallido (snackbar sin BuildContext, con
  /// anti-spam en [showAppError]). El flujo OK no muestra nada.
  void _notifyCommandError(String name) =>
      showAppError('No se pudo controlar «$name»');

  Future<void> toggleLight(Device d) async {
    // Snapshot COMPLETO del estado previo: DeviceState es inmutable, así el
    // revert restaura exactamente (incluye campos que copyWith(null) no
    // podría limpiar, como colormode). Mismo patrón para bri/color/ct.
    final prev = d.state;
    final next = !prev.on;
    // Optimistic update
    d.state = d.state.copyWith(on: next);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'on': next});
    } catch (e) {
      // Revert on error + aviso
      debugPrint('toggleLight error: $e');
      d.state = prev;
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Simula la pulsación de un botón de un switch/dial → dispara la acción
  /// configurada en el backend. Devuelve false si falló.
  Future<bool> simulateButton(Device d, {required int key, int? outlet}) async {
    try {
      await _api.simulateButton(d.id, key: key, outlet: outlet);
      return true;
    } catch (e) {
      debugPrint('simulateButton error: $e');
      return false;
    }
  }

  // ── Vacuum (Roborock) — verbos de capability vía POST /actions/:verb ──
  // Optimista con revert (mismo patrón que luces/termostato): el estado real
  // llega igual por WS desde Matter, el optimismo solo evita el lag visual.

  /// Revert seguro del optimista: restaura [prev] SOLO si el estado actual
  /// sigue siendo el objeto optimista [applied]. Si en el medio llegó un push
  /// WS (estado más fresco del robot), NO lo pisamos — el timeout del HTTP no
  /// implica que el comando no haya llegado (ventana grande con Matter/sidecar).
  void _revertVacuumIfUntouched(Device d, DeviceState prev, DeviceState applied) {
    if (identical(d.state, applied)) {
      d.state = prev;
      notifyListeners();
    }
  }

  /// Verbo simple de transporte: clean | pause | resume | dock.
  Future<void> vacuumCommand(Device d, String verb) async {
    const optimistic = {
      'clean': 'cleaning',
      'pause': 'paused',
      'resume': 'cleaning',
      'dock': 'returning',
    };
    final prev = d.state;
    final next = optimistic[verb];
    final applied =
        next != null ? d.state.copyWith(vacuumState: next) : d.state;
    if (next != null) {
      d.state = applied;
      notifyListeners();
    }
    try {
      await _api.invokeAction(d.id, verb);
    } catch (e) {
      debugPrint('vacuumCommand($verb) error: $e');
      _revertVacuumIfUntouched(d, prev, applied);
      _notifyCommandError(displayName(d));
    }
  }

  /// Cambia el modo de limpieza (label REAL del robot, ej 'Auto, Vacuum and Mop').
  Future<void> setVacuumCleanMode(Device d, String mode) async {
    final prev = d.state;
    final applied = d.state.copyWith(cleanMode: mode);
    d.state = applied;
    notifyListeners();
    try {
      await _api.invokeAction(d.id, 'setCleanMode', {'mode': mode});
    } catch (e) {
      debugPrint('setVacuumCleanMode error: $e');
      _revertVacuumIfUntouched(d, prev, applied);
      _notifyCommandError(displayName(d));
    }
  }

  /// Limpia habitaciones específicas (segmentIds del sidecar). Devuelve false
  /// si falló para que la pantalla mantenga la selección y avise en contexto.
  Future<bool> cleanVacuumRooms(Device d, List<int> segmentIds) async {
    if (segmentIds.isEmpty) return false;
    final prev = d.state;
    final applied = d.state.copyWith(vacuumState: 'cleaning');
    d.state = applied;
    notifyListeners();
    try {
      await _api.invokeAction(d.id, 'cleanRooms', {'rooms': segmentIds.join(',')});
      return true;
    } catch (e) {
      debugPrint('cleanVacuumRooms error: $e');
      _revertVacuumIfUntouched(d, prev, applied);
      return false;
    }
  }

  /// Potencia de succión (label real del robot, sidecar).
  Future<void> setVacuumFanSpeed(Device d, String level) async {
    final prev = d.state;
    final applied = d.state.copyWith(fanSpeed: level);
    d.state = applied;
    notifyListeners();
    try {
      await _api.invokeAction(d.id, 'setFanSpeed', {'level': level});
    } catch (e) {
      debugPrint('setVacuumFanSpeed error: $e');
      _revertVacuumIfUntouched(d, prev, applied);
      _notifyCommandError(displayName(d));
    }
  }

  /// Brillo, optimista con revert al estado previo si el PUT falla (mismo
  /// patrón que el termostato) + snackbar global.
  Future<void> setBrightness(Device d, int bri) async {
    final clamped = bri.clamp(0, 254);
    final wantOn = clamped > 0;
    final prev = d.state;
    d.state = d.state.copyWith(bri: clamped, on: wantOn);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'bri': clamped, 'on': wantOn});
    } catch (e) {
      debugPrint('setBrightness error: $e');
      d.state = prev;
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Color HS, optimista con revert + snackbar (patrón del termostato). El
  /// snapshot completo restaura también mode/colormode previos (que copyWith
  /// con null no podría limpiar).
  Future<void> setColor(Device d, {required int hue, required int sat}) async {
    final clampedHue = hue.clamp(0, 65535);
    final clampedSat = sat.clamp(0, 254);
    final prev = d.state;
    // colormode: 'hs' explícito: pisa un xy/ct stale para que el tile pinte
    // el color elegido al instante (copyWith con ?? no puede limpiarlo).
    d.state = d.state.copyWith(hue: clampedHue, sat: clampedSat, on: true, mode: 'colour', colormode: 'hs');
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'hue': clampedHue, 'sat': clampedSat, 'on': true});
    } catch (e) {
      debugPrint('setColor error: $e');
      d.state = prev;
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Temperatura de color, optimista con revert + snackbar (ver [setColor]).
  Future<void> setCt(Device d, int ct) async {
    final clamped = ct.clamp(153, 500);
    final prev = d.state;
    // colormode: 'ct' explícito: pisa un xy/hs stale (ver nota en copyWith).
    d.state = d.state.copyWith(ct: clamped, on: true, mode: 'white', colormode: 'ct');
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'ct': clamped, 'on': true});
    } catch (e) {
      debugPrint('setCt error: $e');
      d.state = prev;
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  // ===========================================================================
  // Termostato (Tuya cat 'wk') — optimista con revert, mismo patrón que las luces.
  // ===========================================================================

  /// Redondea [temp] al paso de 0.5 °C y lo clampea al rango [minTemp,maxTemp]
  /// del device (defaults 5..45 si el device no los reporta).
  double _clampTargetTemp(Device d, double temp) {
    final min = d.state.minTemp ?? 5;
    final max = d.state.maxTemp ?? 45;
    final stepped = (temp * 2).round() / 2; // paso 0.5
    return stepped.clamp(min, max).toDouble();
  }

  /// Setpoint del termostato (paso 0.5 °C, clamp [minTemp,maxTemp]). Optimista
  /// con revert al valor previo si el PUT falla.
  Future<void> setTargetTemp(Device d, double temp) async {
    final clamped = _clampTargetTemp(d, temp);
    final prev = d.state.targetTemp;
    if (clamped == prev) return;
    d.state = d.state.copyWith(targetTemp: clamped);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'targetTemp': clamped});
    } catch (e) {
      debugPrint('setTargetTemp error: $e');
      d.state = d.state.copyWith(targetTemp: prev);
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Prende/apaga el termostato (power, DP1). Optimista con revert.
  Future<void> setThermostatPower(Device d, bool on) async {
    final prev = d.state.on;
    if (on == prev) return;
    d.state = d.state.copyWith(on: on);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'on': on});
    } catch (e) {
      debugPrint('setThermostatPower error: $e');
      d.state = d.state.copyWith(on: prev);
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Modo del termostato ('Manual' | 'Program', DP4). Optimista con revert.
  Future<void> setTempMode(Device d, String mode) async {
    final prev = d.state.tempMode;
    if (mode == prev) return;
    d.state = d.state.copyWith(tempMode: mode);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'tempMode': mode});
    } catch (e) {
      debugPrint('setTempMode error: $e');
      d.state = d.state.copyWith(tempMode: prev);
      notifyListeners();
      _notifyCommandError(displayName(d));
    }
  }

  /// Prende/apaga el grupo, optimista luz por luz. Las luces cuyo PUT falló
  /// se revierten al estado previo y se avisa UNA vez con el nombre del grupo.
  Future<void> setGroupOn(LightGroup g, bool on) async {
    final ids = g.lightIds.where((id) => _byId.containsKey(id)).toList();
    final prev = {for (final id in ids) id: _byId[id]!.state};
    for (final id in ids) {
      final d = _byId[id]!;
      d.state = d.state.copyWith(on: on);
    }
    notifyListeners();
    var anyFailed = false;
    for (final id in ids) {
      try {
        await _api.setDeviceState(id, {'on': on});
      } catch (e) {
        debugPrint('setGroupOn error on $id: $e');
        _byId[id]!.state = prev[id]!;
        anyFailed = true;
      }
    }
    if (anyFailed) {
      notifyListeners();
      _notifyCommandError(g.name);
    }
  }

  // ===========================================================================
  // Habitaciones canónicas (RoomRef) + stats — única fuente de verdad.
  // ===========================================================================

  /// Habitaciones derivadas ON-DEMAND del estado actual (sin caché, para que
  /// altas/bajas de devices vía WS muevan '_orphans' y deviceIds al instante).
  /// Triple fallback:
  ///  (1) planos con posiciones → planId = plan.id, hueRoomId = plan.hueRoomId
  ///  (2) groups               → planId = null, hueRoomId = null
  ///  (3) '_orphans'           → planId = null, hueRoomId = null
  List<RoomRef> get rooms {
    final result = <RoomRef>[];
    final assigned = <String>{};

    bool visible(String id) {
      final d = _byId[id];
      return d != null && !d.hidden;
    }

    final fp = _floorPlans;
    if (fp != null) {
      for (final plan in fp.plans) {
        final pos = fp.positions[plan.id];
        if (pos == null || pos.isEmpty) continue;
        final ids = pos.keys.where(visible).toList();
        if (ids.isEmpty) continue;
        assigned.addAll(ids);
        result.add(RoomRef(
          id: plan.id,
          name: plan.name,
          deviceIds: ids,
          planId: plan.id,
          hueRoomId: plan.hueRoomId,
          // Ícono PROPIO de la room (plano), asignado desde el dashboard. Las
          // rooms son los planos, no los grupos: el ícono sale de plan.icon.
          iconName: plan.icon,
        ));
      }
    }

    if (result.isEmpty) {
      for (final g in _groups) {
        final ids = g.lightIds.where(visible).toList();
        if (ids.isEmpty) continue;
        assigned.addAll(ids);
        result.add(RoomRef(
          id: g.id,
          name: g.name,
          deviceIds: ids,
          iconName: g.icon,
        ));
      }
    }

    final orphanIds =
        all.map((d) => d.id).where((id) => !assigned.contains(id)).toList();
    if (orphanIds.isNotEmpty) {
      result.add(RoomRef(
        id: '_orphans',
        name: result.isEmpty ? 'Todos' : 'Sin ubicación',
        deviceIds: orphanIds,
      ));
    }
    return result;
  }

  List<Device> _roomDevices(RoomRef room) =>
      room.deviceIds.map((id) => _byId[id]).whereType<Device>().toList();

  List<Device> _roomLights(RoomRef room) => _roomDevices(room)
      .where((d) => d.isLight && !d.isSensorDevice)
      .toList();

  /// Stats derivadas de una sala (tint, conteos, brillo, chips, último evento).
  /// Las vistas NO recalculan nada de esto por su cuenta.
  RoomStats statsFor(RoomRef room) {
    final devices = _roomDevices(room);
    final lights =
        devices.where((d) => d.isLight && !d.isSensorDevice).toList();
    final onLights = lights.where((d) => d.state.on).toList();

    // Promedio del brillo de las luces ON (0..1); null si no hay luces ON —
    // prohibido dividir por cero / devolver NaN.
    double? avgBrightness;
    if (onLights.isNotEmpty) {
      final sum = onLights.fold<int>(0, (acc, d) => acc + d.state.bri);
      avgBrightness =
          (sum / onLights.length / 254).clamp(0.0, 1.0).toDouble();
    }

    DateTime? latest;
    for (final d in devices) {
      final t = d.lastEventAt;
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }

    return RoomStats(
      lightsOn: onLights.length,
      lightsTotal: lights.length,
      anyOn: onLights.isNotEmpty,
      tint: _tintForOnLights(onLights),
      tintColors: _tintColorsForOnLights(onLights),
      avgBrightness: avgBrightness,
      anyContactOpen:
          devices.any((d) => d.isContactSensor && d.sensor?.contact == true),
      anyMotion:
          devices.any((d) => d.isMotionSensor && d.sensor?.motion == true),
      latestEventAt: latest,
    );
  }

  /// Tint dominante de las luces encendidas que reportan color. La luz
  /// dominante es la de mayor brillo; si las dos más brillantes tienen hues
  /// a ≤90° se promedia circularmente el hue ponderado por brillo (jamás se
  /// promedian complementarios). El tint de color sale SIEMPRE normalizado
  /// por [CceTint.normalize]. Sin luces coloreadas pero con alguna ON en
  /// blanco → el color REAL del CT (cálido/frío) de esas luces, NO un gris
  /// fijo (para 2700K da ámbar; el pastel lo deja amarillo cálido, no blanco).
  /// NOTA: el render aplica CceTint.pastel encima; este tint es el color
  /// semántico, no el pintado.
  Color? _tintForOnLights(List<Device> onLights) {
    final colored = <({double hue, double sat, int bri})>[];
    for (final d in onLights) {
      final r = resolveLightColor(d.state);
      if (r.isWhite) continue;
      colored.add((
        hue: r.hueDeg! % 360.0,
        sat: r.sat01!,
        bri: d.state.bri,
      ));
    }
    if (colored.isEmpty) {
      // Luces ON en modo blanco: usar el blanco cálido/frío REAL del CT.
      for (final d in onLights) {
        final r = resolveLightColor(d.state);
        if (r.isWhite) return r.color;
      }
      return null;
    }

    colored.sort((a, b) => b.bri.compareTo(a.bri));
    final dominant = colored.first;
    var hue = dominant.hue;

    if (colored.length >= 2) {
      var diff = (dominant.hue - colored[1].hue).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff <= 90) {
        // Promedio circular del hue, ponderado por brillo.
        double x = 0, y = 0;
        for (final c in colored) {
          final w = c.bri.clamp(1, 254).toDouble();
          final rad = c.hue * math.pi / 180.0;
          x += math.cos(rad) * w;
          y += math.sin(rad) * w;
        }
        hue = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
      }
    }

    // Saturación de la dominante, atenuada por su brillo real (una luz
    // tenue ya no tiñe como una a tope).
    final briFactor = (dominant.bri / 254).clamp(0.35, 1.0).toDouble();
    final sat = (dominant.sat * briFactor).clamp(0.0, 1.0).toDouble();
    final base =
        HSVColor.fromAHSV(1.0, hue.clamp(0.0, 360.0).toDouble(), sat, 1.0)
            .toColor();
    return CceTint.normalize(base);
  }

  /// Colores de TODAS las luces ON con color (para el gradiente multicolor de
  /// la room card estilo Hue). Conserva el orden de las luces, normaliza cada
  /// color, descarta hues casi-iguales (≤18°) para que el gradiente no sea un
  /// bloque plano, y topea en 5 paradas. Las luces ON en blanco/CT aportan
  /// una parada champagne. [] si no hay ninguna luz ON con color ni CT.
  List<Color> _tintColorsForOnLights(List<Device> onLights) {
    final colors = <Color>[];
    final hues = <double>[];
    Color? whiteColor; // color real del CT de la primera luz blanca ON
    for (final d in onLights) {
      final r = resolveLightColor(d.state);
      if (r.isWhite) {
        whiteColor ??= r.color;
        continue;
      }
      final h = r.hueDeg! % 360.0;
      // Dedupe por cercanía de hue (circular).
      final dup = hues.any((other) {
        var diff = (h - other).abs();
        if (diff > 180) diff = 360 - diff;
        return diff <= 18;
      });
      if (dup) continue;
      hues.add(h);
      colors.add(CceTint.normalize(
        HSVColor.fromAHSV(1.0, h.clamp(0.0, 360.0).toDouble(),
                r.sat01!.clamp(0.0, 1.0).toDouble(), 1.0)
            .toColor(),
      ));
      if (colors.length >= 5) break;
    }
    if (colors.isEmpty && whiteColor != null) {
      return [whiteColor];
    }
    return colors;
  }

  /// Prende/apaga TODAS las luces de la sala (optimista, luz por luz).
  /// Devuelve false si ALGUNA luz falló; el estado optimista de las luces
  /// fallidas se revierte. El catch por luz se mantiene para no abortar la
  /// ráfaga del resto.
  Future<bool> setRoomOn(RoomRef room, bool on) async {
    final lights = _roomLights(room);
    if (lights.isEmpty) return true;
    for (final d in lights) {
      d.state = d.state.copyWith(on: on);
    }
    notifyListeners();
    var allOk = true;
    for (final d in lights) {
      try {
        await _api.setDeviceState(d.id, {'on': on});
      } catch (e) {
        debugPrint('setRoomOn error on ${d.id}: $e');
        d.state = d.state.copyWith(on: !on);
        allOk = false;
      }
    }
    if (!allOk) {
      notifyListeners();
      _notifyCommandError(room.name);
    }
    return allOk;
  }

  /// Brillo de toda la sala: [value] 0..1 aplicado a cada luz ENCENDIDA.
  Future<void> setRoomBrightness(RoomRef room, double value) async {
    final target = (value * 254).round().clamp(1, 254);
    final onLights = _roomLights(room).where((d) => d.state.on).toList();
    for (final d in onLights) {
      await setBrightness(d, target);
    }
  }

  // ===========================================================================
  // Escenas (Hue nativas + config CCE)
  // ===========================================================================

  /// Escenas Hue de la sala (vía hueRoomId del plano); [] si no hay link.
  List<HueScene> hueScenesForRoom(RoomRef room) {
    final roomId = room.hueRoomId;
    if (roomId == null) return const [];
    return _hueScenes.where((s) => s.roomId == roomId).toList();
  }

  /// Escenas CCE de la sala — REGLA CONGELADA: solo planId == room.planId
  /// (estricto). Las escenas globales (planId == null) aparecen únicamente
  /// en "Toda la casa" (ScenesSection con room == null).
  List<CceScene> scenesForRoom(RoomRef room) {
    final planId = room.planId;
    if (planId == null) return const [];
    return _scenes.where((s) => s.planId == planId).toList();
  }

  static Map<String, List<String>> _parseActionOrder(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        e.key.toString(): e.value is List
            ? (e.value as List).map((x) => x.toString()).toList()
            : <String>[],
    };
  }

  /// Orden unificado del plano (keys 'scene:<id>' / 'hueScene:<id>' / ...);
  /// [] si el plano no tiene orden guardado.
  List<String> actionOrderFor(String planId) =>
      _actionOrder[planId] ?? const [];

  /// Keys de las escenas visibles del plano, en el orden por defecto
  /// (Hue primero, luego CCE) — para completar buckets incompletos.
  List<String> _visibleSceneKeys(String planId) {
    final keys = <String>[];
    RoomRef? room;
    for (final r in rooms) {
      if (r.planId == planId) {
        room = r;
        break;
      }
    }
    if (room != null) {
      for (final s in hueScenesForRoom(room)) {
        keys.add('hueScene:${s.id}');
      }
    }
    for (final s in _scenes.where((s) => s.planId == planId)) {
      keys.add('scene:${s.id}');
    }
    return keys;
  }

  /// Reordena una escena dentro del orden unificado del plano — MISMO
  /// mecanismo y semántica que el drag&drop del dashboard web (PUT
  /// /config/action-order). Merge defensivo: lee la config fresca y solo
  /// modifica el bucket de [planId], preservando los demás planos y las
  /// keys de grupos/automatizaciones que la app no muestra.
  Future<bool> reorderSceneKey(
      String planId, String fromKey, String toKey) async {
    if (fromKey == toKey) return true;
    try {
      final cfg = await _api.getConfig();
      final order = Map<String, List<String>>.from(
          _parseActionOrder(cfg['actionOrder']));
      final bucket = List<String>.from(order[planId] ?? const []);
      // Completar con las escenas visibles que falten (al final, en el
      // orden por defecto) para que ambos índices existan.
      for (final k in _visibleSceneKeys(planId)) {
        if (!bucket.contains(k)) bucket.add(k);
      }
      final from = bucket.indexOf(fromKey);
      final to = bucket.indexOf(toKey);
      if (from == -1 || to == -1) return false;
      // Misma semántica que el dashboard: remove en from, insert en to
      // (índices calculados sobre la lista original).
      bucket.removeAt(from);
      bucket.insert(to, fromKey);
      order[planId] = bucket;
      await _api.setActionOrder(order);
      _actionOrder = order;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('reorderSceneKey error: $e');
      return false;
    }
  }

  /// Ejecuta una escena CCE client-side: optimista + N× setDeviceState.
  Future<void> applyScene(CceScene s) async {
    for (final l in s.lights) {
      final d = _byId[l.lightId];
      if (d == null) continue;
      d.state = d.state.copyWith(
        on: l.on,
        bri: l.on ? l.bri : null,
        hue: l.on ? l.hue : null,
        sat: l.on ? l.sat : null,
        ct: l.on ? l.ct : null,
        // colormode derivado del payload de la escena: sin esto, una luz Hue
        // en modo 'xy'/'ct' seguiría pintando el color stale y el update
        // optimista quedaría invisible (ver nota en DeviceState.copyWith).
        // null conserva el modo previo (correcto si la escena no toca color).
        colormode: !l.on
            ? null
            : (l.hue != null && l.sat != null
                ? 'hs'
                : (l.ct != null ? 'ct' : null)),
      );
    }
    notifyListeners();
    for (final l in s.lights) {
      await _api.setDeviceState(l.lightId, l.toStateBody());
    }
  }

  /// Recall de escena Hue nativa, optimista CON REVERT: marca [s] activa y el
  /// resto del room inactivas; si el POST falla, restaura y relanza. El estado
  /// real de las luces llega solo por WS device:state-changed.
  Future<void> recallHueScene(HueScene s) async {
    final prev = <HueScene, bool>{
      for (final sc in _hueScenes) sc: sc.isActive,
    };
    for (final sc in _hueScenes) {
      if (sc.roomId != null && sc.roomId == s.roomId) sc.isActive = false;
    }
    s.isActive = true;
    notifyListeners();
    try {
      await _api.recallHueScene(s.id, smart: s.isSmart);
    } catch (e) {
      prev.forEach((sc, wasActive) => sc.isActive = wasActive);
      s.isActive = prev[s] ?? false;
      notifyListeners();
      rethrow;
    }
  }

  void _applyDeviceEvent(DeviceStateEvent ev) {
    final d = _byId[ev.deviceId] ?? _byBindingId[ev.deviceId];
    if (d == null) {
      debugPrint('[DevicesService] WS event for unknown device: ${ev.deviceId} (state=${ev.state != null ? 'yes' : 'no'}, sensor=${ev.sensor != null ? 'yes' : 'no'})');
      return;
    }
    bool changed = false;
    if (ev.state != null && ev.state!.isNotEmpty) {
      final partial = DeviceState.fromJson({
        'on': ev.state!['on'] ?? d.state.on,
        'bri': ev.state!['bri'] ?? d.state.bri,
        'hue': ev.state!['hue'] ?? d.state.hue,
        'sat': ev.state!['sat'] ?? d.state.sat,
        'ct': ev.state!['ct'] ?? d.state.ct,
        'reachable': ev.state!['reachable'] ?? d.state.reachable,
        'mode': ev.state!['mode'] ?? d.state.mode,
        'colormode': ev.state!['colormode'] ?? d.state.colormode,
        'xy': ev.state!['xy'] ?? d.state.xy,
        // Termostato: sin estos campos los updates en vivo del setpoint /
        // temp actual se perderían (el WS state se re-arma campo por campo).
        'currentTemp': ev.state!['currentTemp'] ?? d.state.currentTemp,
        'targetTemp': ev.state!['targetTemp'] ?? d.state.targetTemp,
        'tempMode': ev.state!['tempMode'] ?? d.state.tempMode,
        'systemMode': ev.state!['systemMode'] ?? d.state.systemMode,
        'minTemp': ev.state!['minTemp'] ?? d.state.minTemp,
        'maxTemp': ev.state!['maxTemp'] ?? d.state.maxTemp,
        // Vacuum (Roborock): ídem — el push de Matter trae vacuumState/battery
        // y sin estos campos el estado en vivo del robot se pisaría con null.
        'vacuumState': ev.state!['vacuumState'] ?? d.state.vacuumState,
        'cleanMode': ev.state!['cleanMode'] ?? d.state.cleanMode,
        'cleanModes': ev.state!['cleanModes'] ?? d.state.cleanModes,
        'battery': ev.state!['battery'] ?? d.state.battery,
        'fanSpeed': ev.state!['fanSpeed'] ?? d.state.fanSpeed,
        'fanSpeeds': ev.state!['fanSpeeds'] ?? d.state.fanSpeeds,
        // OJO: rooms NO va acá — el fallback serían objetos VacuumRoom (no JSON
        // crudo) y fromJson los descartaría. Se preserva vía copyWith abajo.
        'rooms': ev.state!['rooms'],
      });
      d.state = (partial.rooms == null && d.state.rooms != null)
          ? partial.copyWith(rooms: d.state.rooms)
          : partial;
      changed = true;
    }
    if (ev.sensor != null && ev.sensor!.isNotEmpty) {
      // Merge: don't lose temp/hum when we only get motion, and vice-versa.
      final current = d.sensor;
      d.sensor = DeviceSensor(
        temperature: (ev.sensor!['temperature'] as num?)?.toDouble() ?? current?.temperature,
        humidity: (ev.sensor!['humidity'] as num?)?.toDouble() ?? current?.humidity,
        battery: (ev.sensor!['battery'] as String?) ?? current?.battery,
        motion: (ev.sensor!['motion'] as bool?) ?? current?.motion,
        contact: (ev.sensor!['contact'] as bool?) ?? current?.contact,
        brightness: (ev.sensor!['brightness'] as String?) ?? current?.brightness,
      );
      changed = true;
    }
    if (!changed) return;
    d.lastEventAt = DateTime.now();
    debugPrint('[DevicesService] Applied: ${d.id} on=${d.state.on} bri=${d.state.bri} motion=${d.sensor?.motion} contact=${d.sensor?.contact}');
    notifyListeners();
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _connSub?.cancel();
    _armedSub?.cancel();
    super.dispose();
  }
}
