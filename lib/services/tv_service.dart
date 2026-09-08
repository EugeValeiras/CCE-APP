import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import '../models/tv_status.dart';
import '../models/server_config.dart';
import 'api_service.dart';
import 'socket_service.dart';

/// Id canónico del televisor histórico en /merged (F8/F13): emite
/// device:state-changed al socket con deltas parciales
/// (on/volume/muted/mediaInput/mediaState/mediaApp/mediaChannel).
///
/// CCE#45 — ya NO es el único: cada Samsung emite bajo el suyo (`dev_tv-<...>`).
/// Éste sigue siendo el del televisor de siempre y el fallback mientras la lista
/// de aparatos no cargó.
const String kTvDeviceId = 'dev_tv';

/// Tope del control de volumen del TV: 0-100, escala nativa de SmartThings/
/// Tizen (a diferencia del JBL, acá NO hay reescalado de display).
const int kTvVolMax = 100;

/// Allowlist de ids del remote del TV (espejo del enum compartido del backend).
/// La app SOLO manda estos ids en POST /tv/remote {key}; qué transporte resuelve
/// cada tecla (cloud SmartThings vs Tizen local) lo decide el backend.
abstract final class TvRemoteKeys {
  static const String up = 'up';
  static const String down = 'down';
  static const String left = 'left';
  static const String right = 'right';
  static const String ok = 'ok';
  static const String back = 'back';
  static const String home = 'home';
  static const String menu = 'menu';
  static const String exit = 'exit';
  static const String power = 'power';
  static const String volumeUp = 'volumeUp';
  static const String volumeDown = 'volumeDown';
  static const String mute = 'mute';
  static const String channelUp = 'channelUp';
  static const String channelDown = 'channelDown';
  static const String hdmi = 'hdmi';
  static const String play = 'play';
  static const String pause = 'pause';
  static const String stop = 'stop';

  /// Teclas numéricas: digit0..digit9. Helper para construir el id sin typos.
  static String digit(int n) => 'digit${n.clamp(0, 9)}';
}

/// AppIds canónicos de las apps lanzables (espejo de GET /tv/apps). Los botones
/// de app de la UI mapean a estos; 'www'/browser puede no tener appId.
abstract final class TvApps {
  static const String netflix = 'netflix';
  static const String max = 'max'; // HBO Max
  static const String prime = 'prime'; // Prime Video
  static const String youtube = 'youtube';
}

/// A qué punto llegó la resolución del aparato que la pantalla quiere mostrar.
enum _TargetState {
  /// Se sabe cuál es: o está en la lista, o nadie nombró aparato y manda el
  /// que el backend elija.
  resolved,

  /// Se pidió por device canónico y la lista de aparatos todavía no llegó.
  pending,

  /// Se pidió y NO se pudo resolver: la lista no lo tiene, o no se pudo leer.
  /// No se cae al aparato por defecto — cada tecla iría al Samsung equivocado.
  unresolved,
}

/// Qué Samsung tiene que mostrar la pantalla, en UNA pieza inmutable.
///
/// Todo lo que sale a la red captura este valor antes de irse y lo compara al
/// volver. Antes la misma pregunta estaba repartida en siete campos sueltos —el
/// elegido, el pendiente, el que faltaba, dos épocas y dos contadores de
/// requests— que había que mover juntos y a mano; cada vuelta de review
/// encontraba un subconjunto actualizado a medias, y ése era el bug. Con una
/// sola pieza, "esta respuesta es para el aparato que quiero" no se puede
/// actualizar a medias (CCE#130).
@immutable
class _TvTarget {
  const _TvTarget({
    required this.seq,
    required this.deviceId,
    required this.state,
  });

  static const inicial =
      _TvTarget(seq: 0, deviceId: null, state: _TargetState.resolved);

  /// Monótono: cada cambio de destino saca uno nuevo. Descarta la respuesta de
  /// un destino anterior aunque el aparato haya vuelto a ser el mismo.
  final int seq;

  /// Device canónico pedido (`dev_tv-ce588d39`), o null si nadie nombró aparato.
  final String? deviceId;

  final _TargetState state;

  bool get isResolved => state == _TargetState.resolved;

  /// ¿Es EXACTAMENTE este destino? Lo usa lo que vuelve de /tv/status: un
  /// estado viejo del mismo aparato tampoco sirve.
  bool sameAs(_TvTarget other) => seq == other.seq;

  /// ¿Se sigue queriendo este aparato? Más laxo que [sameAs] a propósito: una
  /// lista de aparatos que llega sirve para resolver el mismo device sin
  /// importar cuántos intentos hubo en el medio. Comparando el número de pedido
  /// en vez del aparato, el cartel de error quedaba pegado con la lista buena
  /// ya en memoria.
  bool wants(String? device) => deviceId == device;

