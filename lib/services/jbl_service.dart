import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/jbl_status.dart';
import '../models/server_config.dart';
import 'api_service.dart';
import 'socket_service.dart';

/// Id canónico del soundbar en /merged (F8/F13): emite device:state-changed
/// al socket con deltas parciales (on/volume/muted/mediaInput).
const String kJblDeviceId = 'dev_jbl';

/// Tope del control de volumen en la UI: 0-31, step 1. Es la escala de DISPLAY
/// de la barra (lo que muestra el equipo); la API expone/acepta el volumen en
/// esta misma escala y convierte a la UPnP nativa (0-100) internamente, así el
/// número de la app coincide con el de la barra. El dial y los botones − / +
/// (setVolume / nudgeVolume) clampan contra esto.
const int kJblVolMax = 31;

/// Allowlist de ids del remote JBL (espejo del enum compartido del backend —
/// ver remote-keys.ts / contrato 0.1). El `deviceKey` real vive SOLO
/// server-side: la app sólo manda estos ids.
abstract final class JblRemoteKeys {
  static const String playpause = 'playpause';
  static const String tv = 'tv';
  static const String hdmi = 'hdmi';
  static const String bluetooth = 'bluetooth';
  static const String atmos = 'atmos';
  static const String bass = 'bass';
  static const String calibrate = 'calibrate';
  static const String surround = 'surround';
}

/// Estado del soundbar JBL con PUSH por socket (F13). dev_jbl emite
/// device:state-changed con deltas parciales; el service hace un SEED inicial
/// (getJblStatus) y luego escucha el socket — sin Timer.periodic.
///
/// El shell (tablet/phone) posee el ciclo: [startPolling] hace el seed +
/// suscripción, [stopPolling] cancela la suscripción (nombres conservados para
/// no tocar los call-sites). La screen NO arranca nada en su initState.
///
/// Separación `_error` vs `online:false`:
///  - `_error != null` ⟺ excepción real del propio getJblStatus (red caída /
///    API CCE down / timeout).
///  - `status.online == false` con `_error == null` ⟺ la barra respondió pero
///    está en standby/inalcanzable a nivel UPnP.
class JblService extends ChangeNotifier {
  final ApiService _api;
  final SocketService _socket;

  JblService({required ServerConfig config, required SocketService socket})
      : _api = ApiService(config),
        _socket = socket;

  JblStatus? _status;
  List<JblRadio> _radios = const [];
  bool _loading = false;
  String? _error;

  bool _disposed = false;
  bool _refreshing = false;
  StreamSubscription<DeviceStateEvent>? _sub;
  StreamSubscription<bool>? _connSub;
  bool _wasConnected = false;

