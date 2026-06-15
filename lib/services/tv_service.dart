import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/tv_status.dart';
import '../models/server_config.dart';
import 'api_service.dart';

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

/// Estado del Samsung TV con polling controlable (5s). El TV NO emite por
/// socket: el estado se obtiene por polling de getTvStatus.
///
/// El shell (tablet/phone) posee el ciclo de polling: arranca/para según la
/// tab/pantalla visible. La screen NO arranca polling en su initState (solo un
/// refresh de cortesía one-shot).
///
/// Separación `_error` vs `online:false` (idéntica a JblService):
///  - `_error != null` ⟺ excepción real del propio getTvStatus (red caída /
///    API CCE down / timeout).
///  - `status.online == false` con `_error == null` ⟺ el backend respondió pero
///    el TV está apagado/inalcanzable (cloud reporta offline o Tizen no
///    responde). GET /tv/status NUNCA tira por TV inalcanzable.
class TvService extends ChangeNotifier {
  final ApiService _api;

  TvService({required ServerConfig config}) : _api = ApiService(config);

  TvStatus? _status;
  bool _loading = false;
  String? _error;

  bool _disposed = false;
  bool _refreshing = false;
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 5);

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

  /// Nombre fijo del equipo (no viene en /tv/status). "65\" OLED".
  String get displayName => '65" OLED';

  /// Gate de comandos optimistas: requiere un estado conocido y online.
  bool get canCommand => _status != null && online;

  /// Helper de gating de un control puntual declarado por el backend.
  bool isDisabled(String id) => _status?.isDisabled(id) ?? false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  /// Idempotente: cancela un timer previo, hace un refresh inmediato y luego
  /// poll cada _pollInterval.
  void startPolling() {
    _pollTimer?.cancel();
    refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Lectura ──────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    _loading = true;
    _error = null;
    _safeNotify();
    try {
      _status = await _api.getTvStatus();
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
      await _api.setTvPower(on);
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
      await _api.toggleTvPower();
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
    if (!canCommand) return false;
    final clamped = v.clamp(0, kTvVolMax);
    _status = _status!.copyWith(volume: clamped);
    _safeNotify();
    try {
      await _api.setTvVolume(clamped);
      return true;
    } catch (e) {
      debugPrint('TvService setVolume error: $e');
      return false;
    }
  }

  Future<bool> volumeUp() async {
    if (!canCommand) return false;
    final current = _status!.volume ?? 0;
    if (current >= kTvVolMax) return true;
    // Optimismo +1 (el TV puede usar otro step; el poll reconcilia).
    _status = _status!.copyWith(volume: (current + 1).clamp(0, kTvVolMax));
    _safeNotify();
    try {
      final returned = await _api.tvVolumeUp();
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
    if (!canCommand) return false;
    final current = _status!.volume ?? 0;
    if (current <= 0) return true;
    _status = _status!.copyWith(volume: (current - 1).clamp(0, kTvVolMax));
    _safeNotify();
    try {
      final returned = await _api.tvVolumeDown();
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
      await _api.setTvMute(muted);
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
      await _api.toggleTvMute();
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
      final returned = await _api.setTvChannel(channel);
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
      final returned = await _api.tvChannelUp();
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
      final returned = await _api.tvChannelDown();
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
      final returned = await _api.setTvInput(id);
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
      return await _api.sendTvKey(id);
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
      final returned = await _api.tvPlayback(action);
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
      await _api.tvTrackNext();
      return true;
    } catch (e) {
      debugPrint('TvService trackNext error: $e');
      return false;
    }
  }

  Future<bool> trackPrev() async {
    if (_status == null) return false;
    try {
      await _api.tvTrackPrev();
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
      await _api.setTvPictureMode(mode);
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
      await _api.setTvSoundMode(mode);
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
      final ok = await _api.launchTvApp(appId);
      if (ok) await refresh();
      return ok;
    } catch (e) {
      debugPrint('TvService launchApp error: $e');
      return false;
    }
  }

  /// Activa el modo ambiente del TV (POST /tv/ambient/on).
  Future<bool> ambientOn() async {
    if (_status == null) return false;
    try {
      await _api.tvAmbientOn();
      await refresh();
      return true;
    } catch (e) {
      debugPrint('TvService ambientOn error: $e');
      return false;
    }
  }

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
    _pollTimer?.cancel();
    super.dispose();
  }
}
