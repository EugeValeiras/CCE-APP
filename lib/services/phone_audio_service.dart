import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phone_call.dart';
import '../models/server_config.dart';
import '../utils/pcm_level.dart';
import 'api_service.dart';

/// Estado del audio de la llamada EN ESTE CELULAR (CCE#12).
enum PhoneAudioState {
  /// Apagado: la voz sale por el jack del HAT, en la casa.
  off,

  /// Pidiendo el micrófono al usuario.
  requesting,

  /// Armando el audio y abriendo el WebSocket.
  connecting,

  /// Tomado. Si además hay llamada, se habla y se escucha por acá.
  on,

  /// Otro dispositivo se lo llevó (gana el último).
  evicted,

  /// El usuario negó el micrófono. La llamada sigue, con el audio en la casa.
  denied,

  /// Cualquier otra falla.
  error,
}

/// Por dónde sale el audio en el celular.
enum PhoneAudioOutput { receiver, speaker, headphones, bluetooth, other }

/// Códigos de cierre del gateway (`phone-audio.gateway.ts`).
const int kAudioCloseUnauthorized = 4401;
const int kAudioCloseBusy = 4409;
const int kAudioCloseEvicted = 4410;
const int kAudioCloseUnavailable = 4404;
const int kAudioCloseEnded = 4000;

/// Jitter buffer de reproducción, en milisegundos. Son los valores medidos del
/// dashboard: más buffer es más tolerancia a la red y más retardo. Sobre datos
/// móviles el jitter es peor que en una LAN — si se escuchan cortes, es el
/// primer número a subir.
const double kJitterTargetMs = 80;
const double kJitterMaxMs = 200;

/// Sin pong hace este tiempo, se deja de mandar micrófono.
///
/// `dart:io` **no expone `bufferedAmount`** (el dashboard sí lo usa para tirar
/// uplink cuando el socket no drena), así que el atraso se detecta por el
/// ping/pong de control que el gateway ya contesta. Es más grueso, pero cubre
/// lo que importa: que una red trabada no acumule una cola de audio que después
/// se escucha corrida hacia atrás para siempre.
const int kUplinkStallMs = 3000;

/// Cómo se lee un cierre del WebSocket. Puro: la pantalla lo muestra tal cual y
/// el test lo verifica sin abrir un socket.
({PhoneAudioState state, String? message}) describeAudioClose(
  int? code,
  String? reason,
) {
  final text = (reason ?? '').trim();
  switch (code) {
    case kAudioCloseEvicted:
      return (
        state: PhoneAudioState.evicted,
        message: text.isEmpty
            ? 'Te sacaron el audio desde otro dispositivo. La llamada sigue.'
            : text,
      );
    case kAudioCloseBusy:
      return (
        state: PhoneAudioState.error,
        message: text.isEmpty
            ? 'Otro dispositivo tiene el audio del teléfono.'
            : text,
      );
    case kAudioCloseUnauthorized:
      return (
        state: PhoneAudioState.error,
        message: 'El servidor no aceptó el token de la app.',
      );
    case kAudioCloseUnavailable:
      return (
        state: PhoneAudioState.error,
        message: text.isEmpty ? 'El servidor no tiene el audio disponible.' : text,
      );
    case kAudioCloseEnded:
    case 1000:
    case null:
      // Fin normal: el servidor soltó la sesión (colgaron, cambió el ruteo) o
      // fuimos nosotros. No hay nada que explicar.
      return (state: PhoneAudioState.off, message: null);
    default:
      return (
        state: PhoneAudioState.error,
        message: text.isEmpty
            ? 'Se cortó la conexión de audio. La llamada sigue, con el audio en '
                'la casa.'
            : text,
      );
  }
}

