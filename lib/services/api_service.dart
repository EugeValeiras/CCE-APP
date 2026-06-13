import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';
import '../models/device.dart';
import '../models/jbl_status.dart';
import '../models/event_record.dart';
import '../models/floor_plan.dart';
import '../models/scene.dart';

class ApiService {
  final ServerConfig config;

  ApiService(this.config);

  Future<List<Device>> getDevices() async {
    final response = await http
        .get(Uri.parse('${config.baseUrl}/devices/merged'))
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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(state),
        )
        .timeout(const Duration(seconds: 5));
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
          headers: {'Content-Type': 'application/json'},
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
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    return EventsPage.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
  }

  Future<Map<String, dynamic>> getConfig() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config'))
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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(order),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Error ${resp.statusCode}');
    }
  }

  Future<FloorPlansData> getFloorPlans() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config/floor-plans'))
        .timeout(const Duration(seconds: 5));
    final data = resp.statusCode == 200 ? jsonDecode(resp.body) : {};
    final plans = (data['plans'] as List? ?? [])
        .map((p) => FloorPlan.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    final activePlanId = data['activePlanId'] as String?;

    final posResp = await http
        .get(Uri.parse('${config.baseUrl}/config/positions'))
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
    return FloorPlansData(plans: plans, activePlanId: activePlanId, positions: positions);
  }

  /// Escenas de config CCE (GET /config/scenes).
  Future<List<CceScene>> getScenes() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/config/scenes'))
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
        .get(Uri.parse('${config.baseUrl}/hue/scenes'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    return _parseHueScenes(resp.body);
  }

  /// Escenas Hue de un room (GET /hue/rooms/{roomId}/scenes).
  Future<List<HueScene>> getHueRoomScenes(String roomId) async {
    final resp = await http
        .get(Uri.parse(
            '${config.baseUrl}/hue/rooms/${Uri.encodeComponent(roomId)}/scenes'))
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
          headers: {'Content-Type': 'application/json'},
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
        .get(Uri.parse('${config.baseUrl}/config/alarm-armed'))
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
          headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
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
        .post(Uri.parse('${config.baseUrl}/apns/ack/$alarmId'))
        .timeout(const Duration(seconds: 5));
  }

  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('${config.baseUrl}/config/alarm-armed'))
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
        .get(Uri.parse('${config.baseUrl}/jbl/status'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return JblStatus.fromJson(
        data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map));
  }

  Future<List<JblRadio>> getJblRadios() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/jbl/radios'))
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
          headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'muted': muted}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['muted'] as bool;
  }

  Future<bool> toggleJblMute() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/mute/toggle'))
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['muted'] as bool;
  }

  /// Envía una tecla del remote (allowlist server-side). El backend responde
  /// 200 con { ok } incluso si la barra está offline/rechaza (NUNCA 5xx por
  /// barra inalcanzable). Devuelve `ok == true` si la barra aceptó.
  Future<bool> jblSendRemoteKey(String id) async {
    final resp = await http
        .post(
          Uri.parse('${config.baseUrl}/jbl/remote'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'key': id}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return data['ok'] == true;
  }

  Future<void> jblPowerToggle() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/power/toggle'))
        .timeout(const Duration(seconds: 5));
    _jblOk(resp);
  }

  Future<String> setJblPower(bool on, {bool resume = true}) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/power'),
          headers: {'Content-Type': 'application/json'},
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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({if (name != null) 'name': name}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['name'] ?? '').toString();
  }

  Future<String> saveJblRadio() async {
    final resp = await http
        .post(Uri.parse('${config.baseUrl}/jbl/radio/save'))
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['name'] ?? '').toString();
  }

  Future<void> deleteJblRadio(String name) async {
    final resp = await http
        .delete(Uri.parse(
            '${config.baseUrl}/jbl/radios/${Uri.encodeComponent(name)}'))
        .timeout(const Duration(seconds: 5));
    _jblOk(resp);
  }

  Future<String> getJblConfig() async {
    final resp = await http
        .get(Uri.parse('${config.baseUrl}/jbl/config'))
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return (data is Map ? data['ip'] ?? '' : '').toString();
  }

  Future<String> setJblIp(String ip) async {
    final resp = await http
        .put(
          Uri.parse('${config.baseUrl}/jbl/config'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ip': ip}),
        )
        .timeout(const Duration(seconds: 5));
    final data = _jblOk(resp);
    return (data['ip'] ?? '').toString();
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
}