  _TvTarget next({required String? deviceId, required _TargetState state}) =>
      _TvTarget(seq: seq + 1, deviceId: deviceId, state: state);
}

/// Estado del Samsung TV con PUSH por socket (F13). dev_tv emite
/// device:state-changed con deltas parciales; el service hace un SEED inicial
/// (getTvStatus, que además trae inputs/modos/disabled que el socket NO emite) y
/// luego escucha el socket — sin Timer.periodic.
///
/// El shell (tablet/phone) posee el ciclo: [startPolling] hace el seed +
/// suscripción, [stopPolling] cancela la suscripción (nombres conservados para
/// no tocar los call-sites). La screen NO arranca nada en su initState.
///
/// Separación `_error` vs `online:false` (idéntica a JblService):
///  - `_error != null` ⟺ excepción real del propio getTvStatus (red caída /
///    API CCE down / timeout).
///  - `status.online == false` con `_error == null` ⟺ el backend respondió pero
///    el TV está apagado/inalcanzable (cloud reporta offline o Tizen no
///    responde). GET /tv/status NUNCA tira por TV inalcanzable.
class TvService extends ChangeNotifier {
  final ApiService _api;
  final SocketService _socket;

  /// [api] se inyecta SÓLO en tests, para probar la selección y las carreras
  /// de [refresh] sin red; en la app se construye del config.
  TvService({
    required ServerConfig config,
    required SocketService socket,
    ApiService? api,
  })  : _api = api ?? ApiService(config),
        _socket = socket;

  TvStatus? _status;
  bool _loading = false;
  String? _error;

  /// Segunda línea del cartel de error. Los motivos por los que la pantalla se
  /// queda sin control no son el mismo: "no hay red" se reintenta solo, "ese
  /// aparato ya no está" se arregla en el Dashboard.
  String? _errorDetail;

  // ── Varios Samsung (CCE#45) ────────────────────────────────────────────────
  // `_status` es SIEMPRE el del aparato SELECCIONADO, que desde CCE#130 lo
  // nombra quien abre el control ([selectDevice]) y no un selector adentro de
  // la pantalla. La lista puede quedar vacía (backend viejo sin GET /tv/tvs):
  // ahí los comandos van sin `?tv=` y el socket se filtra por `dev_tv` —
  // exactamente el comportamiento anterior a esta feature.
  List<TvSummary> _tvs = const [];

  /// Qué aparato tiene que mostrar la pantalla y en qué estado está su
  /// resolución. ÚNICA fuente: lo cambia sólo [_retarget].
  _TvTarget _target = _TvTarget.inicial;

  /// GET /tv/tvs en vuelo, compartido por quien no necesita una lista recién
  /// pedida (las cards de la home): tres cards montándose eran tres requests.
  /// No es identidad, es coalescencia — por eso no vive en el token.
  Future<void>? _tvsInFlight;

  /// El aparato pedido no está y no se puede comandar otro en su lugar.
  bool get missingDevice => _target.state == _TargetState.unresolved;

  /// Cambia el destino. ÚNICO lugar que toca [_target], para que el estado
  /// asociado —el status que deja de valer y el cartel de error que deja de
  /// aplicar— no pueda quedar a medio actualizar.
  void _retarget(
    _TvTarget next, {
    bool keepStatus = false,
    String? error,
    String? errorDetail,
  }) {
    _target = next;
    if (!keepStatus) _status = null;
    _error = error;
    _errorDetail = errorDetail;
    _safeNotify();
  }

  List<TvSummary> get tvs => _tvs;

  /// El aparato que la pantalla muestra, o null si todavía no se sabe cuál es
  /// (la lista no llegó, o el pedido no se pudo resolver).
  TvSummary? get selectedTv {
    if (_tvs.isEmpty) return null;
    final wanted = _target.deviceId;
    if (wanted != null) {
      for (final t in _tvs) {
        if (t.canonicalDeviceId == wanted) return t;
      }
      // Se pidió un aparato y la lista no lo tiene: NO se cae al principal.
      return null;
    }
    for (final t in _tvs) {
      if (t.isDefault) return t;
    }
    return _tvs.first;
  }

  /// Id para `?tv=` (null ⇒ el backend usa su aparato por defecto).
  String? get selectedTvId => selectedTv?.id;

  /// Device canónico del que se muestra: por dónde llegan SUS eventos del
  /// socket. Con un aparato pedido y sin resolver, ése — no el histórico, que
  /// haría pasar por propios los eventos de otro.
  String get selectedDeviceId =>
      selectedTv?.canonicalDeviceId ?? _target.deviceId ?? kTvDeviceId;

  /// Qué soporta el elegido. Sin lista, todo (comportamiento histórico).
  TvFeatures get features => selectedTv?.features ?? TvFeatures.all;

