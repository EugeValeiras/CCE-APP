import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/phone_call.dart';
import '../models/server_config.dart';
import 'api_service.dart';
import 'socket_service.dart';

/// Id canónico del teléfono 4G en /merged. Emite `device:state-changed` con el
/// estado de la llamada en vivo; el historial va por `phone:call-state`.
const String kPhoneDeviceId = 'dev_phone';

/// Estado y historial de la telefonía 4G (HAT SIM7600G-H).
///
/// La app NO disca: el dial pad vive sólo en el dashboard (decisión de
/// producto). Acá se muestra el estado de la línea, el historial con las
/// perdidas destacadas, y llega la push cuando entra una llamada.
///
/// SEED + PUSH, sin polling: un `GET /phone/status` y un `GET /phone/calls` al
/// arrancar, y de ahí en más manda el socket. El historial se actualiza solo
/// cuando termina una llamada, sin volver a pedirlo.
///
/// `ChangeNotifier` + `AnimatedBuilder`, como el resto de la app: nada de
/// Riverpod/Provider/Bloc.
class TelephonyService extends ChangeNotifier {
  final ApiService _api;
  final SocketService _socket;

  TelephonyService({required ServerConfig config, required SocketService socket})
      : _api = ApiService(config),
        _socket = socket;

  PhoneStatus _status = const PhoneStatus();
  List<PhoneCall> _calls = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  /// Llamada entrante sonando AHORA (para el banner de la pantalla).
  Map<String, dynamic>? _incoming;

  /// Perdidas nuevas desde la última vez que se abrió el historial. Alimenta el
  /// badge de la card: una perdida es el aviso de último recurso de la casa.
  int _unseenMissed = 0;

  StreamSubscription<PhoneCallStateEvent>? _callSub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  PhoneStatus get status => _status;
  List<PhoneCall> get calls => _calls;
  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get incoming => _incoming;
  int get unseenMissed => _unseenMissed;

  /// El módulo está habilitado y el módem responde.
  bool get available => _status.enabled && _status.online;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ── Seed + push ───────────────────────────────────────────────────────────

  /// Idempotente: siembra estado e historial y se suscribe al socket. Lo llama
  /// el shell al conectarse, no la pantalla — así el contador de perdidas de la
  /// card está bien aunque nunca se abra el teléfono.
  void start() {
    _callSub?.cancel();
    _connSub?.cancel();
    refresh();

    _callSub = _socket.onCallState.listen((event) {
      if (event.isIncoming) {
        _incoming = event.payload;
        _safeNotify();
        return;
      }
      // 'ended': cae el banner y la llamada entra al historial en el acto, sin
      // volver a pedirlo al servidor.
      _incoming = null;
      final call = PhoneCall.fromJson(event.payload);
      _calls = [call, ..._calls].take(200).toList();
      if (call.isMissed) _unseenMissed++;
      _safeNotify();
    });

    // Tras una RE-conexión pudimos perder eventos: re-sincronizar. En la
    // conexión inicial no hace falta (el seed de arriba ya corrió).
    _connSub = _socket.onConnectionChanged.listen((connected) {
      if (connected && _wasConnected) refresh();
      _wasConnected = connected;
    });
  }

  void stop() {
    _callSub?.cancel();
    _callSub = null;
    _connSub?.cancel();
    _connSub = null;
  }

  /// Re-lee estado e historial. Nunca tira: un teléfono que no responde deja la
  /// pantalla en su último estado conocido con el error a la vista.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _safeNotify();
    try {
      final results = await Future.wait([
        _api.getPhoneStatus(),
        _api.getPhoneCalls(),
      ]);
      _status = results[0] as PhoneStatus;
      _calls = results[1] as List<PhoneCall>;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Marca las perdidas como vistas (al abrir la pantalla del teléfono).
  void markMissedSeen() {
    if (_unseenMissed == 0) return;
    _unseenMissed = 0;
    _safeNotify();
  }

  void dismissIncoming() {
    if (_incoming == null) return;
    _incoming = null;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