  JblStatus? get status => _status;
  List<JblRadio> get radios => _radios;
  bool get loading => _loading;
  String? get error => _error;
  bool get online => _status?.online ?? false;
  bool get isOn => _status?.isOn ?? false;
  bool get hasVolume => _status?.hasVolume ?? false;
  int get volume => _status?.volume ?? 0;
  bool get muted => _status?.muted ?? false;
  bool get nightMode => _status?.nightMode ?? false;
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
      nightMode: s.nightMode,
    );
  }

  /// Revert del campo `nightMode` que SÍ puede restaurar `null` (igual que
  /// [_restoreMuted]: copyWith no puede setear null). No-op si _status es null.
  void _restoreNightMode(bool? prev) {
    final s = _status;
    if (s == null) return;
    _status = JblStatus(
      online: s.online,
      ip: s.ip,
      name: s.name,
      volume: s.volume,
      muted: s.muted,
      power: s.power,
      source: s.source,
      transport: s.transport,
      nightMode: prev,
    );
  }

  // ── Seed + push por socket (F13, reemplaza el poll de 5s) ────────────────────

  /// Idempotente: cancela una suscripción previa, hace un SEED inmediato
  /// (getJblStatus — necesario porque canCommand depende de `online` y el
  /// socket sólo manda deltas parciales) y se suscribe a device:state-changed.
  void startPolling() {
    _sub?.cancel();
    _connSub?.cancel();
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

  /// Aplica un delta parcial de dev_jbl re-armando el estado campo por campo con
  /// fallback al previo (copyWith no puede volver un campo a null; el backend
  /// OMITE del delta los campos que no cambian, así que el fallback es correcto).
  void _onDeviceEvent(DeviceStateEvent ev) {
    if (ev.deviceId != kJblDeviceId) return;
    final s = _status;
    if (s == null) return; // el seed aún no llegó; refresh() reconciliará
    final st = ev.state;
    if (st == null || st.isEmpty) return;
    // Volumen del socket viene 0-100 (UPnP nativo) → reescala a la escala DISPLAY
    // de la barra igual que el backend (volume-scale.ts: round(upnp/3), factor 3
    // MEDIDO — NO 100/kJblVolMax; UPnP 33 ⇒ display 11). Con *31/100 el push
    // mostraba un número distinto al seed REST (toDeviceVolume) para el mismo vol.
    final int? nextVolume = !st.containsKey('volume')
        ? s.volume
        : (st['volume'] == null
            ? s.volume
            : ((st['volume'] as num) / 3).round().clamp(0, kJblVolMax));
    _status = JblStatus(
      online: st.containsKey('reachable') ? st['reachable'] != false : s.online,
      ip: s.ip,
      name: s.name,
      volume: nextVolume,
      muted: st.containsKey('muted') && st['muted'] is bool
          ? st['muted'] as bool
          : s.muted,
      power: st.containsKey('on') ? (st['on'] == true ? 'on' : 'off') : s.power,
      source: st.containsKey('mediaInput') ? st['mediaInput'] as String? : s.source,
      transport: s.transport,
      nightMode: s.nightMode,
    );
    _safeNotify();
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
    // UI/control acotado a 0-[kJblVolMax] = escala de display de la barra
    // (la API la convierte a UPnP nativo).
    final clamped = volume.clamp(0, kJblVolMax);
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

  /// Ajusta el volumen de a 1 (paso fijo, igual que el dial). Pasa `step: 1`
  /// al backend y clampa el volumen retornado a 0-[kJblVolMax] para que − / +
  /// coincidan con el dial (la API soporta 0-100; acá acotamos a 0-33).
  Future<bool> nudgeVolume(int delta) async {
    if (!canCommand) return false;
    // Cap duro 0-[kJblVolMax]: si ya está en el extremo no manda el comando, así
    // − / + nunca empujan el device fuera del rango 0-33 (la API soporta 0-100).
    final current = _status!.volume ?? 0;
    if (delta > 0 && current >= kJblVolMax) return true;
    if (delta < 0 && current <= 0) return true;
    try {
      final returned = delta >= 0
          ? await _api.jblVolumeUp(step: 1)
          : await _api.jblVolumeDown(step: 1);
      _status = _status!.copyWith(volume: returned.clamp(0, kJblVolMax));
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

  /// "Night listening" (Personal Listening Mode). Pisa optimista y revierte en
  /// catch (igual que [toggleMute]); el toggle real lo resuelve el backend.
  Future<bool> toggleNightMode() async {
    if (!canCommand) return false;
    final prev = _status!.nightMode;
    _status = _status!.copyWith(nightMode: !(prev ?? false));
    _safeNotify();
    try {
      await _api.toggleJblNightMode();
      return true;
    } catch (e) {
      _restoreNightMode(prev);
      _safeNotify();
      debugPrint('JblService toggleNightMode error: $e');
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
  ///
  /// [name] opcional: sin nombre reproduce la radio favorita por defecto del
  /// backend (Heart/favorito → POST /jbl/radio/play sin body).
  Future<bool> playRadio([String? name]) async {
    try {
      await _api.playJblRadio(name: name);
      await refresh();
      return true;
    } catch (e) {
      debugPrint('JblService playRadio error: $e');
      return false;
    }
  }

  /// Envía una tecla del remote (allowlist [JblRemoteKeys]). NO gatea por
  /// `online`: varias teclas (tv/hdmi/bluetooth/playpause) despiertan la barra
  /// desde standby. Gatea sólo por estado conocido (`_status != null`); el
  /// backend devuelve `ok:false` sin romper si la barra rechaza/está offline.
  /// Sin optimismo de estado (son press momentáneos/toggle sin lectura).
  Future<bool> sendRemoteKey(String id) async {
    if (_status == null) return false;
    try {
      final ok = await _api.jblSendRemoteKey(id);
      // playpause puede cambiar el transporte: refrescamos para reflejarlo.
      if (ok && id == JblRemoteKeys.playpause) {
        await refresh();
      }
      return ok;
    } catch (e) {
      // jblSendRemoteKey lanza ante cualquier status != 200/201 (p.ej. 404 si
      // la ruta no está desplegada, o 502 si la barra es inalcanzable). Sin
      // este try/catch la excepción escapa de _handle y no se muestra el
      // SnackBar; degradamos a false como el resto de los comandos.
      debugPrint('JblService sendRemoteKey error: $e');
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
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
