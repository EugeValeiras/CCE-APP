/// Ítems de la sección "Destacados" de la home (editable por el usuario).
///
/// Se persisten en SharedPreferences como lista de strings `kind` o
/// `kind:id` (ej. 'tv', 'thermostat:dev_abc', 'scene:sc_1', 'light:dev_x').
/// Modelo PURO (sin Flutter) para testear encode/decode standalone.
library;

enum FeaturedKind { tv, jbl, thermostat, vacuum, light, scene, hueScene, automation }

class FeaturedItem {
  final FeaturedKind kind;

  /// Id del device/escena/automatización. null para tv/jbl (singletons con
  /// service dedicado).
  final String? id;

  const FeaturedItem(this.kind, [this.id]);

  /// Codificación estable para prefs: 'kind' o 'kind:id'.
  String encode() => id == null ? kind.name : '${kind.name}:$id';

  /// Decodifica una entrada persistida; null si es basura/kind desconocido
  /// (una versión vieja de la app con kinds nuevos no debe romper).
  static FeaturedItem? decode(String raw) {
    final sep = raw.indexOf(':');
    final kindName = sep == -1 ? raw : raw.substring(0, sep);
    final id = sep == -1 ? null : raw.substring(sep + 1);
    for (final k in FeaturedKind.values) {
      if (k.name == kindName) {
        if (id != null && id.isEmpty) return null;
        return FeaturedItem(k, id);
      }
    }
    return null;
  }

  static List<FeaturedItem> decodeList(List<String>? raw) {
    if (raw == null) return const [];
    return raw.map(decode).whereType<FeaturedItem>().toList();
  }

  static List<String> encodeList(List<FeaturedItem> items) =>
      items.map((i) => i.encode()).toList();

  @override
  bool operator ==(Object other) =>
      other is FeaturedItem && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => encode();
}
