import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/alarm_event.dart';
import '../models/device.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../services/push_channel.dart';
import '../services/socket_service.dart';
import '../services/siren_service.dart';
import '../services/notification_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/section_header.dart';
import '../utils/alarm_triggers.dart';
import '../utils/contact_words.dart';
import '../utils/time_format.dart';
import 'active_alarm_view.dart';
import 'alarm_sensors_screen.dart';
import 'sensor_detail_screen.dart';
import 'settings_view.dart';
import 'in_app_notification.dart';

class AlarmView extends StatefulWidget {
  final ServerConfig? initialConfig;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ el
  /// shell del tablet lo deja idéntico.
  final bool neo;

  /// Inventario de la casa, para la lista "qué protege" (sensores de
  /// apertura y movimiento con su estado). Opcional: sin él la pantalla es
  /// sólo el dial (flujo de configuración inicial).
  final DevicesService? devices;

  /// Inyectables para tests (mismo patrón que `AlarmSensorsScreen.api`). En
  /// producción los tres se construyen acá adentro.
  @visibleForTesting
  final ApiService? api;
  @visibleForTesting
  final SocketService? socket;
  @visibleForTesting
  final SirenService? siren;

  const AlarmView({
    super.key,
    this.initialConfig,
    this.neo = false,
    this.devices,
    this.api,
    this.socket,
    this.siren,
  });

  @override
  State<AlarmView> createState() => _AlarmViewState();
}

class _AlarmViewState extends State<AlarmView> with WidgetsBindingObserver {
  late ServerConfig _config;
  ApiService? _api;
  /// Los servicios que ESTE state creó, y por lo tanto los únicos que puede
  /// destruir. `SocketService.dispose()` cierra sus siete StreamControllers:
  /// hacerlo sobre un socket que vino inyectado —el compartido de
  /// `DevicesService`, por ejemplo— mataría los eventos de TODA la app al
  /// salir de esta pantalla.
  late final bool _ownsSocket = widget.socket == null;
  late final bool _ownsSiren = widget.siren == null;
  late final SocketService _socket = widget.socket ?? SocketService();
  late final SirenService _siren = widget.siren ?? SirenService();
  final NotificationService _notifications = NotificationService();

  bool _isArmed = false;

  /// Modo prueba (CCE#122): la alarma sigue armada y sigue disparando, pero el
  /// aviso llega mudo. Va al lado del estado en la pantalla porque un dial que
  /// dice "ARMADA" a secas mientras esto está prendido es una trampa.
  bool _isTestMode = false;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isToggling = false;
  String? _error;
  AlarmEvent? _activeAlarm;

  /// Desde cuándo la alarma está en su estado actual (último
  /// `alarm:armed-changed` del event store; se pisa con cada cambio en vivo).
  /// null = todavía no se sabe: la línea no se muestra.
  DateTime? _armedSince;

  /// Qué sensores disparan la alarma (`sensorAlarmTriggers` del backend), la
  /// fuente de "qué protege". null = todavía no se leyó: la lista espera en
  /// vez de mostrar de más (todos) o de menos (ninguno).
  Map<String, bool>? _alarmTriggers;

  StreamSubscription? _alarmSub;
  StreamSubscription? _armedSub;
  StreamSubscription? _connSub;
  StreamSubscription? _tokenSub;
  StreamSubscription? _pushReceivedSub;
  StreamSubscription? _pushTapSub;
  StreamSubscription? _configSub;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig ?? ServerConfig();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  String? _deviceToken;

