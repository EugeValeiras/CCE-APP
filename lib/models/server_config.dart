import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  String host;
  int port;

  ServerConfig({this.host = '100.79.196.98', this.port = 3000});

  /// Token de autenticación de CCE-API (header `X-CCE-Token`). Se inyecta en
  /// build-time vía --dart-define=CCE_API_TOKEN=... (Codemagic lo toma de su
  /// variable segura homónima; el valor canónico vive en el .env de CCE-API
  /// en la Pi). Así el secreto nunca entra a git. Mientras esté vacío NO se
  /// manda el header (el backend arranca en modo warn: nada se rompe).
  static const String apiToken = String.fromEnvironment('CCE_API_TOKEN');

  /// Identidad de este cliente ante la API (header `X-CCE-Client`): el
  /// command ledger del backend registra QUIÉN hizo cada escritura. Constante
  /// porque todo lo que sale de la app es el usuario operando su teléfono.
  static const String clientId = 'user:app';

  /// Headers comunes para TODAS las llamadas HTTP a la API: identidad del
  /// cliente (siempre — el ledger la necesita aun sin auth) + token de auth
  /// solo si está configurado (sin token el backend corre en modo warn y
  /// nada se rompe).
  static Map<String, String> get tokenHeaders => apiToken.isEmpty
      ? const {'X-CCE-Client': clientId}
      : const {'X-CCE-Client': clientId, 'X-CCE-Token': apiToken};

  String get baseUrl => 'http://$host:$port/api';
  String get socketUrl => 'http://$host:$port';
  bool get isConfigured => host.isNotEmpty;

  static Future<ServerConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ServerConfig(
      host: prefs.getString('server_host') ?? '100.79.196.98',
      port: prefs.getInt('server_port') ?? 3000,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setInt('server_port', port);
  }
}
