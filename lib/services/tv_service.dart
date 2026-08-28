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

  TvService({required ServerConfig config, required SocketService socket})
      : _api = ApiService(config),
        _socket = socket;

  TvStatus? _status;
  bool _loading = false;
  String? _error;

  // ── Varios Samsung (CCE#45) ────────────────────────────────────────────────
  // `_status` es SIEMPRE el del aparato SELECCIONADO. La lista puede quedar
  // vacía (backend viejo sin GET /tv/tvs): en ese caso no hay selector, los
  // comandos van sin `?tv=` y el socket se filtra por `dev_tv` — exactamente el
  // comportamiento anterior a esta feature.
  List<TvSummary> _tvs = const [];
  String? _selectedId;

  List<TvSummary> get tvs => _tvs;
  bool get hasMultipleTvs => _tvs.length > 1;

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
  StreamSubscription<DeviceStateEvent>? _sub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  TvStatus? get status => _status;
  bool get loading => _loading;
  String? get error => _error;

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

  /// Trae los Samsung configurados. NUNCA tira: contra un backend viejo (sin
  /// GET /tv/tvs) la lista queda vacía y la app se comporta como cuando había
  /// un solo televisor.
  Future<void> loadTvs() async {
    final list = await _api.getTvs();
    _tvs = list;
    // Un aparato elegido que ya no existe (lo quitaron) no puede dejar la app
    // mandando comandos a la nada.
    if (_selectedId != null && !list.any((t) => t.id == _selectedId)) {
      _selectedId = null;
    }
    _safeNotify();
  }

  /// Cambia el aparato controlado y relee su estado. El estado del anterior se
  /// descarta: mostrar el volumen del televisor mientras se comanda el monitor
  /// sería peor que mostrar "cargando".
  Future<void> selectTv(String id) async {
    if (_selectedId == id) return;
    _selectedId = id;
    _status = null;
    _safeNotify();
    await refresh();
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

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    _loading = true;
    _error = null;
    _safeNotify();
    try {
      _status = await _api.getTvStatus(tvId: selectedTvId);
    } catch (e) {
      _error = 'No se pudo conectar al servidor';
      debugPrint('TvService refresh error: $e');
    } finally {
      _loading = false;
      _refreshing = false;
      _safeNotify();
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
