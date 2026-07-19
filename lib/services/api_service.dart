import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';
import '../models/device.dart';
import '../models/jbl_status.dart';
import '../models/tv_status.dart';
import '../models/ezviz_lock.dart';
import '../models/event_record.dart';
import '../models/floor_plan.dart';
import '../models/scene.dart';

class ApiService {
  final ServerConfig config;

  ApiService(this.config);

  Future<List<Device>> getDevices() async {
    final response = await http
        .get(Uri.parse('${config.baseUrl}/devices/merged'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('Error ${response.statusCode}');
    final data = jsonDecode(response.body);
    final list = data is List ? data : (data['devices'] as List? ?? []);
    return list.map((e) => Device.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> setDeviceState(String deviceId, Map<String, dynamic> state) async {
    await http
        .put(
          Uri.parse('${config.baseUrl}/devices/${Uri.encodeComponent(deviceId)}/state'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode(state),
        )
        .timeout(const Duration(seconds: 5));
  }

  /// Invoca una acción de capability sobre un device (POST
  /// /devices/:id/actions/:verb) — el mismo endpoint que usa el Dashboard.
  /// clean/pause/resume/dock van sin args; setCleanMode {mode},
  /// cleanRooms {rooms: '7,3'}, setFanSpeed {level}. Lanza Exception con el
  /// mensaje semántico del backend si la acción falla (≠2xx o success:false).
  Future<void> invokeAction(String deviceId, String verb,
      [Map<String, dynamic>? args]) async {
    final response = await http
        .post(
          Uri.parse(
              '${config.baseUrl}/devices/${Uri.encodeComponent(deviceId)}/actions/${Uri.encodeComponent(verb)}'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode(args ?? const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 10));
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {/* body no-JSON: lo cubre el status */}
    final ok = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body?['success'] != false;
    if (!ok) {
      final msg = body?['error'] ?? body?['message'] ?? 'HTTP ${response.statusCode}';
      throw Exception('$verb: $msg');
    }
  }

  /// Simula la pulsación de un botón de un switch/dial (POST
  /// /devices/:id/simulate-button) → dispara la acción configurada en el
  /// backend. key: 0=click, 1=doble, 2=long; outlet = botón (0-based).
  Future<void> simulateButton(String deviceId,
      {required int key, int? outlet}) async {
    await http
        .post(
          Uri.parse(
              '${config.baseUrl}/devices/${Uri.encodeComponent(deviceId)}/simulate-button'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({
            'key': key,
            if (outlet != null) 'outlet': outlet,
          }),
        )
        .timeout(const Duration(seconds: 6));
  }

  Future<EventsPage> getEvents({
    String? eventName,
    String? channel,
    String? globalId,
    int limit = 100,
    String? cursor,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (eventName != null) query['eventName'] = eventName;
    if (channel != null) query['channel'] = channel;
    if (globalId != null) query['globalId'] = globalId;
    if (cursor != null) query['cursor'] = cursor;
    final uri = Uri.parse('${config.baseUrl}/events').replace(queryParameters: query);
    final resp = await http.get(uri, headers: ServerConfig.tokenHeaders).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    return EventsPage.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
  }

  Future<Map<String, dynamic>> getConfig() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);
  }

  /// Persiste el orden de acciones por plano (mismo mecanismo que el
  /// dashboard web): Record completo planId -> keys tipadas
  /// ('scene:<id>', 'hueScene:<id>', 'group:<id>', 'automation:<id>').
  /// SIEMPRE mandar el record entero — el backend lo reemplaza completo.
  Future<void> setActionOrder(Map<String, List<String>> order) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/config/action-order'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode(order),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Error ${resp.statusCode}');
    }
  }

  Future<FloorPlansData> getFloorPlans() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config/floor-plans'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = resp.statusCode == 200 ? jsonDecode(resp.body) : {};
    final plans = (data['plans'] as List? ?? [])
        .map((p) => FloorPlan.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    final activePlanId = data['activePlanId'] as String?;

    final posResp = await http
        .get(Uri.parse('${config.baseUrl}/config/positions'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final posData = posResp.statusCode == 200 ? jsonDecode(posResp.body) : {};
    final positions = <String, Map<String, LightPosition>>{};
    if (posData is Map) {
      posData.forEach((planId, devicesMap) {
        if (devicesMap is Map) {
          final inner = <String, LightPosition>{};
          devicesMap.forEach((did, xy) {
            if (xy is Map) inner[did.toString()] = LightPosition.fromJson(Map<String, dynamic>.from(xy));
          });
          positions[planId.toString()] = inner;
        }
      });
    }
    // Posiciones de los dispositivos dedicados (TV / JBL): una posición ÚNICA
    // por plano, {planId: {x, y}}. Mismo estilo defensivo que /config/positions:
    // si el endpoint falla / no responde 200, el mapa queda vacío y el plano
    // simplemente no muestra ese marker.
    final jblPositions = await _fetchDevicePositions('/config/jbl-positions');
    final tvPositions =
        await _fetchDevicePositions('/config/samsung-tv-positions');

    return FloorPlansData(
      plans: plans,
      activePlanId: activePlanId,
      positions: positions,
      jblPositions: jblPositions,
      tvPositions: tvPositions,
    );
  }

  /// GET de un mapa {planId: {x, y}} (posición única por plano) para un
  /// dispositivo dedicado (TV / JBL). Defensivo: timeout igual al de los planos
  /// (5s) y, ante cualquier fallo (status != 200, JSON inválido, red caída),
  /// devuelve un mapa vacío en lugar de tirar.
  Future<Map<String, LightPosition>> _fetchDevicePositions(String path) async {
    final out = <String, LightPosition>{};
    try {
      final resp = await http
          .get(Uri.parse('${config.baseUrl}$path'), headers: ServerConfig.tokenHeaders)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return out;
      final data = jsonDecode(resp.body);
      if (data is Map) {
        data.forEach((planId, xy) {
          if (xy is Map) {
            out[planId.toString()] =
                LightPosition.fromJson(Map<String, dynamic>.from(xy));
          }
        });
      }
    } catch (e) {
      debugPrint('[FloorPlan] $path no disponible: $e');
    }
    return out;
  }

  /// Escenas de config CCE (GET /config/scenes).
  Future<List<CceScene>> getScenes() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config/scenes'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((s) => CceScene.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  /// Todas las escenas nativas del bridge Hue (GET /hue/scenes).
  Future<List<HueScene>> getHueScenes() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/hue/scenes'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    return _parseHueScenes(resp.body);
  }

  /// Escenas Hue de un room (GET /hue/rooms/{roomId}/scenes).
  Future<List<HueScene>> getHueRoomScenes(String roomId) async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/hue/rooms/${Uri.encodeComponent(roomId)}/scenes'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    return _parseHueScenes(resp.body);
  }

  List<HueScene> _parseHueScenes(String body) {
    final data = jsonDecode(body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((s) => HueScene.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  /// Activa una escena Hue (POST /hue/scenes/{id}/recall).
  /// Lanza en 400 ("Hue no está configurado") y 502.
  Future<void> recallHueScene(String sceneId, {required bool smart}) async {
    final resp = await http
        .post(
          Uri.parse(
              '${config.baseUrl}/hue/scenes/${Uri.encodeComponent(sceneId)}/recall'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'smart': smart}),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      String msg = 'Error ${resp.statusCode}';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) msg = data['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<bool> getAlarmState() async {
    final response = await http
        .get(Uri.parse('${config.baseUrl}/config/alarm-armed'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['armed'] == true;
    }
    throw Exception('Error ${response.statusCode}');
  }

  Future<bool> setAlarmArmed(bool armed) async {
    final response = await http
        .put(
          Uri.parse('${config.baseUrl}/config/alarm-armed'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'armed': armed}),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['armed'] == true;
    }
    throw Exception('Error ${response.statusCode}');
  }

  Future<void> registerDeviceToken(String token, {String? deviceName}) async {
    await http
        .post(
          Uri.parse('${config.baseUrl}/apns/register'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({
            'deviceToken': token,
            'deviceName': deviceName,
          }),
        )
        .timeout(const Duration(seconds: 5));
  }

  Future<void> ackAlarm(String alarmId) async {
    if (alarmId.isEmpty) return;
    await http
        .post(Uri.parse('${config.baseUrl}/apns/ack/$alarmId'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
  }

  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('${config.baseUrl}/config/alarm-armed'), headers: ServerConfig.tokenHeaders)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── JBL Soundbar ───────────────────────────────────────────────────────────
  // El soundbar NO emite por socket: el estado se obtiene por polling de
  // getJblStatus. GET /jbl/status NUNCA falla por barra inalcanzable (devuelve
  // 200 con online:false); el resto de los comandos SÍ fallan (502) ante barra
  // inalcanzable y devuelven un {error} semántico que parseamos como en
  // recallHueScene.

  Future<JblStatus> getJblStatus() async {
    // Timeout 8s: el server hace SSDP discovery (throttle 30s) antes de
    // responder offline; 5s daría timeouts espurios.
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/jbl/status'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return JblStatus.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  Future<List<JblRadio>> getJblRadios() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/jbl/radios'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    final list = data is List ? data : (data is Map ? data['radios'] : null);
    if (list is! List) return const [];
    final radios = <JblRadio>[];
    for (final it in list) {
      if (it is String) {
        radios.add(JblRadio(name: it));
      } else if (it is Map) {
        radios.add(JblRadio.fromJson(Map<String, dynamic>.from(it)));
      }
    }
    return radios;
  }

  Future<int> setJblVolume(int volume) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/volume'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'volume': volume}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['volume'] as num).toInt();
  }

  Future<int> jblVolumeUp({int? step}) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/jbl/volume/up'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({if (step != null) 'step': step}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['volume'] as num).toInt();
  }

  Future<int> jblVolumeDown({int? step}) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/jbl/volume/down'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({if (step != null) 'step': step}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['volume'] as num).toInt();
  }

  Future<bool> setJblMute(bool muted) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/mute'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'muted': muted}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['muted'] as bool;
  }

  Future<bool> toggleJblMute() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/mute/toggle'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['muted'] as bool;
  }

  /// "Night listening" (Personal Listening Mode). Devuelve el estado resultante.
  Future<bool> setJblNightMode(bool on) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/night'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'on': on}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['nightMode'] as bool;
  }

  Future<bool> toggleJblNightMode() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/night/toggle'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['nightMode'] as bool;
  }

  /// Envía una tecla del remote (allowlist server-side). El backend responde
  /// 200 con { ok } incluso si la barra está offline/rechaza (NUNCA 5xx por
  /// barra inalcanzable). Devuelve `ok == true` si la barra aceptó.
  Future<bool> jblSendRemoteKey(String id) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/jbl/remote'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'key': id}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['ok'] == true;
  }

