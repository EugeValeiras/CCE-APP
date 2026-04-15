import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';

class ApiService {
  final ServerConfig config;

  ApiService(this.config);

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
