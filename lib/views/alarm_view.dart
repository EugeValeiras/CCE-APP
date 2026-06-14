import 'dart:async';
import 'dart:math' as math;
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

    final label = _isArmed ? 'ARMADA' : 'DESARMADA';
    final icon = _isArmed ? Icons.shield : Icons.shield_outlined;
    // Legacy (sin neo): rojo danger / gris + borde hairline.
    final fg = _isArmed ? CceColors.danger : CceColors.textTertiary;
    final fill = _isArmed
        ? CceColors.danger.withValues(alpha: 0.15)
        : CceColors.surfaceHigh;
    final borderColor = _isArmed ? CceColors.danger : CceColors.stroke;

    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final buttonSize = isTablet ? 360.0 : 232.0;
    final iconSize = isTablet ? 100.0 : 58.0;
    final labelSize = isTablet ? 26.0 : 17.0;
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
          child: widget.neo
              ? _AlarmDial(
                  armed: _isArmed,
                  size: buttonSize,
                  iconSize: iconSize,
                  labelSize: labelSize,
                  label: label,
                )
              : AnimatedContainer(
                  // Legacy (sin neo): disco simple con borde + glow rojo.
                  duration: const Duration(milliseconds: 300),
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    border:
                        Border.all(color: borderColor, width: isTablet ? 6 : 4),
                    boxShadow: _isArmed
                        ? [
                            BoxShadow(
                              color: CceColors.danger.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ]
                        : null,
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

/// Dial neumórfico de la alarma (estilo "perilla"): disco oscuro elevado con
/// cara hundida. Armada → anillo rojo con glow + arco punteado giratorio +
/// escudo y label rojos. Desarmada → escudo plateado + label gris, sin anillo.
class _AlarmDial extends StatefulWidget {
  const _AlarmDial({
    required this.armed,
    required this.size,
    required this.iconSize,
    required this.labelSize,
    required this.label,
  });

  final bool armed;
  final double size;
  final double iconSize;
  final double labelSize;
  final String label;

  @override
  State<_AlarmDial> createState() => _AlarmDialState();
}

class _AlarmDialState extends State<_AlarmDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final armed = widget.armed;
    const red = CceColors.danger;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Disco base (rim) elevado: gradiente vertical + sombra inferior
          //    fuerte (elevación) y luz superior tenue.
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF31333B), Color(0xFF141519)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.62),
                  offset: Offset(0, s * 0.075),
                  blurRadius: s * 0.16,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.05),
                  offset: Offset(0, -s * 0.035),
                  blurRadius: s * 0.09,
                  spreadRadius: -s * 0.02,
                ),
              ],
            ),
          ),
          // 2. Anillo rojo animado (solo armada), sobre el rim.
          if (armed)
            AnimatedBuilder(
              animation: _spin,
              builder: (_, __) => CustomPaint(
                size: Size(s, s),
                painter: _AlarmRingPainter(color: red, rotation: _spin.value),
              ),
            ),
          // 3. Cara interna hundida.
          Container(
            width: s * 0.82,
            height: s * 0.82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(0, -0.35),
                radius: 0.95,
                colors: [Color(0xFF24262D), Color(0xFF0E0F12)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.04),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  offset: Offset(0, s * 0.03),
                  blurRadius: s * 0.06,
                  spreadRadius: -2,
                ),
              ],
            ),
          ),
          // 4. Escudo + label.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: armed
                      ? const [Color(0xFFFF6B6B), Color(0xFFC42E2A)]
                      : const [Color(0xFFD4D8E0), Color(0xFF6C717C)],
                ).createShader(r),
                child: Icon(
                  armed ? Icons.shield : Icons.shield_outlined,
                  size: widget.iconSize,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                        color: Color(0x80000000),
                        offset: Offset(0, 2),
                        blurRadius: 8),
                  ],
                ),
              ),
              SizedBox(height: s * 0.045),
              Text(
                widget.label,
                style: TextStyle(
                  color: armed ? const Color(0xFFFF6B6B) : const Color(0xFF9BA0AB),
                  fontSize: widget.labelSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  shadows: const [
                    Shadow(
                        color: Color(0x99000000),
                        offset: Offset(0, 1),
                        blurRadius: 3),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Anillo rojo del dial armado: glow difuso + línea nítida (arco de ~270°),
/// arco tenue en el resto y un arco punteado que gira despacio.
class _AlarmRingPainter extends CustomPainter {
  _AlarmRingPainter({required this.color, required this.rotation});

  final Color color;
  final double rotation; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 * 0.80;
    final rect = Rect.fromCircle(center: c, radius: r);

    const start = math.pi * 0.82; // ~148°, hueco abajo-izquierda
    const sweep = math.pi * 1.5; // 270°

    // Glow difuso.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawArc(rect, start, sweep, false, glow);

    // Línea nítida.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.014
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, start, sweep, false, line);

    // Resto del círculo, tenue.
    final dim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.009
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.20);
    canvas.drawArc(rect, start + sweep, math.pi * 2 - sweep, false, dim);

    // Arco punteado giratorio (afuera).
    final dotR = r + size.width * 0.045;
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    const dots = 16;
    final base = -math.pi * 0.5 + rotation * 2 * math.pi;
    const span = math.pi * 0.62;
    for (var i = 0; i < dots; i++) {
      final a = base + span * (i / (dots - 1));
      final p = Offset(c.dx + dotR * math.cos(a), c.dy + dotR * math.sin(a));
      canvas.drawCircle(p, size.width * 0.008, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_AlarmRingPainter old) =>
      old.rotation != rotation || old.color != color;
}
