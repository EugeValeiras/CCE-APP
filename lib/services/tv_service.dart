import 'dart:async';
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
  String? _selectedId;

  /// Device canónico pedido por quien abrió el control cuando la lista de
  /// aparatos todavía no había llegado. [loadTvs] lo aplica al resolver.
  String? _pendingDeviceId;

  /// Device canónico pedido que la lista NO contiene (lo quitaron del backend).
  /// No se puede caer al aparato por defecto: comandar el televisor cuando se
  /// abrió el monitor es peor que decir que no se puede.
  String? _missingDeviceId;

  /// Cambia cada vez que cambia EL APARATO QUE LA PANTALLA TIENE QUE MOSTRAR.
  ///
  /// Es la identidad que [refresh] necesita para saber si la respuesta que le
  /// llegó sigue siendo la de esta pantalla. `selectedTvId` NO sirve para eso:
  /// pasa de null al id del principal con sólo llegar la lista, sin que nadie
  /// haya cambiado de aparato — y comparando contra él, el primer estado de
  /// cada sesión se descartaba por una diferencia que no era un cambio.
  int _selectionEpoch = 0;

  /// Cambia cada vez que se anota un pedido pendiente. [loadTvs] la mira para
  /// no resolver con una lista que salió ANTES del pedido: hay varios
  /// `loadTvs` en vuelo (el shell, cada card, cada apertura del control) y uno
  /// viejo se llevaba puesta la selección recién pedida.
  int _pendingEpoch = 0;

  /// Numeración de los GET /tv/tvs: se piden desde varios lados a la vez (el
  /// shell, cada card de la home, cada apertura del control) y vuelven
  /// desordenados. Una respuesta más vieja que la última aplicada se descarta:
  /// si no, una lista vacía —que es lo que devuelve [ApiService.getTvs] ante
  /// CUALQUIER error— pisaba la lista buena y se llevaba puesta la selección.
  int _tvsRequestSeq = 0;
  int _tvsAppliedSeq = 0;

  /// GET /tv/tvs en vuelo, compartido por quien no necesita una lista recién
  /// pedida (las cards de la home): tres cards montándose eran tres requests.
  Future<void>? _tvsInFlight;

  /// El aparato pedido no está y no se puede comandar otro en su lugar.
  bool get missingDevice => _missingDeviceId != null;

  List<TvSummary> get tvs => _tvs;

  /// El aparato elegido, o null mientras la lista no cargó.
  TvSummary? get selectedTv {
    if (_tvs.isEmpty) return null;
    for (final t in _tvs) {
      if (t.id == _selectedId) return t;
    }
    for (final t in _tvs) {
      if (t.isDefault) return t;
    }
    return _tvs.first;
  }

  /// Id para `?tv=` (null ⇒ el backend usa su aparato por defecto).
  String? get selectedTvId => selectedTv?.id ?? _selectedId;

  /// Device canónico del elegido: por dónde llegan SUS eventos del socket.
  String get selectedDeviceId => selectedTv?.canonicalDeviceId ?? kTvDeviceId;

  /// Qué soporta el elegido. Sin lista, todo (comportamiento histórico).
  TvFeatures get features => selectedTv?.features ?? TvFeatures.all;

  /// ¿Le falta el pairing Tizen? Hay que ir hasta el aparato a aceptarlo.
  bool get needsPairing => selectedTv != null && !selectedTv!.paired;

  bool _disposed = false;
  bool _refreshing = false;

  /// Un refresh pedido mientras había otro en vuelo. No se tira: al abrir el
  /// control se pide el estado del aparato elegido y enseguida el refresh de
  /// cortesía de la pantalla, y descartar el segundo dejaba en pantalla el
  /// estado del aparato anterior.
  bool _queuedRefresh = false;
  StreamSubscription<DeviceStateEvent>? _sub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  TvStatus? get status => _status;

  /// Hay una lectura en curso **o** un aparato pedido que todavía no se pudo
  /// resolver. Las dos cosas son "cargando" para la pantalla: con un pedido sin
  /// resolver no hay estado, no hay error y no hay nada en vuelo, y sin esto la
  /// pantalla se saltaba el spinner Y el cartel y dibujaba el control entero
  /// rotulado con el aparato ANTERIOR, con todos los botones muertos.
  bool get loading => _loading || _pendingDeviceId != null;
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
    final seq = ++_tvsRequestSeq;
    // La epoch del pendiente se captura ANTES de salir a la red: si mientras
    // vuela esta lista alguien pide otro aparato, esta respuesta ya es vieja y
    // no puede decidir sobre ese pedido.
    final epoch = _pendingEpoch;
    final pending = _pendingDeviceId;
    final pendingWaiting = pending != null;
    final list = await _api.getTvs();
    // Respuesta fuera de orden: ya se aplicó una más nueva.
    if (seq < _tvsAppliedSeq) return;
    if (list == null) {
      // NO se pudo leer la lista. La que había NO se toca —pisarla con una
      // vacía dejaba el estado del monitor en pantalla y los comandos yéndose
      // al televisor— y un aparato pedido NO se da por inexistente ni se
      // reemplaza por el principal: se dice que no se pudo y se ofrece
      // reintentar.
      if (pendingWaiting && epoch == _pendingEpoch) {
        _pendingDeviceId = null;
        _missingDeviceId = pending;
        _status = null;
        _error = 'No se pudo leer la lista de aparatos';
        _errorDetail = 'Sin ella no se sabe cuál de los Samsung es éste.';
        _selectionEpoch++;
        _safeNotify();
      }
      return;
    }
    _tvsAppliedSeq = seq;
    _tvs = list;
    // Un aparato elegido que ya no existe (lo quitaron) no puede dejar la app
    // mandando comandos a la nada.
    if (_selectedId != null && !list.any((t) => t.id == _selectedId)) {
      _selectedId = null;
      _selectionEpoch++;
    }
    // Un aparato pedido ANTES de que llegara la lista (abrir el control del
    // monitor apenas arrancó la app) se aplica recién acá. Sin esto el pedido
    // se perdía en silencio y el control abría el que estuviera elegido.
    final resolvable = _pendingDeviceId != null && epoch == _pendingEpoch;
    if (resolvable) {
      final tv = tvForDeviceId(_pendingDeviceId!);
      if (tv != null) {
        _pendingDeviceId = null;
        _missingDeviceId = null;
        if (_selectedId != tv.id) _selectionEpoch++;
        _selectedId = tv.id;
      } else if (list.isEmpty) {
        // El backend contestó que NO tiene lista (404: la ruta no existe). Es
        // el caso de un solo aparato de antes de CCE#45: se suelta el pedido y
        // manda el aparato por defecto del backend, que es como se comportaba
        // la app entonces. Esto sólo es seguro porque ahora una lista vacía
        // significa "el backend lo dijo" y no "algo falló".
        _pendingDeviceId = null;
        _selectionEpoch++;
      } else {
        // La lista llegó y ese aparato NO está: lo quitaron. No se cae al
        // aparato por defecto — cada tecla iría al Samsung equivocado.
        final missing = _pendingDeviceId;
        _pendingDeviceId = null;
        _missingDeviceId = missing;
        _status = null;
        _error = 'Ese aparato ya no está';
        _errorDetail = 'El backend dejó de listarlo. Revisalo desde el Dashboard.';
        _selectionEpoch++;
      }
    }
    _safeNotify();
    // El pedido dejó la pantalla sin estado a propósito (no se muestra el del
    // aparato anterior): ahora que se sabe cuál es, se pide el suyo.
    //
    // Sin condicionarlo a que falte el estado. Hoy da igual —con la epoch de
    // selección, cualquier respuesta en vuelo del aparato anterior se descarta
    // y `_status` llega acá en null—, pero el invariante que importa es "al
    // cambiar de aparato se lee el estado del nuevo", y escribirlo así no lo
    // hace depender de que el otro arreglo siga en su lugar.
    if (resolvable && _missingDeviceId == null) await refresh();
  }

  /// Cambia el aparato controlado y relee su estado. El estado del anterior se
  /// descarta: mostrar el volumen del televisor mientras se comanda el monitor
  /// sería peor que mostrar "cargando".
  ///
  /// PRIVADA: el aparato se elige por su device canónico ([selectDevice]), que
  /// es lo único que tienen a mano la habitación, el plano y las cards. Entrar
  /// por acá con un pedido pendiente vivo dejaba la pantalla sin estado, sin
  /// spinner y sin error, y sin forma de reintentar.
  ///
  /// El guard mira el aparato EFECTIVO y no `_selectedId`: cuando nadie eligió
  /// nada, `_selectedId` es null pero se está mostrando el principal, y fijarlo
  /// explícitamente borraba su estado y mandaba la pantalla al spinner por
  /// nada. Eso es el parpadeo que se ve al abrir el control desde la home.
  Future<void> _selectTv(String id) async {
    if (selectedTv?.id == id) {
      // Ya es el que se está mostrando: se fija para dejar de depender del
      // default, sin tocar el estado.
      _selectedId = id;
      return;
    }
    _selectedId = id;
    _status = null;
    _selectionEpoch++;
    _safeNotify();
    await refresh();
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
    // Idempotente: la card lo llama al tocarla y la pantalla lo reafirma en su
    // post-frame. Sin esto, el segundo pedido bumpeaba las épocas y la lista ya
    // en camino llegaba "vieja": se aplicaba pero no resolvía el aparato, y la
    // pantalla se quedaba sin estado hasta la respuesta siguiente.
    if (_pendingDeviceId == deviceId) return true;
    final tv = tvForDeviceId(deviceId);
    if (tv != null) {
      _pendingDeviceId = null;
      _missingDeviceId = null;
      final cambia = selectedTv?.id != tv.id;
      // Sin await a propósito: lo que decide qué se ve ya pasó cuando esto
      // vuelve; lo que queda pendiente es el GET del estado nuevo.
      unawaited(_selectTv(tv.id));
      return cambia;
    }
    // No se puede resolver todavía. Mientras tanto NO se muestra el estado de
    // otro aparato como si fuera éste; la excepción es el televisor histórico
    // sin lista cargada, que ES lo que se está mostrando.
    if (selectedDeviceId != deviceId) {
      _selectedId = null;
      _status = null;
    }
    _pendingDeviceId = deviceId;
    _missingDeviceId = null;
    _error = null;
    _errorDetail = null;
    // Las dos epochs: la de selección invalida las respuestas en vuelo (el
    // estado del aparato anterior ya no es el de esta pantalla), y la del
    // pendiente evita que un `loadTvs` que salió antes de este pedido lo
    // resuelva con una lista vieja.
    _selectionEpoch++;
    _pendingEpoch++;
    _safeNotify();
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
    final missing = _missingDeviceId;
    if (missing == null) return refresh();
    _missingDeviceId = null;
    _error = null;
    _errorDetail = null;
    _pendingDeviceId = missing;
    _pendingEpoch++;
    _selectionEpoch++;
    _safeNotify();
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
    // Con un aparato pedido y todavía sin resolver, un GET sin `?tv=` lo
    // contesta el backend con SU aparato por defecto: sería traer el estado del
    // televisor para la pantalla del monitor. Se espera a la lista — [loadTvs]
    // pide el estado apenas sabe cuál es. Y un aparato que ya no está no tiene
    // estado que pedir.
    if (_pendingDeviceId != null || _missingDeviceId != null) return;
    if (_refreshing) {
      _queuedRefresh = true;
      return;
    }
    _refreshing = true;
    _loading = true;
    _error = null;
    _errorDetail = null;
    _safeNotify();
    final epoch = _selectionEpoch;
    try {
      final status = await _api.getTvStatus(tvId: selectedTvId);
      if (epoch == _selectionEpoch) _status = status;
    } catch (e) {
      if (epoch == _selectionEpoch) {
        _error = 'No se pudo conectar al servidor';
        _errorDetail = 'Revisá la conexión con la API CCE.';
      }
      debugPrint('TvService refresh error: $e');
    } finally {
      _refreshing = false;
      final queued = _queuedRefresh;
      _queuedRefresh = false;
      // `loading` SIEMPRE baja y SIEMPRE se notifica, incluso encadenando: el
      // encadenado puede salir temprano (aparato sin resolver) y dejar la
      // pantalla clavada en el spinner. Cuando sí corre, vuelve a subirlo en
      // este mismo turno síncrono, así que no hay un frame intermedio.
      _loading = false;
      _safeNotify();
      if (queued) unawaited(refresh());
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
    if (selectedId != null) _selectedId = selectedId;
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
