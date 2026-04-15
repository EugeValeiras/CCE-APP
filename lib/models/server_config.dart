import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  String host;
  int port;

  ServerConfig({this.host = '', this.port = 3000});

  String get baseUrl => 'http://$host:$port/api';
  String get socketUrl => 'http://$host:$port';
  bool get isConfigured => host.isNotEmpty;

  static Future<ServerConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ServerConfig(
      host: prefs.getString('server_host') ?? '',
      port: prefs.getInt('server_port') ?? 3000,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setInt('server_port', port);
  }
}