  Future<void> jblPowerToggle() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/power/toggle'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    _jblOk(resp);
  }

  Future<String> setJblPower(bool on, {bool resume = true}) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/power'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'on': on, 'resume': resume}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['power'] ?? '').toString();
  }

  Future<String> playJblRadio({String? name}) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/jbl/radio/play'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({if (name != null) 'name': name}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['name'] ?? '').toString();
  }

  Future<String> saveJblRadio() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/radio/save'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['name'] ?? '').toString();
  }

  Future<void> deleteJblRadio(String name) async {
    final resp = await http
        .delete(Uri.parse('${config.baseUrl}/jbl/radios/${Uri.encodeComponent(name)}'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    _jblOk(resp);
  }

  Future<String> getJblConfig() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/jbl/config'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return (data is Map ? data['ip'] ?? '' : '').toString();
  }

  Future<String> setJblIp(String ip) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/config'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'ip': ip}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['ip'] ?? '').toString();
  }

  // ── Samsung TV ─────────────────────────────────────────────────────────────
  // Mismo patrón que el soundbar: el TV NO emite por socket → estado por polling
  // de getTvStatus. GET /tv/status NUNCA falla por TV inalcanzable (devuelve 200
  // con online:false); el resto de los comandos SÍ fallan (502) ante TV
  // inalcanzable y devuelven un {error} semántico que parseamos como en
  // recallHueScene / los comandos JBL.

  Future<TvStatus> getTvStatus() async {
    // Timeout 8s: igual que getJblStatus, el server puede hacer discovery /
    // probing del transporte antes de responder offline; 5s daría timeouts
    // espurios.
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/tv/status'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return TvStatus.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  Future<String> setTvPower(bool on) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/power'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'on': on}),
        )
        .timeout(const Duration(seconds: 6));
    final data = _tvOk(resp);
    return (data['power'] ?? '').toString();
  }

  Future<void> toggleTvPower() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/power/toggle'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 6));
    _tvOk(resp);
  }

  Future<int> setTvVolume(int volume) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/volume'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'volume': volume}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return (data['volume'] as num?)?.toInt() ?? volume;
  }

  Future<int?> tvVolumeUp() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/volume/up'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return (data['volume'] as num?)?.toInt();
  }

  Future<int?> tvVolumeDown() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/volume/down'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return (data['volume'] as num?)?.toInt();
  }

  Future<bool> setTvMute(bool muted) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/mute'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'muted': muted}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['muted'] == true;
  }

  Future<bool> toggleTvMute() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/mute/toggle'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['muted'] == true;
  }

  Future<String?> setTvChannel(String channel) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/channel'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'channel': channel}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['channel']?.toString();
  }

  Future<String?> tvChannelUp() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/channel/up'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['channel']?.toString();
  }

  Future<String?> tvChannelDown() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/channel/down'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['channel']?.toString();
  }

  Future<String?> setTvInput(String source) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/input'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'source': source}),
        )
        .timeout(const Duration(seconds: 6));
    final data = _tvOk(resp);
    return data['input']?.toString();
  }

  Future<List<TvInput>> getTvInputs() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/tv/inputs'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvInput.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Envía una tecla del remote (allowlist server-side: up/down/left/right/ok/
  /// back/home/menu/exit/power/volumeUp/volumeDown/mute/channelUp/channelDown/
  /// hdmi/play/pause/stop/digit0..digit9). El backend responde con
  /// {ok,id,via?,error?} y decide el transporte (cloud vs Tizen local).
  /// Devuelve `ok == true` si el TV aceptó.
  Future<bool> sendTvKey(String id) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/tv/remote'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'key': id}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['ok'] == true;
  }

  Future<List<TvRemoteKey>> getTvRemoteKeys() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/tv/remote/keys'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvRemoteKey.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Comando de reproducción (action: play|pause|stop|fastForward|rewind).
  Future<String?> tvPlayback(String action) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/playback'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'action': action}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['playback']?.toString();
  }

  Future<void> tvTrackNext() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/track/next'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    _tvOk(resp);
  }

  Future<void> tvTrackPrev() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/track/prev'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    _tvOk(resp);
  }

  Future<String?> setTvPictureMode(String mode) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/picture-mode'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'mode': mode}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['pictureMode']?.toString();
  }

  Future<String?> setTvSoundMode(String mode) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/tv/sound-mode'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'mode': mode}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _tvOk(resp);
    return data['soundMode']?.toString();
  }

  /// Modos disponibles del TV (GET /tv/modes) → {picture:[...], sound:[...]}.
  /// Devuelve el Map crudo; el caller decide cómo consumirlo.
  Future<Map<String, dynamic>> getTvModes() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/tv/modes'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  /// Lanza una app por su appId (POST /tv/app/launch {appId}).
  Future<bool> launchTvApp(String appId) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/tv/app/launch'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'appId': appId}),
        )
        .timeout(const Duration(seconds: 6));
    final data = _tvOk(resp);
    // El backend responde {success, appId} (no 'ok'); aceptamos cualquiera de
    // los dos como señal de éxito y solo fallamos ante un false explícito.
    return data['success'] != false && data['ok'] != false;
  }

  Future<List<TvApp>> getTvApps() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/tv/apps'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvApp.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Apps INSTALADAS sondeadas en el TV (GET /tv/apps/installed →
  /// { apps: [ { appId, label, brand } ] }). El backend NUNCA tira por TV
  /// inalcanzable: devuelve la última lista cacheada, o {apps:[]} si no hay
  /// nada. Acá tampoco propagamos errores: ante cualquier fallo (red/API down/
  /// timeout/JSON inesperado) devolvemos [] para que la grilla muestre el
  /// estado "vacío" sin romper. Timeout 8s: el sondeo del TV puede tardar más
  /// que un comando simple (igual criterio que getTvStatus).
  Future<List<TvInstalledApp>> getInstalledTvApps() async {
    try {
      final resp = await http
          .get(Uri.parse('${config.baseUrl}/tv/apps/installed'), headers: ServerConfig.tokenHeaders)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body);
      // Contrato: { apps: [...] }. Toleramos también una List cruda por las
      // dudas; cualquier otra forma ⇒ lista vacía.
      final list = data is Map ? data['apps'] : data;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => TvInstalledApp.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // NUNCA tira: la grilla cae al estado vacío.
      return const [];
    }
  }

  /// Activa el modo ambiente del TV (POST /tv/ambient/on).
  Future<void> tvAmbientOn() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/tv/ambient/on'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 6));
    _tvOk(resp);
  }

  /// Valida la respuesta de un comando TV (acepta 200 y 201). Ante fallo parsea
  /// el {error} semántico del body (502/400/404), igual que _jblOk /
  /// recallHueScene. Devuelve el body decodificado como Map.
  Map<String, dynamic> _tvOk(http.Response resp) {
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      String msg = 'Error ${resp.statusCode}';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) msg = data['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
    final data = jsonDecode(resp.body);
    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  /// Valida la respuesta de un comando JBL (acepta 200 y 201). Ante fallo
  /// parsea el {error} semántico del body (502/400/404), igual que
  /// recallHueScene. Devuelve el body decodificado como Map.
  Map<String, dynamic> _jblOk(http.Response resp) {
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      String msg = 'Error ${resp.statusCode}';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) msg = data['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
    final data = jsonDecode(resp.body);
    return data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
  }

  // ── Cerradura EZVIZ ──────────────────────────────────────────────────────
  // Provider ezviz (API privada; user/pass en el .env del backend). El serial
  // crudo es el deviceSerial (Device.ezvizSerial lo deriva del bindingId
  // `ezviz_<serial>`), que es lo que esperan las rutas /ezviz/devices/:serial.
  // Mismo estilo que JBL/TV: status por polling/one-shot al abrir la pantalla.
  //
  //   GET  /ezviz/devices/:serial/status -> EzvizLockStatus
  //   GET  /ezviz/devices/:serial/events -> EzvizLockEvent[]
  //   POST /ezviz/devices/:serial/unlock -> EzvizUnlockResponse  (body {confirm:true})
  //
  // unlock() es SECURITY-SENSITIVE: siempre POST, nunca idempotente, requiere
  // {confirm:true}; el backend loguea cada apertura. Si el modelo no admite
  // apertura remota el controller responde 501 → lo mapeamos a supported:false
  // (en vez de tirar), espejo del catchError(501) del dashboard.

  /// Estado vivo de la cerradura (online/battery/locked). Tira ante status != 200
  /// (la pantalla cae al estado del merged device / muestra el error).
  Future<EzvizLockStatus> getLockStatus(String serial) async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/ezviz/devices/${Uri.encodeComponent(serial)}/status'), headers: ServerConfig.tokenHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return EzvizLockStatus.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  /// Historial de eventos (aperturas, timbre, intentos). Defensivo como
  /// getInstalledTvApps: ante cualquier fallo devuelve [] para que la lista caiga
  /// al estado vacío sin romper la pantalla.
  Future<List<EzvizLockEvent>> getLockEvents(String serial, {int pageSize = 20}) async {
    try {
      final uri = Uri.parse(
              '${config.baseUrl}/ezviz/devices/${Uri.encodeComponent(serial)}/events')
          .replace(queryParameters: {'pageSize': pageSize.toString()});
      final resp = await http.get(uri, headers: ServerConfig.tokenHeaders).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body);
      // Contrato: List cruda; toleramos también { events: [...] } por las dudas.
      final list = data is List ? data : (data is Map ? data['events'] : null);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => EzvizLockEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Abre la cerradura remotamente (POST /unlock {confirm:true}). Acepta 200/201.
  /// 501 (modelo sin apertura remota) NO tira: devuelve supported:false con el
  /// motivo del backend. Cualquier otro fallo parsea el {error} semántico y tira
  /// (igual que _jblOk / _tvOk).
  Future<EzvizUnlockResponse> unlock(String serial) async {
    final resp = await http
        .post(
          Uri.parse(
              '${config.baseUrl}/ezviz/devices/${Uri.encodeComponent(serial)}/unlock'),
          headers: {'Content-Type': 'application/json', ...ServerConfig.tokenHeaders},
          body: jsonEncode({'confirm': true}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 501) {
      String reason = 'No soportado por el modelo de cerradura';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) reason = data['error'].toString();
      } catch (_) {}
      return EzvizUnlockResponse(success: false, supported: false, reason: reason);
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      String msg = 'Error ${resp.statusCode}';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) msg = data['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
    final data = jsonDecode(resp.body);
    return EzvizUnlockResponse.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }
}