/// Audio de la llamada del HAT 4G, hablando y escuchando por el celular.
///
/// ## Cómo está partido
///
/// Este servicio es el TRANSPORTE y el estado; el audio de verdad lo maneja
/// Swift (`ios/Runner/PhoneAudioEngine.swift`), que es donde están el
/// `AVAudioSession` en `.voiceChat` —lo que cancela el eco—, el
/// `AVAudioEngine`, el jitter buffer de reproducción y el ruteo auricular /
/// altavoz. Flutter no da audio full-duplex de baja latencia: no hay una
/// versión de esto que viva entera en Dart.
///
/// Los frames del micrófono suben por un **EventChannel** y los de la línea
/// bajan por un **BasicMessageChannel binario**. Un `MethodChannel` por frame
/// sería un round-trip con respuesta 50 veces por segundo, en cada dirección.
///
/// ## Estado, a la manera de esta app
///
/// `ChangeNotifier` + `AnimatedBuilder`, como el resto del repo. Nada de
/// Riverpod/Provider/Bloc.
///
/// ## Lo que NO hace
///
/// No corta llamadas y no cambia el jack. Tomar o soltar el audio sólo cambia
/// por dónde sale la voz: si esto falla entero, la llamada sigue sonando en el
/// teléfono de la casa, que es el respaldo que el backend deja siempre armado.
class PhoneAudioService extends ChangeNotifier {
  PhoneAudioService({required ServerConfig config})
      : _config = config,
        _api = ApiService(config);

  final ServerConfig _config;
  final ApiService _api;

  /// Canales nativos (`ios/Runner/PhoneAudioPlugin.swift`).
  static const MethodChannel _control = MethodChannel('com.cce.phoneaudio');
  static const EventChannel _events = EventChannel('com.cce.phoneaudio/events');
  static const BasicMessageChannel<ByteData?> _downlink =
      BasicMessageChannel<ByteData?>(
    'com.cce.phoneaudio/downlink',
    BinaryCodec(),
  );

  PhoneAudioState _state = PhoneAudioState.off;
  String? _error;
  PhoneAudioOutput _output = PhoneAudioOutput.receiver;
  bool _speaker = false;
  bool _muted = false;
  bool _disposed = false;

  final LevelMeter _inputMeter = LevelMeter();
  final LevelMeter _outputMeter = LevelMeter();

  /// Milisegundos en el jitter buffer nativo, y muestras tiradas por atraso.
  int _bufferedMs = 0;
  int _dropped = 0;

  /// Ida y vuelta al servidor, medido con el ping de control. `null` hasta el
  /// primer pong.
  int? _rttMs;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<dynamic>? _nativeSub;
  Timer? _levelTimer;
  Timer? _pingTimer;
  int _lastPongAt = 0;
  bool _uplinkStalled = false;

  /// ¿Había una llamada viva la última vez que la pantalla nos contó?
  bool _wasLive = false;

  PhoneAudioState get state => _state;
  String? get error => _error;
  PhoneAudioOutput get output => _output;
  bool get speakerOn => _speaker;
  bool get muted => _muted;
  double get inputLevel => _inputMeter.value;
  double get outputLevel => _outputMeter.value;
  int get bufferedMs => _bufferedMs;
  int get droppedSamples => _dropped;
  int? get rttMs => _rttMs;

  /// ¿El audio está en ESTE celular ahora mismo?
  bool get isOn => _state == PhoneAudioState.on;

  /// ¿Hay algo en curso que conviene no interrumpir con otro toque?
  bool get busy =>
      _state == PhoneAudioState.requesting ||
      _state == PhoneAudioState.connecting;

