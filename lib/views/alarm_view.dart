import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/alarm_event.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/siren_service.dart';
import '../services/notification_service.dart';
import 'active_alarm_view.dart';
import 'settings_view.dart';
import 'in_app_notification.dart';

class AlarmView extends StatefulWidget {
  final ServerConfig? initialConfig;

  const AlarmView({super.key, this.initialConfig});

  @override
  State<AlarmView> createState() => _AlarmViewState();
}

class _AlarmViewState extends State<AlarmView> with WidgetsBindingObserver {
  late ServerConfig _config;
  ApiService? _api;
  final SocketService _socket = SocketService();
  final SirenService _siren = SirenService();
  final NotificationService _notifications = NotificationService();

  bool _isArmed = false;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isToggling = false;
  String? _error;
  AlarmEvent? _activeAlarm;

  StreamSubscription? _alarmSub;
  StreamSubscription? _armedSub;
  StreamSubscription? _connSub;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig ?? ServerConfig();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  static const _apnsChannel = MethodChannel('com.cce.apns');
  String? _deviceToken;

  Future<void> _init() async {
    try {
      await _siren.init();
      await _notifications.init();
      await _notifications.requestPermissions();
    } catch (e) {
      debugPrint('📱 [Flutter] Error init servicios: $e');
    }

    // Listen for native iOS events via MethodChannel
    debugPrint('📱 [Flutter] Esperando token de APNs via MethodChannel...');
    _apnsChannel.setMethodCallHandler((call) async {
      try {
        debugPrint('📱 [Flutter] MethodChannel call: ${call.method}');
        if (call.method == 'onToken') {
          _deviceToken = call.arguments as String;
          debugPrint('📱 [Flutter] Token recibido: ${_deviceToken!.substring(0, 16)}...');
          _registerTokenIfReady();
        } else if (call.method == 'onPushReceived') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          debugPrint('📱 [Flutter] Push recibida in-app: ${data['title']}');
          _showPushAsInApp(data);
        } else if (call.method == 'onPushTapped') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          debugPrint('📱 [Flutter] Push tapped: ${data['title']}');
          _handlePushTapped(data);
        }
      } catch (e) {
        debugPrint('📱 [Flutter] Error en MethodChannel: $e');
      }
    });

    try {
      if (!_config.isConfigured) {
        _config = await ServerConfig.load();
      }
      if (_config.isConfigured) {
        _connectToServer();
      }
    } catch (e) {
      debugPrint('📱 [Flutter] Error cargando config: $e');
    }
  }

  Future<void> _registerTokenIfReady() async {
    debugPrint('📱 [Flutter] _registerTokenIfReady: token=${_deviceToken != null ? "SI" : "NO"}, api=${_api != null ? "SI" : "NO"}');
    if (_deviceToken != null && _api != null) {
      try {
        debugPrint('📱 [Flutter] Enviando token al backend: ${_config.baseUrl}/apns/register');
        await _api!.registerDeviceToken(_deviceToken!, deviceName: 'iPhone');
        debugPrint('📱 [Flutter] Token registrado OK en backend');
      } catch (e) {
        debugPrint('📱 [Flutter] ERROR registrando token: $e');
      }
    }
  }

  void _connectToServer() {
    try {
      _api = ApiService(_config);

      _alarmSub?.cancel();
      _armedSub?.cancel();
      _connSub?.cancel();

      _socket.connect(_config);

      _alarmSub = _socket.onAlarm.listen(_onAlarmTriggered);
      _armedSub = _socket.onArmedChanged.listen((armed) {
        if (!mounted) return;
        setState(() => _isArmed = armed);
        if (!armed && _activeAlarm != null) {
          _dismissAlarm();
        }
      });
      _connSub = _socket.onConnectionChanged.listen((connected) {
        if (!mounted) return;
        setState(() => _isConnected = connected);
        if (connected) _fetchAlarmState();
      });

      _fetchAlarmState();
      _registerTokenIfReady();
    } catch (e) {
      debugPrint('📱 [Flutter] ERROR conectando: $e');
      if (mounted) {
        setState(() => _error = 'Error de conexion');
      }
    }
  }

  Future<void> _fetchAlarmState() async {
    if (_api == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final armed = await _api!.getAlarmState();
      if (!mounted) return;
      setState(() {
        _isArmed = armed;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexion';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleArmed() async {
    if (_api == null || _isToggling || !mounted) return;
    setState(() => _isToggling = true);

    final newState = !_isArmed;
    setState(() => _isArmed = newState);
    HapticFeedback.heavyImpact();

    try {
      final result = await _api!.setAlarmArmed(newState);
      if (!mounted) return;
      setState(() {
        _isArmed = result;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isArmed = !newState;
        _error = 'Error al cambiar estado';
      });
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  void _showPushAsInApp(Map<String, dynamic> data) {
    if (!mounted) return;
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';

    // Determine icon based on content
    IconData icon = Icons.notifications;
    Color color = Colors.white;
    if (title.contains('ACTIVADA')) {
      icon = Icons.shield;
      color = Colors.red;
    } else if (title.contains('DESACTIVADA')) {
      icon = Icons.shield_outlined;
      color = Colors.green;
    } else if (data['soundType'] == 'alarm') {
      icon = Icons.warning_amber_rounded;
      color = Colors.red;
    }

    InAppNotification.show(
      context,
      title: title,
      body: body,
      icon: icon,
      iconColor: color,
    );
  }

  void _handlePushTapped(Map<String, dynamic> data) {
    // If it's an alarm trigger push, fetch latest state
    _fetchAlarmState();
  }

  void _onAlarmTriggered(AlarmEvent event) {
    setState(() => _activeAlarm = event);
    _siren.startSiren(sound: event.sound);
    HapticFeedback.heavyImpact();
    if (mounted) {
      InAppNotification.show(
        context,
        title: event.automationName,
        body: event.message,
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.red,
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _dismissAlarm() {
    _siren.stop();
    setState(() => _activeAlarm = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _config.isConfigured) {
      _socket.connect(_config);
      _fetchAlarmState();
    } else if (state == AppLifecycleState.paused) {
      _socket.disconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmSub?.cancel();
    _armedSub?.cancel();
    _connSub?.cancel();
    _socket.dispose();
    _siren.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsView(
          config: _config,
          onSaved: () {
            _connectToServer();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B3A6B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF152D54),
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !_config.isConfigured
                    ? Colors.grey
                    : _isConnected
                        ? Colors.green
                        : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _config.isConfigured
                  ? 'CCE Home'
                  : 'Configurar servidor',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white54),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          Center(
            child: _config.isConfigured
                ? _buildAlarmButton()
                : _buildSetupPrompt(),
          ),
          // Active alarm overlay
          if (_activeAlarm != null)
            Positioned.fill(
              child: ActiveAlarmView(
                event: _activeAlarm!,
                onDismiss: _dismissAlarm,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSetupPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        const Text(
          'Configura la IP del servidor',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _openSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F3460),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Configurar'),
        ),
      ],
    );
  }

  Widget _buildAlarmButton() {
    if (_isLoading && !_isToggling) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Conectando...',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      );
    }

    final color = _isArmed ? Colors.red : Colors.white38;
    final label = _isArmed ? 'ARMADA' : 'DESARMADA';
    final icon = _isArmed ? Icons.shield : Icons.shield_outlined;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(color: Colors.orange, fontSize: 14),
          ),
          const SizedBox(height: 16),
        ],
        GestureDetector(
          onTap: _toggleArmed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color, width: 4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: color),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Toca para ${_isArmed ? 'desarmar' : 'armar'}',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Text(
          _config.host,
          style: const TextStyle(color: Colors.white24, fontSize: 12),
        ),
      ],
    );
  }
}