  Future<void> _init() async {
    try {
      await _siren.init();
      await _notifications.init();
      await _notifications.requestPermissions();
    } catch (e) {
      debugPrint('📱 [Flutter] Error init servicios: $e');
    }

    // Los eventos nativos de APNs llegan por PushChannel (CCE#23), que es
    // el dueño del MethodChannel desde `main()`: esta pantalla ya no es la
    // única que los escucha (el shell atiende el toque de la push de un SMS)
    // y el token puede haber llegado antes de que se montara.
    debugPrint('📱 [Flutter] Esperando token de APNs via PushChannel...');
    final push = PushChannel.instance;
    push.install();
    _deviceToken = push.lastToken;
    _tokenSub = push.onToken.listen((token) {
      _deviceToken = token;
      debugPrint('📱 [Flutter] Token recibido: ${token.substring(0, 16)}...');
      _registerTokenIfReady();
    });
    _pushReceivedSub = push.onPushReceived.listen((data) {
      // La push de un SMS la muestra el shell, que es quien puede abrirla.
      if (data['kind'] == 'phone-sms') return;
      debugPrint('📱 [Flutter] Push recibida in-app: ${data['title']}');
      _showPushAsInApp(data);
    });
    _pushTapSub = push.onPushTapped.listen((data) {
      debugPrint('📱 [Flutter] Push tapped: ${data['title']}');
      _handlePushTapped(data);
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
      _api = widget.api ?? ApiService(_config);

      _alarmSub?.cancel();
      _armedSub?.cancel();
      _connSub?.cancel();
      _configSub?.cancel();

      _socket.connect(_config);

      _alarmSub = _socket.onAlarm.listen(_onAlarmTriggered);
      _armedSub = _socket.onArmedChanged.listen((armed) {
        if (!mounted) return;
        setState(() {
          if (armed != _isArmed) _armedSince = DateTime.now();
          _isArmed = armed;
        });
        if (!armed && _activeAlarm != null) {
          _dismissAlarm();
        }
      });
      _connSub = _socket.onConnectionChanged.listen((connected) {
        if (!mounted) return;
        setState(() => _isConnected = connected);
        if (connected) _fetchAlarmState();
      });
      // El flag de disparo también se toca desde el detalle de un sensor y
      // desde el dashboard: el backend avisa con `config:changed`, así que la
      // lista no queda vieja sin tener que volver a entrar a la pantalla.
      _configSub = _socket.onLiveEvent.listen((ev) {
        if (ev.eventName != 'config:changed') return;
        final section = ev.payload['section'];
        if (section == 'sensorAlarmTriggers' || section == 'all') {
          _loadAlarmTriggers();
        }
        // El modo prueba se prende desde el CLI, el dashboard o esta misma
        // App: sin esto el dial seguiría prometiendo una alarma que suena.
        if (section == 'alarm' || section == 'all') {
          _fetchAlarmState();
        }
      });

      _fetchAlarmState();
      _loadAlarmTriggers();
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
      final status = await _api!.getAlarmStatus();
      if (!mounted) return;
      setState(() {
        _isArmed = status.armed;
        // Acá `null` (backend sin la clave) se pinta como apagado: el chip
        // sólo AVISA, no ofrece cambiar nada. El switch de la pantalla de
        // sensores sí distingue el null, porque ahí un toggle que no se puede
        // guardar sería una mentira.
        _isTestMode = status.testMode ?? false;
        _error = null;
        _isLoading = false;
      });
      _fetchArmedSince();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexion';
        _isLoading = false;
      });
    }
  }

  /// "Desarmada desde las 08:02": el último cambio de armado que grabó el
  /// event store. Best-effort: sin evento (o sin historial habilitado) la
  /// línea simplemente no aparece.
  Future<void> _fetchArmedSince() async {
    final api = _api;
    if (api == null) return;
    try {
      final page = await api.getEvents(
        eventName: 'alarm:armed-changed',
        channel: 'websocket',
        limit: 1,
      );
      if (!mounted || page.items.isEmpty) return;
      final last = page.items.first;
      final ms = last.payload?['timestamp'];
      final ts = ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : TimeFormat.parseEventTime(last.time);
      setState(() => _armedSince = ts);
    } catch (e) {
      debugPrint('📱 [Flutter] Sin fecha de armado: $e');
    }
  }

  /// Lee el mapa `sensorAlarmTriggers` que decide qué entra a "qué protege".
  /// Best-effort: si falla, la lista se queda en su último valor conocido (o
  /// sin dibujar si nunca hubo uno) en vez de mostrar sensores que no suenan.
  Future<void> _loadAlarmTriggers() async {
    final api = _api;
    if (api == null) return;
    try {
      final triggers = await api.getSensorAlarmTriggers();
      if (!mounted) return;
      setState(() => _alarmTriggers = triggers);
    } catch (e) {
      debugPrint('📱 [Flutter] Sin mapa de disparos de alarma: $e');
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
        _armedSince = DateTime.now();
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
    } else if (title.contains('Llamada')) {
      // Telefonía 4G: la push de llamada entrante llega mientras el teléfono
      // TODAVÍA suena, así que el aviso in-app tiene que decir de un vistazo
      // que es una llamada y no una alarma.
      icon = Icons.phone_callback;
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

  /// Un disparo llegó por el websocket.
  ///
  /// El TIPO decide (EugeValeiras/CCE#122). Antes esto arrancaba la sirena y
  /// tomaba la pantalla sin mirar `event.critical`: con la App abierta, un
  /// aviso `info` sonaba igual que un robo — y con eso el modo prueba no se
  /// cumplía justo en el dispositivo donde más importa. El Dashboard ya lo
  /// resolvía del otro lado (`alarm.service.ts`: sólo `critical` toma la
  /// pantalla); esta es la mitad que faltaba.
  void _onAlarmTriggered(AlarmEvent event) {
    _ackAlarm(event.automationId);

    if (!event.critical) {
      // Aviso discreto y nada más: sin sirena, sin pantalla roja, sin vibrar.
      if (mounted) {
        InAppNotification.show(
          context,
          title: event.automationName,
          body: event.message,
          icon: Icons.notifications_active_outlined,
          iconColor: CceColors.textSecondary,
          duration: const Duration(seconds: 6),
        );
      }
      return;
    }

    // La alarma de la casa: pantalla completa, sirena y vibración. No se toca.
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
    _configSub?.cancel();
    _tokenSub?.cancel();
    _pushReceivedSub?.cancel();
    _pushTapSub?.cancel();
    // SÓLO lo que creó este state (ver `_ownsSocket`). Un servicio inyectado es
    // del caller: ni `dispose()` ni `disconnect()` — las suscripciones propias
    // ya se cancelaron arriba, y eso es todo lo que esta pantalla tiene que
    // deshacer.
    if (_ownsSocket) _socket.dispose();
    if (_ownsSiren) _siren.dispose();
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

  /// El engranaje de la alarma abre QUÉ SENSORES la disparan, no la config del
  /// servidor (que en el teléfono vive al pie de la home, en "Cerrar sesión").
  ///
  /// Excepción: el flujo de configuración inicial —sin servidor cargado o sin
  /// inventario, como cuando `main.dart` monta la pantalla suelta— no tiene
  /// sensores que listar y el engranaje sigue siendo su única puerta a los
  /// ajustes.
  Future<void> _openGear() async {
    final devices = widget.devices;
    if (devices == null || !_config.isConfigured) {
      _openSettings();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlarmSensorsScreen(devices: devices),
      ),
    );
    // Al volver, "qué protege" tiene que reflejar lo que se acaba de marcar.
    await _loadAlarmTriggers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.neo ? CceColors.neoBase : CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
              _config.isConfigured ? 'Alarma' : 'Configurar servidor',
              style: CceText.title,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.devices == null || !_config.isConfigured
                ? 'Ajustes'
                : 'Sensores de la alarma',
            icon: const CceIcon(CceIcons.settings, color: CceColors.textTertiary),
            onPressed: _openGear,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          if (!_config.isConfigured)
            Center(child: _buildSetupPrompt())
          else if (widget.devices == null)
            Center(child: _buildAlarmButton())
          else
            // Dial arriba y, debajo, qué protege la alarma. Scrolleable: en
            // una casa con muchos sensores la lista no entra bajo el dial.
            ListView(
              padding: EdgeInsets.fromLTRB(
                  CceSpace.lg, CceSpace.xl, CceSpace.lg, CceSpace.xl),
              children: [
                _buildAlarmButton(),
                ProtectedList(
                  devices: widget.devices!,
                  triggers: _alarmTriggers,
                  onConfigure: _openGear,
                ),
              ],
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
        mainAxisSize: MainAxisSize.min,
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

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
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
        SizedBox(height: isTablet ? CceSpace.xxxl : CceSpace.xxl),
        // MODO PRUEBA (CCE#122): va PEGADO al dial y no escondido en el
        // engranaje. El toggle es manual y no vence solo: la única defensa
        // contra olvidarlo prendido es verlo cada vez que se mira la alarma.
        if (_isTestMode) ...[
          _TestModeChip(fontSize: hintSize),
          SizedBox(height: CceSpace.md),
        ],
        Text(
          'Tocá para ${_isArmed ? 'desarmar' : 'armar'}',
          style: CceText.body.copyWith(
            color: CceColors.textTertiary,
            fontSize: hintSize,
          ),
        ),
        // Desde cuándo está así. El host del servidor que iba acá era
        // diagnóstico: vive en Ajustes.
        if (_armedSince != null) ...[
          SizedBox(height: CceSpace.sm),
          Text(
            '${_isArmed ? 'Armada' : 'Desarmada'} '
            '${TimeFormat.since(_armedSince!)}',
            style: CceText.dataCaption.copyWith(
              fontSize: isTablet ? 16 : 13,
            ),
          ),
        ],
      ],
    );
  }
}