  /// Qué decir del estado, en castellano y corto.
  String get stateLabel {
    switch (_state) {
      case PhoneAudioState.on:
        return 'En el celular';
      case PhoneAudioState.requesting:
        return 'Pidiendo micrófono…';
      case PhoneAudioState.connecting:
        return 'Conectando…';
      case PhoneAudioState.evicted:
        return 'Te lo sacaron';
      case PhoneAudioState.denied:
        return 'Sin micrófono';
      case PhoneAudioState.error:
        return 'Error';
      case PhoneAudioState.off:
        return 'En la casa';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Tomar y soltar ────────────────────────────────────────────────────────

  /// Trae el audio de la llamada a este celular.
  ///
  /// El orden importa y es el mismo que el del dashboard: **primero el
  /// micrófono**, porque si el usuario lo niega no tiene sentido haber abierto
  /// un socket ni haber movido el ruteo del servidor; después el WebSocket; y
  /// recién al final el `audio-route: web`, que es lo que hace que el módem
  /// mande el PCM por USB.
  ///
  /// Devuelve `false` sin tirar: cualquier fallo deja la llamada viva con el
  /// audio en la casa, y el motivo en [error].
  Future<bool> take() async {
    if (_state == PhoneAudioState.on || busy) return _state == PhoneAudioState.on;
    _error = null;
    _state = PhoneAudioState.requesting;
    _notify();

    final Map<Object?, Object?>? started;
    try {
      started = await _control.invokeMapMethod<Object?, Object?>('start', {
        'targetMs': kJitterTargetMs,
        'maxMs': kJitterMaxMs,
      });
    } on PlatformException catch (e) {
      return _fail(PhoneAudioState.error,
          e.message ?? 'No se pudo iniciar el audio en el celular.');
    } on MissingPluginException {
      return _fail(
        PhoneAudioState.error,
        'Esta versión de la app no trae el audio en el celular.',
      );
    }

    if (started?['granted'] != true) {
      return _fail(
        PhoneAudioState.denied,
        'No diste permiso para usar el micrófono. La llamada sigue: el audio '
        'sale por el teléfono de la casa. Podés darlo en Ajustes › CCE Home.',
      );
    }
    _output = _parseOutput(started?['output']);
    _speaker = _output == PhoneAudioOutput.speaker;
    _muted = false;
    _listenNative();

    _state = PhoneAudioState.connecting;
    _notify();
    try {
      await _connect();
    } catch (e) {
      return _fail(PhoneAudioState.error, _connectError(e));
    }

    // Recién ahora se mueve el ruteo del módem. Que esto falle NO invalida la
    // sesión: el audio ya está tomado y el servidor lo prende solo en cuanto el
    // ruteo quede en 'web' (el dashboard puede haberlo dejado ahí).
    try {
      await _api.phoneAudioRoute('web');
    } catch (e) {
      _error = 'El audio está tomado, pero el teléfono de la casa no aceptó '
          'mandarlo por acá: ${e is PhoneCommandException ? e.reason : e}';
    }

    // Mientras se movía el ruteo nos pudieron desalojar (gana el último): el
    // socket ya no está y ponerse en 'on' sería mentir.
    if (_ws == null) {
      _notify();
      return false;
    }

    _state = PhoneAudioState.on;
    _startMeters();
    _notify();
    return true;
  }

  /// Suelta el audio y lo devuelve a la casa. No toca la llamada.
  Future<void> release() async {
    await _teardown();
    if (_state != PhoneAudioState.denied && _state != PhoneAudioState.evicted) {
      _state = PhoneAudioState.off;
    }
    _notify();
  }

  /// Altavoz o auricular, en caliente.
  ///
  /// Con auriculares o manos libres conectados el nativo IGNORA el pedido: no
  /// se le saca el audio de la oreja a nadie sin que lo haya pedido. Por eso el
  /// valor que vale es el que devuelve el nativo, no el que se pidió.
  Future<void> setSpeaker(bool value) async {
    _speaker = value;
    _notify();
    try {
      final result = await _control.invokeMethod<String>(
        'setSpeaker',
        {'speaker': value},
      );
      _output = _parseOutput(result);
      _speaker = _output == PhoneAudioOutput.speaker;
    } catch (_) {
      // Que no se pueda mover la salida no puede tirar la llamada abajo.
    }
    _notify();
  }

  /// Silencia el micrófono sin soltar la sesión ni cortar lo que se escucha.
  Future<void> setMuted(bool value) async {
    _muted = value;
    _notify();
    try {
      await _control.invokeMethod<void>('setMuted', {'muted': value});
    } catch (_) {
      // Idem: el estado de la UI ya cambió y el audio sigue.
    }
  }

  void clearError() {
    if (_error == null &&
        _state != PhoneAudioState.error &&
        _state != PhoneAudioState.denied &&
        _state != PhoneAudioState.evicted) {
      return;
    }
    _error = null;
    if (_state == PhoneAudioState.error ||
        _state == PhoneAudioState.denied ||
        _state == PhoneAudioState.evicted) {
      _state = PhoneAudioState.off;
    }
    _notify();
  }

  /// La pantalla informa si hay una llamada viva.
  ///
  /// Al TERMINAR una llamada el audio se suelta solo. En el dashboard la sesión
  /// queda tomada entre llamadas, pero un celular con el micrófono abierto y el
  /// punto naranja prendido después de colgar es otra cosa: se suelta, y quien
  /// quiera volver a hablar lo toma de nuevo.
  ///
  /// Tomarlo ANTES de discar sigue siendo válido: esto sólo actúa en el borde
  /// de bajada.
  void syncWithCall(bool live) {
    if (_wasLive && !live && _state == PhoneAudioState.on) {
      unawaited(release());
    }
    _wasLive = live;
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  /// URL del gateway binario. `baseUrl` ya trae el `/api`.
  Uri get wsUri =>
      Uri.parse('${_config.baseUrl}/phone/audio'.replaceFirst('http', 'ws'));

  Future<void> _connect() async {
    // El token va por **header**, que es lo que un navegador no puede hacer y
    // por lo que existe el subprotocolo `cce-token.<token>` del dashboard. El
    // `X-CCE-Client` de siempre es lo que le dice al servidor que el que se
    // conecta es la app, para que el desalojado lea desde dónde se lo sacaron.
    final ws = await WebSocket.connect(
      wsUri.toString(),
      headers: ServerConfig.tokenHeaders,
    ).timeout(const Duration(seconds: 10));
    _ws = ws;
    _lastPongAt = DateTime.now().millisecondsSinceEpoch;
    _uplinkStalled = false;
    _wsSub = ws.listen(
      _onWsData,
      onDone: () => _onWsClosed(ws.closeCode, ws.closeReason),
      // Código propio: un `null` se leería como "cierre limpio" y este no lo
      // es — el socket se rompió y el usuario tiene que enterarse.
      onError: (Object e) => _onWsClosed(-1, 'Se cortó el audio: $e'),
      cancelOnError: false,
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _ping());
  }

  void _onWsData(dynamic data) {
    if (data is List<int>) {
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      _outputMeter.add(bytes);
      // Derecho al jitter buffer nativo: acá no se acumula nada, porque la cola
      // que importa es la que alimenta el render de audio.
      unawaited(_downlink.send(ByteData.sublistView(bytes)));
      return;
    }
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return; // control ilegible: no es motivo para tirar el audio
    }
    switch (msg['type']) {
      case 'pong':
        final sent = (msg['t'] as num?)?.toInt();
        _lastPongAt = DateTime.now().millisecondsSinceEpoch;
        _uplinkStalled = false;
        if (sent != null) _rttMs = _lastPongAt - sent;
        break;
      case 'error':
        final reason = (msg['reason'] ?? '').toString();
        if (reason.isNotEmpty) _error = reason;
        _notify();
        break;
    }
  }

  void _onWsClosed(int? code, String? reason) {
    if (_ws == null) return; // ya lo cerramos nosotros desde `_teardown`
    final verdict = describeAudioClose(code, reason);
    _error = verdict.message;
    unawaited(_teardown().then((_) {
      _state = verdict.state;
      _notify();
    }));
  }

  /// Ping de control: mide el ida y vuelta y, sobre todo, detecta que la red se
  /// trabó. Ver [kUplinkStallMs].
  void _ping() {
    final ws = _ws;
    if (ws == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPongAt > kUplinkStallMs && !_uplinkStalled) {
      _uplinkStalled = true;
      _notify();
    }
    try {
      ws.add(jsonEncode({'type': 'ping', 't': now}));
    } catch (_) {
      // Un socket que ya murió va a avisar por `onDone`.
    }
  }

  // ── Canal nativo ──────────────────────────────────────────────────────────

  void _listenNative() {
    _nativeSub?.cancel();
    _nativeSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object e) {
        _error = 'El audio del celular falló: $e';
        _notify();
      },
    );
  }

