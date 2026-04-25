import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';
import '../models/device.dart';
import '../models/event_record.dart';
import '../models/floor_plan.dart';

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
}