  /// ¿Le falta el pairing Tizen? Hay que ir hasta el aparato a aceptarlo.
  bool get needsPairing => selectedTv != null && !selectedTv!.paired;

  bool _disposed = false;
  bool _refreshing = false;

  StreamSubscription<DeviceStateEvent>? _sub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  TvStatus? get status => _status;

  /// Hay una lectura en curso **o** un aparato pedido que todavía no se pudo
  /// resolver. Las dos cosas son "cargando" para la pantalla: con un pedido sin
  /// resolver no hay estado, no hay error y no hay nada en vuelo, y sin esto la
  /// pantalla se saltaba el spinner Y el cartel y dibujaba el control entero
  /// rotulado con el aparato ANTERIOR, con todos los botones muertos.
  bool get loading => _loading || _target.state == _TargetState.pending;
  String? get error => _error;
  String? get errorDetail => _errorDetail;

  bool get online => _status?.online ?? false;
  bool get isOn => _status?.isOn ?? false;
  bool get hasVolume => _status?.hasVolume ?? false;
  int get volume => _status?.volume ?? 0;
  bool get muted => _status?.muted ?? false;
  String? get channel => _status?.channel;
  String? get channelName => _status?.channelName;
  String? get input => _status?.input;
  List<TvInput> get inputs => _status?.inputs ?? const [];
  String? get app => _status?.app;
  String? get playback => _status?.playback;
  List<String> get supportedPlaybackCommands =>
      _status?.supportedPlaybackCommands ?? const [];
  String? get pictureMode => _status?.pictureMode;
  List<String> get supportedPictureModes =>
      _status?.supportedPictureModes ?? const [];
  String? get soundMode => _status?.soundMode;
  List<String> get supportedSoundModes =>
      _status?.supportedSoundModes ?? const [];
  List<String> get disabled => _status?.disabled ?? const [];

  /// Nombre del aparato elegido (no viene en /tv/status, sale de GET /tv/tvs).
  /// Sin lista cargada, el nombre histórico del televisor.
  String get displayName => selectedTv?.name ?? '65" OLED';

  /// Gate de comandos optimistas: requiere un estado conocido y online.
  bool get canCommand => _status != null && online;

  /// Helper de gating de un control puntual declarado por el backend.
  bool isDisabled(String id) => _status?.isDisabled(id) ?? false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ── Seed + push por socket (F13, reemplaza el poll de 5s) ────────────────────

  /// Idempotente: cancela una suscripción previa, hace un SEED inmediato
  /// (getTvStatus — necesario porque canCommand depende de `online` y porque el
  /// seed trae inputs/modos/disabled que el socket NO emite) y se suscribe a
  /// device:state-changed.
  void startPolling() {
    _sub?.cancel();
    _connSub?.cancel();
    loadTvs();
    refresh();
    _sub = _socket.onDeviceChanged.listen(_onDeviceEvent);
    // Re-seed en reconexión: los device:state-changed emitidos durante el gap
    // NO se replayean, así que sin esto el estado AV queda congelado tras un
    // background→foreground (frecuente en iOS). Espejo de DevicesService.
    _connSub = _socket.onConnectionChanged.listen((connected) {
      if (connected && !_wasConnected) refresh();
      _wasConnected = connected;
    });
  }

  void stopPolling() {
    _sub?.cancel();
    _sub = null;
    _connSub?.cancel();
    _connSub = null;
  }

  /// Aplica un delta parcial de dev_tv: pisa SÓLO on/volume/muted/input/app/
  /// playback/channel desde el socket y PRESERVA del estado previo los campos
  /// ricos que device:state-changed NO emite (channelName, inputs[], comandos
  /// soportados, modos de imagen/sonido, disabled[]) — ésos vienen del seed
  /// GET /tv/status. Se re-arma campo por campo (copyWith no puede volver a
  /// null; el backend OMITE del delta lo que no cambió → fallback correcto).
  /// Volumen 0-100 passthrough (el TV NO reescala, a diferencia del JBL).
  void _onDeviceEvent(DeviceStateEvent ev) {
    // CCE#45: sólo los eventos del aparato ELEGIDO. Sin este filtro, el monitor
    // apagándose pintaba al televisor como apagado.
    if (ev.deviceId != selectedDeviceId) return;
    final s = _status;
    if (s == null) return; // el seed aún no llegó; refresh() reconciliará
    final st = ev.state;
    if (st == null || st.isEmpty) return;
    _status = TvStatus(
      online: st.containsKey('reachable') ? st['reachable'] != false : s.online,
      power: st.containsKey('on') ? (st['on'] == true ? 'on' : 'off') : s.power,
      // Guard de null igual que JBL: un delta con volume:null NO debe borrar el
      // display previo (hoy el provider solo emite campos definidos, pero blinda
      // ante cambios de contrato del socket).
      volume: st['volume'] == null ? s.volume : (st['volume'] as num).toInt(),
      muted: st.containsKey('muted') && st['muted'] is bool
          ? st['muted'] as bool
          : s.muted,
      channel:
          st.containsKey('mediaChannel') ? st['mediaChannel'] as String? : s.channel,
      channelName: s.channelName,
      input: st.containsKey('mediaInput') ? st['mediaInput'] as String? : s.input,
      inputs: s.inputs,
      app: st.containsKey('mediaApp') ? st['mediaApp'] as String? : s.app,
      playback:
          st.containsKey('mediaState') ? st['mediaState'] as String? : s.playback,
      supportedPlaybackCommands: s.supportedPlaybackCommands,
      pictureMode: s.pictureMode,
      supportedPictureModes: s.supportedPictureModes,
      soundMode: s.soundMode,
      supportedSoundModes: s.supportedSoundModes,
      disabled: s.disabled,
    );
    _safeNotify();
  }