  void _onNativeEvent(dynamic event) {
    // Un frame del micrófono llega como bytes; todo lo demás, como mapa.
    if (event is Uint8List) {
      _inputMeter.add(event);
      final ws = _ws;
      if (ws == null || _uplinkStalled) return;
      try {
        ws.add(event);
      } catch (_) {
        // Socket muerto: `onDone` se encarga.
      }
      return;
    }
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);
    switch (map['type']) {
      case 'output':
        _output = _parseOutput(map['value']);
        _speaker = _output == PhoneAudioOutput.speaker;
        _notify();
        break;
      case 'stats':
        _bufferedMs = (map['bufferedMs'] as num?)?.toInt() ?? 0;
        _dropped = (map['dropped'] as num?)?.toInt() ?? 0;
        break;
      case 'interruption':
        _onInterruption(map['began'] == true, map['resumed'] == true);
        break;
      case 'failure':
        _error = (map['message'] ?? 'Falló el audio del celular.').toString();
        _notify();
        break;
    }
  }

  /// Una llamada telefónica DE VERDAD al celular, Siri o una alarma.
  ///
  /// Mientras dura, el audio de la llamada de la casa no suena — no hay forma
  /// de evitarlo, iOS le da la sesión a quien interrumpió. Lo que sí se puede
  /// es no quedar en un estado mentiroso: si el sistema deja volver, se vuelve;
  /// si no, se suelta y la voz se queda en la casa, dicho con todas las letras.
  void _onInterruption(bool began, bool resumed) {
    if (began) {
      _error = 'El celular interrumpió el audio (una llamada, Siri o una '
          'alarma). Mientras tanto la voz sale por el teléfono de la casa.';
      _notify();
      return;
    }
    if (resumed) {
      _error = null;
      _notify();
      return;
    }
    _error = 'No se pudo recuperar el audio después de la interrupción. La '
        'llamada sigue, con el audio en la casa.';
    unawaited(_teardown().then((_) {
      _state = PhoneAudioState.error;
      _notify();
    }));
  }

  // ── Interno ───────────────────────────────────────────────────────────────

  void _startMeters() {
    _levelTimer?.cancel();
    // 100 ms: el mismo ritmo que reportan los worklets del dashboard. Más lento
    // se ve a saltos; más rápido no aporta nada al ojo.
    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _inputMeter.tick();
      _outputMeter.tick();
      _notify();
    });
  }

  Future<bool> _fail(PhoneAudioState state, String message) async {
    await _teardown();
    _state = state;
    _error = message;
    _notify();
    return false;
  }

  /// Suelta TODO. Idempotente: se llama desde varios caminos de error.
  Future<void> _teardown() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _inputMeter.reset();
    _outputMeter.reset();
    _bufferedMs = 0;
    _rttMs = null;
    _uplinkStalled = false;
    _muted = false;

    final ws = _ws;
    _ws = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await ws?.close(1000, 'el usuario soltó el audio');
    } catch (_) {
      // Un socket que ya se estaba cerrando no es un problema.
    }

    await _nativeSub?.cancel();
    _nativeSub = null;
    try {
      // Esto es lo que apaga el micrófono y devuelve la sesión de audio al
      // sistema: dejar el punto naranja prendido con el teléfono colgado es
      // inaceptable.
      await _control.invokeMethod<void>('stop');
    } catch (_) {
      // Sin plugin (o ya parado) no hay nada que soltar.
    }
  }

  static PhoneAudioOutput _parseOutput(Object? raw) {
    switch (raw) {
      case 'speaker':
        return PhoneAudioOutput.speaker;
      case 'headphones':
        return PhoneAudioOutput.headphones;
      case 'bluetooth':
        return PhoneAudioOutput.bluetooth;
      case 'receiver':
        return PhoneAudioOutput.receiver;
      default:
        return PhoneAudioOutput.other;
    }
  }

  static String _connectError(Object e) {
    if (e is TimeoutException) {
      return 'El servidor de la casa no contestó a tiempo.';
    }
    if (e is WebSocketException || e is SocketException) {
      return 'No se pudo conectar el audio con la casa: ${e.toString()}';
    }
    return 'No se pudo conectar el audio: $e';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    super.dispose();
  }
}
