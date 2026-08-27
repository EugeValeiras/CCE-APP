/// Formateo de tiempos compartido (historial, automatizaciones).
///
/// Sin dependencia de `intl`: nombres de día en español hardcodeados.
abstract final class TimeFormat {
  // Índice = weekday % 7 (DateTime: lunes=1..domingo=7 → domingo%7=0).
  static const List<String> _daysAbbr = [
    'dom',
    'lun',
    'mar',
    'mié',
    'jue',
    'vie',
    'sáb',
  ];
  static const List<String> _daysUpper = [
    'DOMINGO',
    'LUNES',
    'MARTES',
    'MIÉRCOLES',
    'JUEVES',
    'VIERNES',
    'SÁBADO',
  ];

  /// Parsea un ISO-8601 del backend. Si NO trae sufijo de zona
  /// ('Z' o '±HH:MM'), Dart lo interpretaría como hora local — acá se trata
  /// como UTC (es lo que manda el server) y SIEMPRE se devuelve `.toLocal()`.
  static DateTime parseEventTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (parsed.isUtc) return parsed.toLocal();
    // Sin sufijo: reinterpretar los mismos campos como UTC.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toLocal();
  }

  /// Tiempo relativo en escala:
  /// <60 s "ahora" (clamp: diff negativo < −90 s ⇒ hora absoluta "HH:mm");
  /// <60 min "hace N min"; hoy "14:32"; ayer "ayer 23:10";
  /// <7 días "mar 14:32"; resto "12/06".
  static String relative(DateTime ts, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = ts.toLocal();
    final diff = n.difference(local);
    if (diff.inSeconds < -90) return hm(local);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (_sameDay(local, n)) return hm(local);
    if (_sameDay(local, n.subtract(const Duration(days: 1)))) {
      return 'ayer ${hm(local)}';
    }
    if (diff.inDays < 7) {
      return '${_daysAbbr[local.weekday % 7]} ${hm(local)}';
    }
    return '${_two(local.day)}/${_two(local.month)}';
  }

  /// Momento FUTURO en escala: "hoy 19:04", "mañana 02:00", "lun 07:30" (<7
  /// días), "12/06 07:30". Para "Próxima …" de una automatización programada.
  static String upcoming(DateTime ts, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = ts.toLocal();
    if (_sameDay(local, n)) return 'hoy ${hm(local)}';
    if (_sameDay(local, n.add(const Duration(days: 1)))) {
      return 'mañana ${hm(local)}';
    }
    if (local.difference(n).inDays < 7) {
      return '${_daysAbbr[local.weekday % 7]} ${hm(local)}';
    }
    return '${_two(local.day)}/${_two(local.month)} ${hm(local)}';
  }

  /// "desde cuándo" un estado se mantiene: "desde las 08:02" (hoy), "desde
  /// ayer 22:14", "desde el lun 07:30" (<7 días), "desde el 12/06".
  static String since(DateTime ts, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = ts.toLocal();
    if (_sameDay(local, n)) return 'desde las ${hm(local)}';
    if (_sameDay(local, n.subtract(const Duration(days: 1)))) {
      return 'desde ayer ${hm(local)}';
    }
    if (n.difference(local).inDays < 7) {
      return 'desde el ${_daysAbbr[local.weekday % 7]} ${hm(local)}';
    }
    return 'desde el ${_two(local.day)}/${_two(local.month)}';
  }

  /// [relative] convertido en complemento de una oración: "ahora", "hace 5
  /// min", "a las 14:32", "ayer 23:10", "el mar 14:32", "el 12/06". Para
  /// "Se ejecutó …".
  static String relativeInSentence(DateTime ts, {DateTime? now}) {
    final r = relative(ts, now: now);
    if (r == 'ahora' || r.startsWith('hace') || r.startsWith('ayer')) return r;
    if (r.contains('/')) return 'el $r';
    if (RegExp(r'^\d').hasMatch(r)) return 'a las $r';
    return 'el $r';
  }

  /// "14:32"
  static String hm(DateTime ts) {
    final local = ts.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// "14:32:05" (sub-filas expandidas del historial)
  static String hms(DateTime ts) {
    final local = ts.toLocal();
    return '${hm(local)}:${_two(local.second)}';
  }

  /// "HOY" / "AYER" / "MARTES 10/06" para headers de sección.
  static String dayLabel(DateTime ts, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = ts.toLocal();
    if (_sameDay(local, n)) return 'HOY';
    if (_sameDay(local, n.subtract(const Duration(days: 1)))) return 'AYER';
    return '${_daysUpper[local.weekday % 7]} '
        '${_two(local.day)}/${_two(local.month)}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _two(int n) => n.toString().padLeft(2, '0');
}
