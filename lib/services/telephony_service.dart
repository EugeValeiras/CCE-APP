import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/phone_call.dart';
import '../models/phone_sms.dart';
import '../models/server_config.dart';
import 'api_service.dart';
import 'phone_audio_service.dart';
import 'socket_service.dart';

/// Id canónico del teléfono 4G en /merged. Emite `device:state-changed` con el
/// estado de la llamada en vivo; el historial va por `phone:call-state`.
const String kPhoneDeviceId = 'dev_phone';

/// Estado, historial y comandos de la telefonía 4G (HAT SIM7600G-H).
///
/// La app DISCA (issue #10) y desde el #12 también **lleva el audio**: se habla
/// y se escucha por el celular. Esa parte vive en [audio], que es un servicio
/// aparte porque es otra cosa —un WebSocket binario y código nativo de iOS—,
/// pero cuelga de acá porque su ciclo de vida es el del teléfono: tiene que
/// sobrevivir a que se cierre la pantalla y morir con el shell.
///
/// Mientras el audio NO esté tomado por esta app, sigue valiendo el aviso del
/// #10: la voz sale por el jack del HAT o por el navegador del dashboard, y hay
/// que decirlo — ver [PhoneStatus.audioNotice].
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

  /// [api] se inyecta SÓLO en tests, para probar [refresh] sin red: en la app
  /// se arma de [config].
  TelephonyService({
    required ServerConfig config,
    required SocketService socket,
    this.reloadPhoneDevice,
    ApiService? api,
  })  : _api = api ?? ApiService(config),
        _socket = socket,
        audio = PhoneAudioService(config: config);

  /// Re-lee `dev_phone` del backend y lo pisa donde la pantalla lo lee
  /// (DevicesService). Lo pone el shell; acá no se conoce ese servicio. Se usa
  /// una sola vez: cuando el placeholder de "marcando" expira sin que haya
  /// llegado el estado (CCE#19) — ver [_onDialingExpired].
  final Future<Device?> Function()? reloadPhoneDevice;

  /// El audio de la llamada en ESTE celular (CCE#12). Ver [PhoneAudioService].
  final PhoneAudioService audio;

  PhoneStatus _status = const PhoneStatus();
  List<PhoneCall> _calls = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  /// Llamada entrante sonando AHORA (para la card de la pantalla). Lo arma el
  /// `phone:call-state` de `incoming` y lo retira **cualquiera** de las vías
  /// por las que la app se entera de que dejó de sonar (CCE#21):
  ///
  ///  - el `phone:call-state` de fin;
  ///  - el `device:state-changed` de `dev_phone` a un estado que no sea
  ///    `ringing` (terminó, o la atendieron desde otro lado);
  ///  - la re-lectura de `/phone/status` en [refresh], tras reconectar.
  ///
  /// Los tres pasan por [_clearIncoming], que es idempotente: pueden llegar en
  /// cualquier orden, o uno solo. Hasta este fix colgaba del primero nada más,
  /// y si ese evento se perdía —app en segundo plano, socket reconectando— la
  /// card quedaba pegada con Rechazar/Atender sobre una llamada que ya no
  /// existía. Mismo patrón que CCE#19: un estado que dependía de un único
  /// evento sin red de seguridad.
  Map<String, dynamic>? _incoming;

  /// Perdidas nuevas desde la última vez que se abrió el historial. Alimenta el
  /// badge de la card: una perdida es el aviso de último recurso de la casa.
  int _unseenMissed = 0;

  /// SMS recibidos (CCE#23), del más nuevo al más viejo. Seed por `GET
  /// /phone/sms` y de ahí en más entran por el socket `phone:sms`.
  List<PhoneSms> _sms = const [];

  /// SMS nuevos desde la última vez que se abrió [SmsScreen]. Mismo criterio
  /// que [_unseenMissed]: es un contador de la app, no un estado del servidor
  /// — el issue lo pide "como el contador de perdidas no vistas".
  int _unseenSms = 0;

  /// Libreta del backend. Se carga bajo demanda (nadie la necesita hasta que se
  /// abre la pantalla del teléfono) y se cachea: el ABM es del dashboard, así
  /// que no cambia sola mientras la app está abierta.
  List<PhoneContact> _contacts = const [];
  bool _contactsLoaded = false;

  /// Motivo del último comando rechazado, tal como lo redactó el backend
  /// ("hay una llamada en curso", "rate limit de llamadas por hora alcanzado").
  /// La pantalla lo muestra sin reemplazarlo: un genérico haría que el usuario
  /// reintente contra un límite que no va a ceder. También lleva el aviso de
  /// que una llamada no se pudo confirmar ([_onDialingExpired]).
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
  StreamSubscription<PhoneSmsEvent>? _smsSub;
  StreamSubscription<DeviceStateEvent>? _deviceSub;
  StreamSubscription<bool>? _connSub;

  /// El socket ya estuvo conectado alguna vez: el próximo `connected` es una
  /// RE-conexión y hay que re-sincronizar. Se compara contra esto y no contra
  /// "el último valor fue conectado": el socket avisa `true` → `false` →
  /// `true`, y con el último valor la reconexión evaluaba `true && false` y el
  /// refresh de acá abajo no corría nunca (encontrado en CCE#21).
  bool _everConnected = false;

  PhoneStatus get status => _status;
  List<PhoneCall> get calls => _calls;
  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get incoming => _incoming;
  int get unseenMissed => _unseenMissed;
  List<PhoneSms> get sms => _sms;
  int get unseenSms => _unseenSms;

  /// Todo lo que hay para ver sin entrar: perdidas y SMS. Es lo que muestra
  /// la card de la home.
  int get unseenTotal => _unseenMissed + _unseenSms;
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
    _smsSub?.cancel();
    _deviceSub?.cancel();
    _connSub?.cancel();
    refresh();

    // El estado EN VIVO de la llamada viaja por `device:state-changed` sobre
    // `dev_phone`, no por `phone:call-state`. Acá se lo usa para retirar lo
    // que este servicio sostiene por su cuenta —el placeholder de "marcando" y
    // la card de la entrante—: el estado que pinta la pantalla sale de
    // DevicesService, y duplicarlo sería tener dos verdades.
    _deviceSub = _socket.onDeviceChanged.listen((event) {
      if (event.deviceId != kPhoneDeviceId) return;
      final state = (event.state?['callState'] ?? '').toString();
      if (state.isEmpty) return;
      // El audio del celular se suelta solo cuando la llamada termina. Va acá y
      // no en la pantalla porque tiene que pasar igual con la app en segundo
      // plano o con el teléfono cerrado: un micrófono abierto después de colgar
      // es exactamente lo que nadie quiere en su celular.
      audio.syncWithCall(state != 'idle' && state != 'ended');
      // La entrante vive mientras el device diga que SUENA. Cualquier otro
      // estado la retira: `ended`/`idle` porque terminó, `active` porque la
      // atendieron desde otro lado (dashboard, el HAT). Es la segunda fuente
      // del fin de la llamada, y hasta CCE#21 este listener la ignoraba: si el
      // `phone:call-state` de fin se perdía, la card quedaba pegada.
      if (state != 'ringing') _clearIncoming();
      // El placeholder de "marcando" NO se retira con un fin: el `idle` de la
      // llamada anterior puede llegar con el `ATD` de la nueva en vuelo, y
      // soltarlo ahí dejaría la pantalla quieta después de tocar Llamar.
      if (state == 'idle' || state == 'ended') return;
      _clearDialing();
    });

    _callSub = _socket.onCallState.listen((event) {
      if (event.isIncoming) {
        _incoming = event.payload;
        _safeNotify();
        return;
      }
      // 'ended': cae la card y la llamada entra al historial en el acto, sin
      // volver a pedirlo al servidor. El historial y el contador NO dependen
      // de que la card siguiera montada: si el device ya la retiró, la
      // perdida entra igual.
      _clearIncoming(notify: false);
      _clearDialing(notify: false);
      audio.syncWithCall(false);
      final call = PhoneCall.fromJson(event.payload);
      _calls = [call, ..._calls].take(200).toList();
      if (call.isMissed) _unseenMissed++;
      _safeNotify();
    });

    // Un SMS entra al historial en el acto y suma al contador. Se deduplica
    // por id: tras una reconexión el `refresh()` vuelve a pedir la lista y el
    // mismo mensaje puede llegar por las dos vías.
    _smsSub = _socket.onSms.listen((event) {
      final sms = PhoneSms.fromJson(event.payload);
      if (sms.id.isEmpty || _sms.any((s) => s.id == sms.id)) return;
      _sms = [sms, ..._sms].take(200).toList();
      _unseenSms++;
      _safeNotify();
    });

    // Tras una RE-conexión pudimos perder eventos: re-sincronizar. En la
    // conexión inicial no hace falta (el seed de arriba ya corrió). Si el
    // socket ya estaba conectado al arrancar, su primer `true` ya pasó y el
    // próximo es una reconexión.
    _everConnected = _socket.isConnected;
    _connSub = _socket.onConnectionChanged.listen((connected) {
      if (!connected) return;
      if (_everConnected) refresh();
      _everConnected = true;
    });
  }

  void stop() {
    _callSub?.cancel();
    _callSub = null;
    _smsSub?.cancel();
    _smsSub = null;
    _deviceSub?.cancel();
    _deviceSub = null;
    _connSub?.cancel();
    _connSub = null;
    _dialingTimer?.cancel();
    _dialingTimer = null;
  }

  /// Re-lee estado e historial. Nunca tira: un teléfono que no responde deja la
  /// pantalla en su último estado conocido con el error a la vista.
  ///
  /// También re-deriva la entrante del estado real (CCE#21): es la
  /// re-sincronización que corre tras reconectar el socket, o sea el momento en
  /// que es más probable que se haya perdido el evento de fin.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _safeNotify();
    // Lo que había al PEDIR el snapshot. Si mientras el GET viajaba llegó una
    // entrante por el socket, es más nueva que la respuesta y no se la pisa.
    final incomingBefore = _incoming;
    try {
      final results = await Future.wait([
        _api.getPhoneStatus(),
        _api.getPhoneCalls(),
      ]);
      _status = results[0] as PhoneStatus;
      _calls = results[1] as List<PhoneCall>;
      _error = null;
      _reconcileIncoming(_status, before: incomingBefore);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _safeNotify();
    }
    await _refreshSms();
  }

  /// Los SMS se piden aparte del estado y las llamadas: un `GET /phone/sms`
  /// que falle (backend viejo sin el endpoint, store apagado) no puede dejar
  /// el teléfono entero "sin conexión".
  Future<void> _refreshSms() async {
    try {
      final fresh = await _api.getPhoneSms();
      // Lo que entró por el socket mientras el GET viajaba es más nuevo que
      // la respuesta: se conserva adelante, sin repetir.
      final ids = fresh.map((s) => s.id).toSet();
      final newer = _sms.where((s) => !ids.contains(s.id)).toList();
      _sms = [...newer, ...fresh].take(200).toList();
      _safeNotify();
    } catch (_) {
      // El seed de SMS es una comodidad: sin él el resto del teléfono sigue.
    }
  }

  /// Marca las perdidas como vistas (al abrir la pantalla del teléfono).
  void markMissedSeen() {
    if (_unseenMissed == 0) return;
    _unseenMissed = 0;
    _safeNotify();
  }

  /// Marca los SMS como vistos (al abrir la pantalla de mensajes).
  void markSmsSeen() {
    if (_unseenSms == 0) return;
    _unseenSms = 0;
    _safeNotify();
  }

  void dismissIncoming() => _clearIncoming();

  /// Retira la card de la entrante. Idempotente a propósito: la llaman las
  /// tres vías por las que la app se entera de que dejó de sonar (ver
  /// [_incoming]) y pueden correr en cualquier orden, o una sola.
  void _clearIncoming({bool notify = true}) {
    if (_incoming == null) return;
    _incoming = null;
    if (notify) _safeNotify();
  }

  /// Alinea la entrante con el snapshot de `/phone/status`: si dice que suena
  /// una entrante, hay card (la que había, o una armada del snapshot si el
  /// aviso del socket se perdió); si no, no la hay.
  ///
  /// Sólo toca lo que había al pedir el snapshot ([before]): una entrante que
  /// entró por el socket mientras el GET viajaba —o una que el device retiró
  /// en ese mismo lapso— es más nueva que la respuesta y manda ella.
  void _reconcileIncoming(PhoneStatus status, {Map<String, dynamic>? before}) {
    if (!identical(_incoming, before)) return;
    if (!status.ringingIn) {
      _incoming = null;
      return;
    }
    _incoming ??= <String, dynamic>{
      'event': 'incoming',
      'direction': 'in',
      'number': status.callNumber ?? '',
      if (status.callContactId != null) 'contactId': status.callContactId,
      if (status.callContactName != null) 'contactName': status.callContactName,
    };
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
  /// CUESTA PLATA y suena del otro lado de verdad. Dónde se escucha depende de
  /// si el audio está tomado por [audio]: si no lo está, se queda en la casa.
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
          _clearIncoming(notify: false);
          _clearDialing(notify: false);
        },
      );

  /// Atiende la entrante que suena. El audio va a donde esté el ruteo: a la
  /// casa, o a este celular si [audio] lo tiene tomado.
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
    _dialingTimer = Timer(const Duration(seconds: 30), _onDialingExpired);
  }

  /// Pasaron 30 s desde el "Llamar" sin que llegara el estado del device. Hay
  /// dos formas de que pase: el evento se perdió (socket caído) y la llamada
  /// está viva, o la llamada no existe. Se retira el placeholder y se re-lee
  /// la verdad en sus DOS fuentes —el device que pinta la pantalla y el seed
  /// propio— para quedar en un estado honesto: la card si está viva, y si no,
  /// reposo CON el aviso de que no se confirmó. Volver a reposo en silencio
  /// era lo que hacía que CCE#19 pareciera intermitente.
  Future<void> _onDialingExpired() async {
    _clearDialing();
    final deviceRead = reloadPhoneDevice?.call();
    final statusRead = refresh();
    final device = await deviceRead;
    await statusRead;
    if (_disposed) return;
    final live = device != null
        ? device.phoneInCall
        : (status.callState != 'idle' && status.callState != 'ended');
    if (live) return;
    _actionError = device == null && _error != null
        ? 'No se pudo confirmar el estado de la llamada.'
        : 'La llamada no se pudo confirmar: el teléfono de la casa figura libre.';
    _safeNotify();
  }

  /// SÓLO TESTS: arma el placeholder de "marcando" sin mandar el POST, para
  /// poder probar qué pasa cuando expira.
  @visibleForTesting
  void debugStartDialing(String number) => _startDialing(number);

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
    // Soltar el audio apaga el micrófono y devuelve la sesión al sistema. Que
    // quede prendido después de cerrar la app es inaceptable.
    audio.dispose();
    super.dispose();
  }
}