  // ── Lectura ──────────────────────────────────────────────────────────────

  /// NUNCA tira: contra un backend viejo (sin GET /tv/tvs) la lista queda vacía
  /// y la app se comporta como cuando había un solo televisor.
  ///
  /// Trae los Samsung configurados.
  ///
  /// [force] pide una lista NUEVA en vez de compartir la que esté en vuelo: lo
  /// necesita [selectDevice], porque una lista pedida antes que el aparato no
  /// sirve para resolverlo. Lo demás (el shell, las cards) comparte.
  Future<void> loadTvs({bool force = false}) async {
    final inFlight = _tvsInFlight;
    if (!force && inFlight != null) return inFlight;
    final future = _loadTvs();
    _tvsInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_tvsInFlight, future)) _tvsInFlight = null;
    }
  }

  Future<void> _loadTvs() async {
    final asked = _target;
    final list = await _api.getTvs();
    if (list == null) {
      // NO se pudo leer. La lista que había no se toca —pisarla con una vacía
      // dejaba el estado de un aparato en pantalla mientras los comandos se
      // iban a otro— y un aparato esperándola no se da por inexistente ni se
      // reemplaza por el principal: se dice que no se pudo, y se puede
      // reintentar.
      if (asked.state == _TargetState.pending &&
          _target.state == _TargetState.pending &&
          _target.wants(asked.deviceId)) {
        _retarget(
          _target.next(deviceId: asked.deviceId, state: _TargetState.unresolved),
          error: 'No se pudo leer la lista de aparatos',
          errorDetail: 'Sin ella no se sabe cuál de los Samsung es éste.',
        );
      }
      return;
    }
    _tvs = list;

    final wanted = _target.deviceId;
    if (wanted == null) {
      // Nadie nombró aparato: manda el principal y no hay nada que resolver.
      _safeNotify();
      return;
    }
    if (tvForDeviceId(wanted) != null) {
      // Cualquier lista que llegue resuelve el aparato que se quiere AHORA,
      // haya o no un pedido anotado: así una lista buena despega el cartel que
      // dejó una lectura fallida anterior, sin esperar a que alguien reintente.
      if (!_target.isResolved) {
        _retarget(_target.next(deviceId: wanted, state: _TargetState.resolved));
        await refresh();
      } else {
        _safeNotify();
      }
      return;
    }
    if (list.isEmpty) {
      // El backend contestó que no tiene lista (404): es el caso de un solo
      // aparato de antes de CCE#45. Los comandos van sin `?tv=` y los resuelve
      // el backend, que es como se comportaba la app entonces.
      _retarget(_target.next(deviceId: null, state: _TargetState.resolved));
      await refresh();
      return;
    }
    // La lista llegó y ese aparato NO está: lo quitaron.
    if (_target.state != _TargetState.unresolved) {
      _retarget(
        _target.next(deviceId: wanted, state: _TargetState.unresolved),
        error: 'Ese aparato ya no está',
        errorDetail: 'El backend dejó de listarlo. Revisalo desde el Dashboard.',
      );
    } else {
      _safeNotify();
    }
  }

  /// El aparato cuyo device canónico es [deviceId] (`dev_tv-ce588d39`), o null
  /// si no está en la lista — un plano puede seguir apuntando a uno que el
  /// backend ya no lista.
  TvSummary? tvForDeviceId(String deviceId) {
    for (final t in _tvs) {
      if (t.canonicalDeviceId == deviceId) return t;
    }
    return null;
  }

  /// Pasa a comandar el aparato cuyo device canónico es [deviceId]. Es la única
  /// forma en que se elige aparato desde CCE#130: lo nombra quien abre el
  /// control (la habitación, el plano, la card de la home), no un selector
  /// dentro de la pantalla.
  ///
  /// Lo que decide QUÉ SE VE es síncrono: al volver de esta llamada
  /// `selectedTvId` ya es el del aparato pedido y el estado del anterior ya se
  /// descartó, así que la pantalla que se construya después no alcanza a pintar
  /// un frame del aparato de antes.
  ///
  /// Si la lista de aparatos todavía no llegó, el pedido queda PENDIENTE y lo
  /// aplica [loadTvs]. Antes era un no-op silencioso: tocar el monitor con la
  /// app recién abierta abría el televisor, con su estado y sus teclas.
  ///
  /// Devuelve true si de acá sale una lectura del estado —porque cambió el
  /// aparato o porque quedó pendiente—, para que quien abre la pantalla no
  /// pida una segunda: abrir un control costaba dos GET /tv/status del mismo
  /// aparato.
  bool selectDevice(String deviceId) {
    // Ya es exactamente lo que se está mostrando: no hay nada que descartar.
    // Igual se limpia un cartel viejo — si no, abrir el control de un aparato
    // perfectamente válido pintaba encima el error de un intento anterior.
    if (_target.isResolved && _target.wants(deviceId)) {
      if (_error != null) {
        _error = null;
        _errorDetail = null;
        _safeNotify();
      }
      return false;
    }
    // Ya se está resolviendo ESE aparato: la card lo pide al tocarla y la
    // pantalla lo reafirma al abrirse. Volver a pedirlo invalidaba la lista ya
    // en camino, que llegaba "vieja" y no resolvía nada.
    if (_target.state == _TargetState.pending && _target.wants(deviceId)) {
      return true;
    }
    final tv = tvForDeviceId(deviceId);
    if (tv != null) {
      final mismoAparato = selectedTv?.id == tv.id;
      _retarget(
        _target.next(deviceId: deviceId, state: _TargetState.resolved),
        keepStatus: mismoAparato,
      );
      if (mismoAparato) return false;
      unawaited(refresh());
      return true;
    }
    // No se puede resolver todavía. Mientras tanto NO se muestra el estado de
    // otro aparato como si fuera éste; la excepción es el televisor histórico
    // sin lista cargada, que ES lo que se está mostrando.
    _retarget(
      _target.next(deviceId: deviceId, state: _TargetState.pending),
      keepStatus: selectedDeviceId == deviceId,
    );
    unawaited(loadTvs(force: true));
    return true;
  }

  /// Nombre del aparato [deviceId] según GET /tv/tvs; null si no está en la
  /// lista (backend viejo, o un aparato que ya no existe).
  String? nameForDeviceId(String deviceId) => tvForDeviceId(deviceId)?.name;

  /// Reintento del cartel de error de la pantalla. Con un aparato que no
  /// aparecía en la lista vuelve a pedirla —lo pueden haber vuelto a agregar—;
  /// si no, relee el estado. [refresh] solo no alcanza: con un aparato sin
  /// resolver sale temprano a propósito y el botón no haría nada.
  Future<void> retry() async {
    if (_target.state != _TargetState.unresolved) return refresh();
    _retarget(
      _target.next(deviceId: _target.deviceId, state: _TargetState.pending),
    );
    await loadTvs(force: true);
  }

  /// Dispara el pairing Tizen del aparato elegido. TRÁMITE FÍSICO: aparece un
  /// aviso en SU pantalla y alguien tiene que aceptarlo ahí.
  Future<bool> pair() async {
    try {
      final ok = await _api.pairTv(tvId: selectedTvId);
      if (ok) await loadTvs();
      return ok;
    } catch (e) {
      debugPrint('TvService pair error: $e');
      return false;
    }
  }

  /// Relee el estado del aparato elegido, cuando se sabe cuál es.
  ///
  /// La respuesta se DESCARTA si mientras volaba se cambió de aparato: abrir el
  /// control del monitor justo cuando volvía el estado del televisor pintaba el
  /// monitor con el estado del televisor (CCE#130). Y un pedido que llega con
  /// otro en vuelo se ENCOLA en vez de tirarse — ese es el caso normal al abrir
  /// el control (elegir aparato + el refresh de cortesía de la pantalla), y
  /// tirarlo dejaba la pantalla con el estado del aparato anterior.
  Future<void> refresh() async {
    // Sin saber qué aparato es, un GET sin `?tv=` lo contesta el backend con SU
    // aparato por defecto: sería traer el estado del televisor para la pantalla
    // del monitor. [loadTvs] pide el estado apenas lo resuelve.
    if (!_target.isResolved) return;
    if (_refreshing) return;
    _refreshing = true;
    _loading = true;
    _error = null;
    _errorDetail = null;
    _safeNotify();
    final asked = _target;
    try {
      final status = await _api.getTvStatus(tvId: selectedTvId);
      if (_target.sameAs(asked)) _status = status;
    } catch (e) {
      if (_target.sameAs(asked)) {
        _error = 'No se pudo conectar al servidor';
        _errorDetail = 'Revisá la conexión con la API CCE.';
      }
      debugPrint('TvService refresh error: $e');
    } finally {
      _refreshing = false;
      _loading = false;
      _safeNotify();
      // El destino cambió mientras esto volaba: lo que llegó no era de esta
      // pantalla, y quien lo cambió no pudo pedir el suyo porque este estaba en
      // curso. Se pide ahora, en vez de encolarlo en un campo aparte.
      if (!_target.sameAs(asked) && _target.isResolved) unawaited(refresh());
    }
  }

  // ── Comandos ───────────────────────────────────────────────────────────────

  Future<bool> setPower(bool on) async {
    if (_status == null) return false;
    final prev = _status!.power;
    _status = _status!.copyWith(power: on ? 'on' : 'off');
    _safeNotify();
    try {
      await _api.setTvPower(on, tvId: selectedTvId);
      return true;
    } catch (e) {
      _status = _status!.copyWith(power: prev);
      _safeNotify();
      debugPrint('TvService setPower error: $e');
      return false;
    }
  }

  /// Prende/apaga el aparato [deviceId] SIN cambiar el que controla la pantalla
  /// del control: en la home hay una card por Samsung y el switch de una no
  /// puede llevarse el control de la otra.
  ///
  /// Devuelve false sin mandar nada si el aparato no está en la lista: el
  /// comando sin `?tv=` lo resuelve el backend con SU aparato por defecto, o
  /// sea que apagaría el televisor cuando se tocó el switch del monitor.
  Future<bool> setPowerOf(String deviceId, bool on) async {
    final tv = tvForDeviceId(deviceId);
    if (tv == null) {
      // Sin lista (backend viejo, o todavía cargando) el único aparato que se
      // puede comandar sin ambigüedad es el histórico, que es el que el backend
      // atiende por defecto.
      if (_tvs.isEmpty && deviceId == kTvDeviceId) return setPower(on);
      return false;
    }
    // El optimismo local sólo aplica al aparato que la pantalla está mostrando;
    // las cards de los demás reflejan el cambio desde el inventario.
    final prev = _status?.power;
    TvStatus? applied;
    if (tv.id == selectedTv?.id && _status != null) {
      applied = _status = _status!.copyWith(power: on ? 'on' : 'off');
      _safeNotify();
    }
    try {
      await _api.setTvPower(on, tvId: tv.id);
      return true;
    } catch (e) {
      // Se revierte SÓLO si lo que hay en pantalla sigue siendo exactamente lo
      // que este comando escribió. Comparar por id del aparato no alcanzaba: si
      // mientras el PUT viajaba llegó un device:state-changed (alguien lo
      // prendió con el control físico), el revert pisaba esa verdad fresca con
      // el valor viejo. Y si se cambió de aparato, `_status` es otro o es null.
      if (prev != null && applied != null && identical(_status, applied)) {
        _status = _status!.copyWith(power: prev);
        _safeNotify();
      }
      debugPrint('TvService setPowerOf error: $e');
      return false;
    }
  }

  Future<bool> togglePower() async {
    if (_status == null) return false;
    final next = !isOn;
    final prev = _status!.power;
    _status = _status!.copyWith(power: next ? 'on' : 'off');
    _safeNotify();
    try {
      await _api.toggleTvPower(tvId: selectedTvId);
      return true;
    } catch (e) {
      _status = _status!.copyWith(power: prev);
      _safeNotify();
      debugPrint('TvService togglePower error: $e');
      return false;
    }
  }

  /// Slider: pisa optimista, NO revierte en catch (igual que JblService.setVolume
  /// / setBrightness). El próximo poll reconcilia.
  Future<bool> setVolume(int v) async {
    // Gateamos sólo por estado conocido (NO por online): el volumen debe poder
    // enviarse aunque SmartThings reporte offline por rate-limit/timeout, igual
    // que sendKey/togglePower. El TV real es la verdad, no el cache.
    if (_status == null) return false;
    final clamped = v.clamp(0, kTvVolMax);
    _status = _status!.copyWith(volume: clamped);
    _safeNotify();
    try {
      await _api.setTvVolume(clamped, tvId: selectedTvId);
      return true;
    } catch (e) {
      debugPrint('TvService setVolume error: $e');
      return false;
    }
  }

  Future<bool> volumeUp() async {
    // Sólo requiere estado conocido (NO online). NO abortamos en el extremo:
    // el volumen cacheado no es confiable (SmartThings reporta 0 con una app
    // abierta), así que SIEMPRE mandamos el comando al backend.
    if (_status == null) return false;
    final current = _status!.volume ?? 0;
    // Optimismo +1 sólo para el display (el TV puede usar otro step; el poll
    // reconcilia). Nunca abortamos el envío por el cache.
    _status = _status!.copyWith(volume: (current + 1).clamp(0, kTvVolMax));
    _safeNotify();
    try {
      final returned = await _api.tvVolumeUp(tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(volume: returned.clamp(0, kTvVolMax));
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService volumeUp error: $e');
      return false;
    }
  }

  Future<bool> volumeDown() async {
    // Sólo requiere estado conocido (NO online). NO abortamos en el extremo:
    // el volumen cacheado no es confiable (SmartThings reporta 0 con una app
    // abierta), así que SIEMPRE mandamos el comando al backend.
    if (_status == null) return false;
    final current = _status!.volume ?? 0;
    // Optimismo -1 sólo para el display (el poll reconcilia). Nunca abortamos
    // el envío por el cache.
    _status = _status!.copyWith(volume: (current - 1).clamp(0, kTvVolMax));
    _safeNotify();
    try {
      final returned = await _api.tvVolumeDown(tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(volume: returned.clamp(0, kTvVolMax));
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService volumeDown error: $e');
      return false;
    }
  }

  Future<bool> setMute(bool muted) async {
    if (!canCommand) return false;
    final prev = _status!.muted;
    _status = _status!.copyWith(muted: muted);
    _safeNotify();
    try {
      await _api.setTvMute(muted, tvId: selectedTvId);
      return true;
    } catch (e) {
      _restoreMuted(prev);
      _safeNotify();
      debugPrint('TvService setMute error: $e');
      return false;
    }
  }

  Future<bool> toggleMute() async {
    if (!canCommand) return false;
    final prev = _status!.muted;
    _status = _status!.copyWith(muted: !(prev ?? false));
    _safeNotify();
    try {
      await _api.toggleTvMute(tvId: selectedTvId);
      return true;
    } catch (e) {
      _restoreMuted(prev);
      _safeNotify();
      debugPrint('TvService toggleMute error: $e');
      return false;
    }
  }

  /// Sin optimismo de número (el canal real lo confirma el backend/poll); aplica
  /// el valor retornado si viene. Revierte implícitamente vía poll ante error.
  Future<bool> setChannel(String channel) async {
    if (!canCommand) return false;
    try {
      final returned = await _api.setTvChannel(channel, tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(channel: returned);
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService setChannel error: $e');
      return false;
    }
  }

  Future<bool> channelUp() async {
    if (!canCommand) return false;
    try {
      final returned = await _api.tvChannelUp(tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(channel: returned);
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService channelUp error: $e');
      return false;
    }
  }

  Future<bool> channelDown() async {
    if (!canCommand) return false;
    try {
      final returned = await _api.tvChannelDown(tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(channel: returned);
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService channelDown error: $e');
      return false;
    }
  }

  Future<bool> setInput(String id) async {
    if (!canCommand) return false;
    final prev = _status!.input;
    _status = _status!.copyWith(input: id);
    _safeNotify();
    try {
      final returned = await _api.setTvInput(id, tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(input: returned);
        _safeNotify();
      }
      return true;
    } catch (e) {
      // Revert (input es non-null en optimismo; copyWith basta).
      _status = _status!.copyWith(input: prev);
      _safeNotify();
      debugPrint('TvService setInput error: $e');
      return false;
    }
  }

  /// Envía una tecla del remote (allowlist [TvRemoteKeys]). NO gatea por
  /// `online`: varias teclas (power/home/hdmi) despiertan el TV desde standby.
  /// Gatea sólo por estado conocido (`_status != null`); el backend devuelve
  /// `ok:false` sin romper si el TV rechaza/está offline. Sin optimismo de
  /// estado (son press momentáneos/toggle sin lectura).
  Future<bool> sendKey(String id) async {
    if (_status == null) return false;
    try {
      return await _api.sendTvKey(id, tvId: selectedTvId);
    } catch (e) {
      debugPrint('TvService sendKey error: $e');
      return false;
    }
  }

  /// Comando de reproducción (play|pause|stop|fastForward|rewind). Aplica el
  /// estado de playback retornado si viene; sin optimismo previo.
  /// NOTA: se llama `setPlayback` (no `playback`) para no colisionar con el
  /// getter `playback` (Dart no permite getter + método con el mismo nombre).
  Future<bool> setPlayback(String action) async {
    if (_status == null) return false;
    try {
      final returned = await _api.tvPlayback(action, tvId: selectedTvId);
      if (returned != null) {
        _status = _status!.copyWith(playback: returned);
        _safeNotify();
      }
      return true;
    } catch (e) {
      debugPrint('TvService playback error: $e');
      return false;
    }
  }

  Future<bool> trackNext() async {
    if (_status == null) return false;
    try {
      await _api.tvTrackNext(tvId: selectedTvId);
      return true;
    } catch (e) {
      debugPrint('TvService trackNext error: $e');
      return false;
    }
  }

  Future<bool> trackPrev() async {
    if (_status == null) return false;
    try {
      await _api.tvTrackPrev(tvId: selectedTvId);
      return true;
    } catch (e) {
      debugPrint('TvService trackPrev error: $e');
      return false;
    }
  }

  Future<bool> setPictureMode(String mode) async {
    if (!canCommand) return false;
    final prev = _status!.pictureMode;
    _status = _status!.copyWith(pictureMode: mode);
    _safeNotify();
    try {
      await _api.setTvPictureMode(mode, tvId: selectedTvId);
      return true;
    } catch (e) {
      if (prev != null) {
        _status = _status!.copyWith(pictureMode: prev);
        _safeNotify();
      }
      debugPrint('TvService setPictureMode error: $e');
      return false;
    }
  }

  Future<bool> setSoundMode(String mode) async {
    if (!canCommand) return false;
    final prev = _status!.soundMode;
    _status = _status!.copyWith(soundMode: mode);
    _safeNotify();
    try {
      await _api.setTvSoundMode(mode, tvId: selectedTvId);
      return true;
    } catch (e) {
      if (prev != null) {
        _status = _status!.copyWith(soundMode: prev);
        _safeNotify();
      }
      debugPrint('TvService setSoundMode error: $e');
      return false;
    }
  }

  /// Lanza una app por appId (netflix/max/prime/youtube). Sin optimismo; refresh
  /// tras éxito para reflejar el cambio de `app`/`input`. NO gatea por online
  /// (lanzar una app puede despertar el TV).
  Future<bool> launchApp(String appId) async {
    if (_status == null) return false;
    try {
      final ok = await _api.launchTvApp(appId, tvId: selectedTvId);
      if (ok) await refresh();
      return ok;
    } catch (e) {
      debugPrint('TvService launchApp error: $e');
      return false;
    }
  }

  /// Lista de apps INSTALADAS sondeadas en el TV (passthrough a
  /// [ApiService.getInstalledTvApps]). NUNCA tira (la api ya garantiza []
  /// ante error); no cachea ni notifica: el sheet la pide on-demand al abrir.
  Future<List<TvInstalledApp>> installedApps() =>
      _api.getInstalledTvApps(tvId: selectedTvId);

  /// Activa el modo ambiente del TV (POST /tv/ambient/on).
  Future<bool> ambientOn() async {
    if (_status == null) return false;
    try {
      await _api.tvAmbientOn(tvId: selectedTvId);
      await refresh();
      return true;
    } catch (e) {
      debugPrint('TvService ambientOn error: $e');
      return false;
    }
  }

  /// SOLO TESTS: siembra la lista de aparatos, el elegido y el estado, sin red
  /// ni socket. Espeja lo que hacen [loadTvs] y [refresh] con la respuesta HTTP
  /// (mismo patrón que DevicesService.debugSeedDevices).
  @visibleForTesting
  void debugSeed({
    List<TvSummary>? tvs,
    TvStatus? status,
    String? selectedId,
  }) {
    if (tvs != null) _tvs = tvs;
    if (status != null) _status = status;
    if (selectedId != null) {
      // El destino se nombra por device canónico; el id del aparato es lo que
      // los tests tienen a mano, así que se traduce acá.
      final tv = _tvs.where((t) => t.id == selectedId).firstOrNull;
      _target = _target.next(
        deviceId: tv?.canonicalDeviceId ?? 'dev_$selectedId',
        // Un elegido que no está en la lista sembrada queda SIN resolver, igual
        // que si lo hubiera descubierto [loadTvs]: no se cae al principal.
        state: tv != null ? _TargetState.resolved : _TargetState.unresolved,
      );
    }
    _safeNotify();
  }

  /// SOLO TESTS: aplica un `device:state-changed` como si viniera del socket,
  /// para poder verificar que un evento de OTRO aparato no toca el estado del
  /// elegido.
  @visibleForTesting
  void debugApplyDeviceEvent(DeviceStateEvent ev) => _onDeviceEvent(ev);

  /// Revert del campo `muted` que SÍ puede restaurar `null` (a diferencia de
  /// copyWith, cuyo patrón `?? this.muted` no puede setear null). Reconstruye
  /// el TvStatus preservando el resto de los campos. No-op si _status es null.
  void _restoreMuted(bool? prev) {
    final s = _status;
    if (s == null) return;
    _status = TvStatus(
      online: s.online,
      power: s.power,
      volume: s.volume,
      muted: prev,
      channel: s.channel,
      channelName: s.channelName,
      input: s.input,
      inputs: s.inputs,
      app: s.app,
      playback: s.playback,
      supportedPlaybackCommands: s.supportedPlaybackCommands,
      pictureMode: s.pictureMode,
      supportedPictureModes: s.supportedPictureModes,
      soundMode: s.soundMode,
      supportedSoundModes: s.supportedSoundModes,
      disabled: s.disabled,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
