import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/jbl_status.dart';
import '../models/server_config.dart';
import 'api_service.dart';

/// Estado del soundbar JBL con polling controlable (5s). El soundbar NO emite
/// por socket: el estado se obtiene por polling de getJblStatus.
///
/// El shell (tablet/phone) posee el ciclo de polling: arranca/para según la
/// tab visible. La screen NO arranca polling en su initState.
///
/// Separación `_error` vs `online:false`:
///  - `_error != null` ⟺ excepción real del propio getJblStatus (red caída /
///    API CCE down / timeout).
///  - `status.online == false` con `_error == null` ⟺ la barra respondió pero
///    está en standby/inalcanzable a nivel UPnP.
class JblService extends ChangeNotifier {
  final ApiService _api;

  JblService({required ServerConfig config}) : _api = ApiService(config);

  JblStatus? _status;
  List<JblRadio> _radios = const [];
  bool _loading = false;
  String? _error;

  bool _disposed = false;
  bool _refreshing = false;
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 5);

  JblStatus? get status => _status;
  List<JblRadio> get radios => _radios;
  bool get loading => _loading;
  String? get error => _error;
  bool get online => _status?.online ?? false;
  bool get isOn => _status?.isOn ?? false;
  bool get hasVolume => _status?.hasVolume ?? false;
  int get volume => _status?.volume ?? 0;
  bool get muted => _status?.muted ?? false;
  String? get source => _status?.source;
  String get displayName => _status?.name ?? 'JBL BAR 1000MK2';

  /// Gate de comandos optimistas: requiere un estado conocido y online.
  bool get canCommand => _status != null && online;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Revert del campo `muted` que SÍ puede restaurar `null` (a diferencia de
  /// copyWith, cuyo patrón `?? this.muted` no puede setear null). Reconstruye
  /// el JblStatus preservando el resto de los campos. No-op si _status es null.
  void _restoreMuted(bool? prev) {
    final s = _status;
    if (s == null) return;
    _status = JblStatus(
      online: s.online,
      ip: s.ip,
      name: s.name,
      volume: s.volume,
      muted: prev,
      power: s.power,
      source: s.source,
      transport: s.transport,
    );
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
      _status = await _api.getJblStatus();
      try {
        _radios = await _api.getJblRadios();
      } catch (_) {
        // Degrada sin tocar _error: las radios son secundarias.
        _radios = const [];
      }
    } catch (e) {
      _error = 'No se pudo conectar al servidor';
      debugPrint('JblService refresh error: $e');
    } finally {
      _loading = false;
      _refreshing = false;
      _safeNotify();
    }
  }

  /// Solo radios; degrada a [] sin tocar _error.
  Future<void> refreshRadios() async {
    try {
      _radios = await _api.getJblRadios();
    } catch (e) {
      _radios = const [];
      debugPrint('JblService refreshRadios error: $e');
    }
    _safeNotify();
  }

  // ── Comandos ───────────────────────────────────────────────────────────────

  /// Slider: pisa optimista, NO revierte en catch (igual que setBrightness).
  Future<bool> setVolume(int volume) async {
    if (!canCommand) return false;
    final clamped = volume.clamp(0, 100);
    _status = _status!.copyWith(volume: clamped);
    _safeNotify();
    try {
      await _api.setJblVolume(clamped);
      return true;
    } catch (e) {
      debugPrint('JblService setVolume error: $e');
      return false;
    }
  }

  /// Aplica el volumen real retornado por el backend (autoritativo).
  Future<bool> nudgeVolume(int delta) async {
    if (!canCommand) return false;
    try {
      final returned = delta >= 0
          ? await _api.jblVolumeUp()
          : await _api.jblVolumeDown();
      _status = _status!.copyWith(volume: returned);
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('JblService nudgeVolume error: $e');
      return false;
    }
  }

  Future<bool> setMuted(bool muted) async {
    if (!canCommand) return false;
    final prev = _status!.muted;
    _status = _status!.copyWith(muted: muted);
    _safeNotify();
    try {
      await _api.setJblMute(muted);
      return true;
    } catch (e) {
      _restoreMuted(prev);
      _safeNotify();
      debugPrint('JblService setMuted error: $e');
      return false;
    }
  }

  Future<bool> toggleMute() async {
    if (!canCommand) return false;
    final prev = _status!.muted;
    _status = _status!.copyWith(muted: !(prev ?? false));
    _safeNotify();
    try {
      await _api.toggleJblMute();
      return true;
    } catch (e) {
      _restoreMuted(prev);
      _safeNotify();
      debugPrint('JblService toggleMute error: $e');
      return false;
    }
  }

  Future<bool> togglePower() async {
    if (!canCommand) return false;
    final next = !isOn;
    final prev = _status!.power;
    _status = _status!.copyWith(power: next ? 'on' : 'off');
    _safeNotify();
    try {
      await _api.setJblPower(next);
      return true;
    } catch (e) {
      _status = _status!.copyWith(power: prev);
      _safeNotify();
      debugPrint('JblService togglePower error: $e');
      return false;
    }
  }

  /// Sin optimismo; refresh tras éxito. Funciona offline server-side; un 502
  /// (barra inalcanzable) devuelve false sin setear _error global.
  Future<bool> playRadio(String name) async {
    try {
      await _api.playJblRadio(name: name);
      await refresh();
      return true;
    } catch (e) {
      debugPrint('JblService playRadio error: $e');
      return false;
    }
  }

  Future<bool> saveCurrentRadio() async {
    try {
      await _api.saveJblRadio();
      await refreshRadios();
      return true;
    } catch (e) {
      debugPrint('JblService saveCurrentRadio error: $e');
      return false;
    }
  }

  Future<bool> deleteRadio(String name) async {
    try {
      await _api.deleteJblRadio(name);
      await refreshRadios();
      return true;
    } catch (e) {
      debugPrint('JblService deleteRadio error: $e');
      return false;
    }
  }

  Future<bool> setIp(String ip) async {
    try {
      await _api.setJblIp(ip);
      await refresh();
      return true;
    } catch (e) {
      debugPrint('JblService setIp error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
