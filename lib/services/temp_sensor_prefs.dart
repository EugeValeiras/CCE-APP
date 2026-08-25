import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Termómetro elegido por el usuario para cada habitación (y para toda la casa
/// con `roomId == null`), cacheado en memoria.
///
/// La elección siempre vivió en SharedPreferences (`home.tempSensorId.<roomId>`,
/// escrita por el picker del detalle de la habitación), pero leerla es `async`
/// y el badge del `RoomCard` la necesita DENTRO de un build: de ahí el cache.
///
/// Es un [ChangeNotifier] para que elegir un termómetro en el detalle actualice
/// el badge de la home sin volver a entrar a la pantalla, y singleton porque el
/// picker vive tres niveles más abajo que las listas que muestran el badge —
/// cablearlo por constructor obligaría a tocar todo el árbol para pasar una
/// preferencia local.
class TempSensorPrefs extends ChangeNotifier {
  TempSensorPrefs._();

  static final TempSensorPrefs instance = TempSensorPrefs._();

  /// Namespace histórico. `roomId == null` ⇒ hero de toda la casa (phone y
  /// tablet comparten esa key: un solo termómetro de la casa).
  static const String keyPrefix = 'home.tempSensorId';

  static String keyFor(String? roomId) =>
      roomId == null ? keyPrefix : '$keyPrefix.$roomId';

  final Map<String, String> _byKey = {};
  Future<void>? _loading;

  /// Id elegido para [roomId], o null si nunca se eligió (⇒ fallback al primer
  /// sensor del pool, que resuelve `RoomTemperature`).
  String? idFor(String? roomId) => _byKey[keyFor(roomId)];

  /// Carga el cache una sola vez por sesión. Idempotente: los call-sites la
  /// invocan en su initState sin coordinarse.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(keyPrefix)) continue;
        final value = prefs.getString(key);
        // putIfAbsent, no asignación: si el usuario eligió un termómetro
        // MIENTRAS esta carga estaba en vuelo, su elección (ya en el cache y
        // camino al disco) gana sobre el valor viejo que acabamos de leer.
        if (value != null) _byKey.putIfAbsent(key, () => value);
      }
      notifyListeners();
    } catch (_) {
      // Sin prefs se sigue con el fallback "primer sensor": el badge muestra
      // algo razonable en vez de nada.
    }
  }

  /// Persiste la elección de [roomId] y avisa YA (optimista): el header y el
  /// badge se actualizan sin esperar al disco.
  Future<void> select(String? roomId, String sensorId) async {
    final key = keyFor(roomId);
    if (_byKey[key] == sensorId) return;
    _byKey[key] = sensorId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, sensorId);
    } catch (_) {}
  }

  /// SOLO TESTS: siembra el cache sin tocar disco y da la carga por hecha.
  @visibleForTesting
  void debugSeed(Map<String?, String> byRoomId) {
    _byKey
      ..clear()
      ..addEntries(
          byRoomId.entries.map((e) => MapEntry(keyFor(e.key), e.value)));
    _loading = Future.value();
    notifyListeners();
  }

  /// SOLO TESTS: vacía el cache y permite volver a cargar (el singleton
  /// sobrevive entre tests del mismo archivo).
  @visibleForTesting
  void debugReset() {
    _byKey.clear();
    _loading = null;
  }
}
