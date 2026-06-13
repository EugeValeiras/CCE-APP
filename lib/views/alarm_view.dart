import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/alarm_event.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/siren_service.dart';
import '../services/notification_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import 'active_alarm_view.dart';
import 'settings_view.dart';
import 'in_app_notification.dart';

class AlarmView extends StatefulWidget {
  final ServerConfig? initialConfig;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ el
  /// shell del tablet lo deja idéntico.
  final bool neo;

  const AlarmView({super.key, this.initialConfig, this.neo = false});

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

  void _ackAlarm(String? alarmId) {
    if (alarmId == null || alarmId.isEmpty || _api == null) return;
    _api!.ackAlarm(alarmId).catchError((e) {
      debugPrint('📱 [Flutter] Error acking alarm: $e');
    });
  }

  void _showPushAsInApp(Map<String, dynamic> data) {
    if (!mounted) return;
    _ackAlarm(data['automationId'] as String?);
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
    _ackAlarm(data['automationId'] as String?);
    _fetchAlarmState();
  }

  void _onAlarmTriggered(AlarmEvent event) {
    _ackAlarm(event.automationId);
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
    _ackAlarm(_activeAlarm?.automationId);
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
      backgroundColor: widget.neo ? CceColors.neoBase : CceColors.bg,
      appBar: AppBar(
        backgroundColor: widget.neo ? CceColors.neoBase : null,
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
                        ? CceColors.ok
                        : CceColors.danger,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _config.isConfigured
                  ? 'CCE Home'
                  : 'Configurar servidor',
              style: CceText.title.copyWith(fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const CceIcon(CceIcons.settings, color: CceColors.textTertiary),
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
        Text(
          'Configura la IP del servidor',
          style: CceText.body.copyWith(color: CceColors.textTertiary, fontSize: 16),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _openSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: CceColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CceRadii.control),
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
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Conectando...',
            style: TextStyle(color: CceColors.textTertiary, fontSize: 14),
          ),
        ],
      );
    }

    // Armada: rojo danger; desarmada: surfaceHigh + borde hairline.
    final fg = _isArmed ? CceColors.danger : CceColors.textTertiary;
    final fill = _isArmed
        ? CceColors.danger.withValues(alpha: 0.15)
        : CceColors.surfaceHigh;
    final borderColor = _isArmed ? CceColors.danger : CceColors.stroke;
    final label = _isArmed ? 'ARMADA' : 'DESARMADA';
    final icon = _isArmed ? Icons.shield : Icons.shield_outlined;

    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final buttonSize = isTablet ? 340.0 : 200.0;
    final iconSize = isTablet ? 110.0 : 64.0;
    final labelSize = isTablet ? 28.0 : 18.0;
    final hintSize = isTablet ? 20.0 : 14.0;
    final hostSize = isTablet ? 16.0 : 12.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: CceColors.contact, fontSize: hintSize),
          ),
          const SizedBox(height: 16),
        ],
        GestureDetector(
          onTap: _toggleArmed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Desarmada + neo: disco neumórfico elevado (neoBase, sin borde).
              color: widget.neo && !_isArmed ? CceColors.neoBase : fill,
              border: widget.neo && !_isArmed
                  ? null
                  : Border.all(color: borderColor, width: isTablet ? 6 : 4),
              boxShadow: _isArmed
                  ? [
                      BoxShadow(
                        color: CceColors.danger.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ]
                  : (widget.neo
                      ? CceShadows.neo(blur: 28, offset: 12, intensity: 1.1)
                      : null),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: fg),
                SizedBox(height: isTablet ? 14 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: isTablet ? 48 : 32),
        Text(
          'Toca para ${_isArmed ? 'desarmar' : 'armar'}',
          style: TextStyle(color: CceColors.textTertiary, fontSize: hintSize),
        ),
        const SizedBox(height: 8),
        Text(
          _config.host,
          style: TextStyle(color: Colors.white24, fontSize: hostSize),
        ),
      ],
    );
  }
}
