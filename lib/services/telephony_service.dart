import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/phone_call.dart';
import '../models/server_config.dart';
import 'api_service.dart';
import 'socket_service.dart';

/// Id canónico del teléfono 4G en /merged. Emite `device:state-changed` con el
/// estado de la llamada en vivo; el historial va por `phone:call-state`.
const String kPhoneDeviceId = 'dev_phone';

/// Estado, historial y comandos de la telefonía 4G (HAT SIM7600G-H).
///
/// La app DISCA (issue #10, que reemplaza la decisión de #4): además de leer el
/// estado y el historial, manda call / answer / hangup / dtmf. Lo que la app NO
/// lleva es AUDIO: la voz sale por el jack del HAT o por el navegador, nunca
/// por el celular — ver [PhoneStatus.audioNotice].
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

  /// Libreta del backend. Se carga bajo demanda (nadie la necesita hasta que se
  /// abre la pantalla del teléfono) y se cachea: el ABM es del dashboard, así
  /// que no cambia sola mientras la app está abierta.
  List<PhoneContact> _contacts = const [];
  bool _contactsLoaded = false;

  /// Motivo del último comando rechazado, tal como lo redactó el backend
  /// ("hay una llamada en curso", "rate limit de llamadas por hora alcanzado").
  /// La pantalla lo muestra sin reemplazarlo: un genérico haría que el usuario
  /// reintente contra un límite que no va a ceder.
  String? _actionError;

  /// Número que se acaba de discar, mientras el módem todavía no movió el
  /// estado. El `ATD` puede tardar varios segundos y sin esto la pantalla
  /// parece colgada — pero es un PLACEHOLDER, no estado: en cuanto llega el
  /// `device:state-changed` de `dev_phone` manda el estado real.
  String? _dialingNumber;
  Timer? _dialingTimer;

  /// Un comando en vuelo (call/answer/hangup): bloquea el botón para que dos
  /// toques no manden dos llamadas.
  bool _busy = false;

  StreamSubscription<PhoneCallStateEvent>? _callSub;
  StreamSubscription<DeviceStateEvent>? _deviceSub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  PhoneStatus get status => _status;
  List<PhoneCall> get calls => _calls;
  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get incoming => _incoming;
  int get unseenMissed => _unseenMissed;
  List<PhoneContact> get contacts => _contacts;
  String? get actionError => _actionError;
  String? get dialingNumber => _dialingNumber;
  bool get busy => _busy;

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
    _deviceSub?.cancel();
    _connSub?.cancel();
    refresh();

    // El estado EN VIVO de la llamada viaja por `device:state-changed` sobre
    // `dev_phone`, no por `phone:call-state`. Acá sólo se lo usa para retirar
    // el placeholder de "marcando": el estado que pinta la pantalla sale de
    // DevicesService, y duplicarlo sería tener dos verdades.
    _deviceSub = _socket.onDeviceChanged.listen((event) {
      if (event.deviceId != kPhoneDeviceId) return;
      final state = (event.state?['callState'] ?? '').toString();
      if (state.isEmpty || state == 'idle' || state == 'ended') return;
      _clearDialing();
    });

    _callSub = _socket.onCallState.listen((event) {
      if (event.isIncoming) {
        _incoming = event.payload;
        _safeNotify();
        return;
      }
      // 'ended': cae el banner y la llamada entra al historial en el acto, sin
      // volver a pedirlo al servidor.
      _incoming = null;
      _clearDialing(notify: false);
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
    _deviceSub?.cancel();
    _deviceSub = null;
    _connSub?.cancel();
    _connSub = null;
    _dialingTimer?.cancel();
    _dialingTimer = null;
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

  // ── Libreta ───────────────────────────────────────────────────────────────

  /// Carga la libreta una sola vez. [force] la vuelve a pedir (pull-to-refresh
  /// del sheet), por si el dashboard agregó un contacto con la app abierta.
  Future<void> loadContacts({bool force = false}) async {
    if (_contactsLoaded && !force) return;
    try {
      _contacts = await _api.getPhoneContacts();
      _contactsLoaded = true;
    } catch (_) {
      // La libreta es una comodidad: si no viene, el teclado sigue discando.
      _contactsLoaded = false;
    }
    _safeNotify();
  }

  // ── Comandos ──────────────────────────────────────────────────────────────

  /// Disca. Devuelve true si el backend aceptó el comando — que NO es lo mismo
  /// que "la llamada conectó": eso lo dirá el socket.
  ///
  /// CUESTA PLATA y suena del otro lado de verdad. El audio, en cambio, se
  /// queda en la casa: ver [PhoneStatus.audioNotice].
  Future<bool> call({String? number, String? contactId}) async {
    if (_busy) return false;
    final dialed = number?.trim();
    // "Marcando" se muestra ANTES del POST, no después: el `ATD` puede tardar
    // varios segundos en volver y una pantalla quieta después de tocar "llamar"
    // se lee como que no pasó nada. Además, ponerlo después correría el riesgo
    // de pisar los eventos del socket que llegaron mientras el POST viajaba, y
    // dejar un "marcando" fantasma sobre una llamada ya terminada.
    _startDialing(dialed ?? _contactNumber(contactId) ?? '…');
    return _command(() => _api.phoneCall(number: dialed, contactId: contactId));
  }

  /// Corta lo que haya en curso. También es el "rechazar" de una entrante: el
  /// backend no tiene un endpoint aparte para eso.
  Future<bool> hangup() => _command(
        _api.phoneHangup,
        onSent: () {
          _incoming = null;
          _clearDialing(notify: false);
        },
      );

  /// Atiende la entrante que suena. El audio sigue en la casa.
  Future<bool> answer() => _command(_api.phoneAnswer);

  /// Manda un tono a la llamada en curso. No toca [_busy]: los tonos se tipean
  /// rápido y bloquear el teclado entre tono y tono lo haría inusable.
  Future<bool> sendDtmf(String digits) async {
    if (digits.isEmpty) return false;
    try {
      await _api.phoneDtmf(digits);
      if (_actionError != null) {
        _actionError = null;
        _safeNotify();
      }
      return true;
    } catch (e) {
      _actionError = _reasonOf(e);
      _safeNotify();
      return false;
    }
  }

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    _safeNotify();
  }

  /// Corre un comando serializado con el resto: dos toques en el botón de
  /// llamar no pueden mandar dos llamadas.
  Future<bool> _command(
    Future<void> Function() run, {
    void Function()? onSent,
  }) async {
    if (_busy) return false;
    _busy = true;
    _actionError = null;
    _safeNotify();
    try {
      await run();
      onSent?.call();
      return true;
    } catch (e) {
      _actionError = _reasonOf(e);
      _clearDialing(notify: false);
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// El motivo tal como lo mandó el backend. Sólo se cae a un genérico cuando
  /// ni siquiera se pudo hablar con la API (timeout, sin red).
  static String _reasonOf(Object e) {
    if (e is PhoneCommandException) return e.reason;
    return 'No se pudo hablar con el teléfono de la casa.';
  }

  String? _contactNumber(String? contactId) {
    if (contactId == null) return null;
    for (final c in _contacts) {
      if (c.id == contactId) return c.number;
    }
    return null;
  }

  void _startDialing(String number) {
    _dialingNumber = number;
    _dialingTimer?.cancel();
    // Red de seguridad: si el `device:state-changed` no llega (socket caído,
    // evento perdido), el placeholder no puede quedarse para siempre diciendo
    // "marcando". A los 30 s se retira y se re-lee el estado real.
    _dialingTimer = Timer(const Duration(seconds: 30), () {
      _clearDialing();
      refresh();
    });
  }

  void _clearDialing({bool notify = true}) {
    _dialingTimer?.cancel();
    _dialingTimer = null;
    if (_dialingNumber == null) return;
    _dialingNumber = null;
    if (notify) _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
