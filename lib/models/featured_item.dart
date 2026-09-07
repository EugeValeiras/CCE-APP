/// Ítems de la sección "Destacados" de la home (editable por el usuario).
///
/// Se persisten en SharedPreferences como lista de strings `kind` o
/// `kind:id` (ej. 'tv', 'thermostat:dev_abc', 'scene:sc_1', 'light:dev_x').
/// Modelo PURO (sin Flutter) para testear encode/decode standalone.
library;

enum FeaturedKind {
  tv,
  jbl,
  thermostat,
  vacuum,
  /// Teléfono 4G (dev_phone). Como el robot, es un [Device] con card propia.
  phone,
  light,
  button,
  lock,
  sensor,
  scene,
  hueScene,
  automation,
}

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

  /// Migración de la card "TV" única a una card por aparato (CCE#130).
  ///
  /// Un `tv` guardado SIN id es de cuando había una sola card de televisor y
  /// cuál controlaba lo decidía el estado global del servicio. Se expande, EN
  /// SU LUGAR, a un ítem por Samsung ([deviceIds] son los devices canónicos,
  /// `dev_tv` / `dev_tv-ce588d39`), que es lo que la home ofrece ahora.
  ///
  /// Con la lista de aparatos todavía sin cargar ([deviceIds] vacía) devuelve
  /// **la misma instancia** sin tocar nada: quien ya tenía la card destacada
  /// tiene que seguir viéndola, y un `tv` sin id sigue renderizando la card del
  /// aparato por defecto. Comparar con `identical` dice si hubo migración y
  /// por lo tanto si hay que persistir.
  static List<FeaturedItem> expandLegacyTv(
    List<FeaturedItem> items,
    List<String> deviceIds,
  ) {
    if (deviceIds.isEmpty) return items;
    final hasLegacy =
        items.any((i) => i.kind == FeaturedKind.tv && i.id == null);
    if (!hasLegacy) return items;
    final out = <FeaturedItem>[];
    final seen = <FeaturedItem>{};
    for (final item in items) {
      final expansion = item.kind == FeaturedKind.tv && item.id == null
          ? [for (final id in deviceIds) FeaturedItem(FeaturedKind.tv, id)]
          : [item];
      for (final e in expansion) {
        // Dedupe: el aparato podía estar destacado además del `tv` genérico, y
        // dos ítems iguales rompen las keys del reorder del editor.
        if (seen.add(e)) out.add(e);
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is FeaturedItem && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => encode();
}
