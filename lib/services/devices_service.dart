import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/color_preset.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../models/light_group.dart';
import '../models/server_config.dart';
import 'api_service.dart';
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
  Map<String, String> _lightNames = const {};
  Map<String, String> _automationNames = const {};
  List<ColorPreset> _colorPresets = const [];
  bool _loading = false;
  String? _error;

  StreamSubscription? _deviceSub;
  StreamSubscription? _connSub;
  bool _wasConnected = false;

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
  }

  SocketService get socket => _socket;

  // Listas visibles: excluyen devices marcados como hidden en backend.
  // _byId sigue con todo para lookups internos (WS, comandos sobre grupos, etc.).
  List<Device> get all => _byId.values.where((d) => !d.hidden).toList();
  List<Device> get lights => all.where((d) => d.isLight && !d.isSensorDevice).toList();
  List<Device> get sensors => all.where((d) => d.isSensorDevice).toList();
  FloorPlansData? get floorPlans => _floorPlans;
  List<LightGroup> get groups => _groups;
  Map<String, String> get lightIcons => _lightIcons;
  List<ColorPreset> get colorPresets => _colorPresets;
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
    } catch (e) {
      _error = 'Error cargando dispositivos';
      debugPrint('DevicesService error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> toggleLight(Device d) async {
    final next = !d.state.on;
    // Optimistic update
    d.state = d.state.copyWith(on: next);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'on': next});
    } catch (e) {
      // Revert on error
      d.state = d.state.copyWith(on: !next);
      notifyListeners();
    }
  }

  Future<void> setBrightness(Device d, int bri) async {
    final clamped = bri.clamp(0, 254);
    final wantOn = clamped > 0;
    d.state = d.state.copyWith(bri: clamped, on: wantOn);
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'bri': clamped, 'on': wantOn});
    } catch (e) {
      debugPrint('setBrightness error: $e');
    }
  }

  Future<void> setColor(Device d, {required int hue, required int sat}) async {
    final clampedHue = hue.clamp(0, 65535);
    final clampedSat = sat.clamp(0, 254);
    d.state = d.state.copyWith(hue: clampedHue, sat: clampedSat, on: true, mode: 'colour');
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'hue': clampedHue, 'sat': clampedSat, 'on': true});
    } catch (e) {
      debugPrint('setColor error: $e');
    }
  }

  Future<void> setCt(Device d, int ct) async {
    final clamped = ct.clamp(153, 500);
    d.state = d.state.copyWith(ct: clamped, on: true, mode: 'white');
    notifyListeners();
    try {
      await _api.setDeviceState(d.id, {'ct': clamped, 'on': true});
    } catch (e) {
      debugPrint('setCt error: $e');
    }
  }

  Future<void> setGroupOn(LightGroup g, bool on) async {
    final ids = g.lightIds.where((id) => _byId.containsKey(id)).toList();
    for (final id in ids) {
      final d = _byId[id]!;
      d.state = d.state.copyWith(on: on);
    }
    notifyListeners();
    for (final id in ids) {
      try {
        await _api.setDeviceState(id, {'on': on});
      } catch (e) {
        debugPrint('setGroupOn error on $id: $e');
      }
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
      });
      d.state = partial;
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
    super.dispose();
  }
}