/// "MODO PRUEBA · No va a sonar", bajo el dial (CCE#122).
///
/// Ámbar y no rojo a propósito: en esta pantalla el rojo ya significa "armada",
/// y confundir las dos cosas sería peor que no decir nada.
class _TestModeChip extends StatelessWidget {
  const _TestModeChip({required this.fontSize});

  final double fontSize;

  static const Color _amber = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: CceSpace.md, vertical: CceSpace.sm),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        border: Border.all(color: _amber.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(CceRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volume_off_outlined, size: fontSize + 4, color: _amber),
          SizedBox(width: CceSpace.sm),
          Flexible(
            child: Text(
              'MODO PRUEBA · no va a sonar',
              style: CceText.body.copyWith(
                color: _amber,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
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

/// Sensores que la alarma vigila, en el orden en que importan: aperturas
/// primero (las ABIERTAS arriba de todo: son lo que va a disparar la alarma
/// apenas la armes), después movimiento (activo primero, el resto por
/// recencia). Pura, para testear el criterio sin montar la pantalla.
List<Device> protectedSensors(Iterable<Device> all) {
  final list = all
      .where((d) =>
          !d.hidden && !isPseudoSensor(d) && (d.isContactSensor || d.isMotionSensor))
      .toList();
  int rank(Device d) {
    if (d.isContactSensor) return d.sensor?.contact == true ? 0 : 1;
    return d.sensor?.motion == true ? 2 : 3;
  }

  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (rank(a) == 3) {
      // Movimiento en reposo: el que se disparó más recientemente primero.
      final ta = lastTriggerAt(a), tb = lastTriggerAt(b);
      if (ta != null && tb != null && ta != tb) return tb.compareTo(ta);
      if (ta == null && tb != null) return 1;
      if (ta != null && tb == null) return -1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

/// Pseudo-devices del backend que declaran `contact` pero no son un sensor de
/// la casa: los ANUNCIADORES (`dev_announcer_*`, type `announcer`), que existen
/// para que el backend avise cosas —"Portón abriendo", "Portón abierto"— y la
/// propia ALARMA (`dev_alarm`, binding `alarm_alarm`, hoy `hidden`).
///
/// No tienen nada que hacer en una lista que promete qué protege la casa ni en
/// la que ofrece marcar qué la dispara: marcar "la alarma" para que dispare la
/// alarma no significa nada. Si aparece otro pseudo-device del mismo estilo, va
/// acá — el criterio es el prefijo de su binding, que es lo que los distingue
/// de un device de provider (`ewelink_`, `matter_`, `hue_`, `tuya_`…).
bool isPseudoSensor(Device d) {
  const pseudoTypes = {'announcer', 'alarm'};
  final type = d.type.toLowerCase().trim();
  if (pseudoTypes.contains(type)) return true;
  return d.bindingIds.any((b) =>
      pseudoTypes.any((p) => b.toLowerCase().startsWith('${p}_')));
}

/// Último disparo del sensor: el `trigTime` que reporta el propio sensor, o
/// el último evento que la app le vio.
DateTime? lastTriggerAt(Device d) {
  final t = d.sensor?.trigTime;
  if (t != null && t > 0) return DateTime.fromMillisecondsSinceEpoch(t);
  return d.lastEventAt;
}

/// "Qué protege": los sensores que EFECTIVAMENTE disparan la alarma, con su
/// estado, en filas de 52 px con hairline (el mismo molde que el historial).
/// Se reconstruye con cada evento del inventario.
///
/// El filtro es el punto: antes se listaban todos los sensores de la casa,
/// así que la pantalla prometía protección que no existía. Lo que decide es
/// el mapa `sensorAlarmTriggers` ([triggers]), resuelto por [firesAlarm] —
/// que prueba el id canónico Y los bindings, porque el mapa mezcla las dos
/// familias de ids.
///
/// Pública por el mismo motivo que [protectedSensors]: el criterio se prueba
/// sin montar la pantalla (que abre sockets y HTTP al construirse).
class ProtectedList extends StatelessWidget {
  const ProtectedList({
    super.key,
    required this.devices,
    required this.triggers,
    required this.onConfigure,
  });

  final DevicesService devices;

  /// null = todavía no se leyó el mapa. La sección no se dibuja: con una
  /// lista de seguridad, esperar un instante es mejor que afirmar algo falso.
  final Map<String, bool>? triggers;

  /// Abre la pantalla donde se elige qué sensores disparan la alarma.
  final VoidCallback onConfigure;

  static const double _row = 52;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        final triggers = this.triggers;
        if (triggers == null) return const SizedBox.shrink();
        final candidates = protectedSensors(devices.all);
        // Una casa sin sensores de apertura ni movimiento no tiene nada que
        // explicar: no hay decisión que ofrecer.
        if (candidates.isEmpty) return const SizedBox.shrink();

        final sensors =
            candidates.where((d) => firesAlarm(d, triggers)).toList();
        // El contador cuenta sobre lo que se muestra: decir "2 abiertas" por
        // puertas que no van a sonar es exactamente el ruido que esta tarea
        // saca de la pantalla.
        final open = sensors
            .where((d) => d.isContactSensor && d.sensor?.contact == true)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: CceSpace.lg),
            SectionHeader(
              title: 'Qué protege',
              counter: open == 0
                  ? null
                  : ContactWords.openCount(open),
            ),
            if (sensors.isEmpty)
              _emptyRow(context)
            else
              for (final d in sensors) _row_(context, d),
          ],
        );
      },
    );
  }

  /// Con cero sensores marcados la sección NO puede desaparecer: una casa
  /// donde nunca se configuró nada se quedaría sin explicación, leyendo la
  /// ausencia como "todo en orden". Dice por qué está vacía y lleva a
  /// arreglarlo.
  Widget _emptyRow(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onConfigure,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CceColors.strokeSoft)),
          ),
          child: Row(
            children: [
              const CceIcon(CceIcons.alarmShield,
                  size: 20, color: CceColors.textTertiary, emboss: false),
              SizedBox(width: CceSpace.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ningún sensor dispara la alarma',
                      style: CceText.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('Tocá para elegir cuáles', style: CceText.caption),
                  ],
                ),
              ),
              SizedBox(width: CceSpace.sm),
              const CceIcon(CceIcons.chevronRight,
                  size: 18, color: CceColors.textTertiary, emboss: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row_(BuildContext context, Device d) {
    final String svg;
    final Color iconColor;
    final Widget trailing;
    if (d.isContactSensor) {
      final isOpen = d.sensor?.contact == true;
      svg = isOpen ? CceIcons.doorOpen : CceIcons.doorClosed;
      iconColor = isOpen ? CceColors.contact : CceColors.textTertiary;
      // La abierta va en su color: es la que va a disparar la alarma.
      trailing = Text(
        ContactWords.label(isOpen),
        style: isOpen
            ? CceText.label.copyWith(color: CceColors.contact)
            : CceText.caption.copyWith(color: CceColors.textTertiary),
      );
    } else {
      final active = d.sensor?.motion == true;
      svg = active ? CceIcons.personStanding : CceIcons.footprints;
      iconColor = active ? CceColors.motion : CceColors.textTertiary;
      final last = lastTriggerAt(d);
      trailing = active
          ? Text('Movimiento',
              style: CceText.label.copyWith(color: CceColors.motion))
          : Text(
              last == null ? 'Sin movimiento' : TimeFormat.relative(last),
              style: CceText.dataCaption,
            );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SensorDetailScreen(device: d, service: devices),
        )),
        child: Container(
          height: _row,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CceColors.strokeSoft)),
          ),
          child: Row(
            children: [
              CceIcon(svg, size: 20, color: iconColor, emboss: false),
              SizedBox(width: CceSpace.md),
              Expanded(
                child: Text(
                  devices.displayName(d),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.body,
                ),
              ),
              SizedBox(width: CceSpace.sm),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
