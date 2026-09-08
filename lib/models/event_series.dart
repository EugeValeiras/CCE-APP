// Las series agregadas de `GET /api/events/series` (CCE#129).
//
// El servidor agrega con `time_bucket` sobre la hypertable y devuelve un punto
// por bucket, ya descontando el arrastre del bloque sensor y el eco del canal
// websocket. La app dibuja lo que llega: no recorta, no promedia y no decide
// qué lectura vale — todo eso pasa donde están los datos.

/// Un punto: el bucket, su promedio y el rango que hubo adentro.
class SeriesPoint {
  const SeriesPoint({
    required this.t,
    required this.avg,
    required this.min,
    required this.max,
    required this.count,
  });

  /// Comienzo del bucket, en hora LOCAL (el servidor lo manda en UTC).
  final DateTime t;
  final double avg;
  final double min;
  final double max;

  /// Cuántas lecturas entraron en el bucket. Nunca 0: el servidor no manda
  /// buckets vacíos.
  final int count;

  static SeriesPoint? fromJson(Map<String, dynamic> json) {
    final t = json['t'];
    final avg = json['avg'];
    if (t is! String || avg is! num) return null;
    final parsed = DateTime.tryParse(t);
    if (parsed == null) return null;
    final min = json['min'];
    final max = json['max'];
    return SeriesPoint(
      t: parsed.toLocal(),
      avg: avg.toDouble(),
      min: min is num ? min.toDouble() : avg.toDouble(),
      max: max is num ? max.toDouble() : avg.toDouble(),
      count: (json['count'] as num?)?.toInt() ?? 1,
    );
  }
}

/// La serie de UN campo de UN binding.
class EventSeries {
  const EventSeries({
    required this.globalId,
    required this.field,
    required this.unit,
    required this.points,
  });

  final String globalId;

  /// 'temperature' | 'humidity' | 'lux' | 'currentTemp'.
  final String field;

  /// '°C' | '%' | 'lx'. Viene del servidor para no inventarla acá.
  final String unit;

  final List<SeriesPoint> points;

  static EventSeries fromJson(Map<String, dynamic> json) {
    final raw = json['points'];
    final points = <SeriesPoint>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          final point = SeriesPoint.fromJson(Map<String, dynamic>.from(p));
          if (point != null) points.add(point);
        }
      }
    }
    return EventSeries(
      globalId: json['globalId']?.toString() ?? '',
      field: json['field']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      points: points,
    );
  }
}

/// La respuesta entera. `from`/`to` son el rango EFECTIVO: lo que el gráfico
/// muestra es lo que dicen estos dos campos, no lo que dice el botón que se
/// apretó (que es exactamente el defecto que este endpoint vino a arreglar).
class EventSeriesPage {
  const EventSeriesPage({
    required this.bucket,
    required this.bucketSeconds,
    required this.from,
    required this.to,
    required this.series,
    required this.enabled,
  });

  final String bucket;
  final int bucketSeconds;
  final DateTime from;
  final DateTime to;
  final List<EventSeries> series;

  /// false cuando el event store está apagado: no hay historial que mostrar,
  /// y no es lo mismo que "este rango no tuvo lecturas".
  final bool enabled;

  static EventSeriesPage fromJson(Map<String, dynamic> json) {
    final raw = json['series'];
    final series = <EventSeries>[];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) series.add(EventSeries.fromJson(Map<String, dynamic>.from(s)));
      }
    }
    return EventSeriesPage(
      bucket: json['bucket']?.toString() ?? 'auto',
      bucketSeconds: (json['bucketSeconds'] as num?)?.toInt() ?? 0,
      from: DateTime.tryParse(json['from']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      to: DateTime.tryParse(json['to']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      series: series,
      enabled: json['enabled'] != false,
    );
  }

  /// Las series de UN campo, fusionadas en una sola línea.
  ///
  /// Un termómetro de la casa está MERGEADO: el "Termómetro living" es un
  /// aparato con dos bindings (`ewelink_acc4001d73` y el endpoint Matter), y
  /// los dos reportan la misma magnitud por caminos distintos. Se piden los
  /// dos —si uno se queda mudo una tarde, el otro tiene el dato— y acá se
  /// unen: un aparato, una línea.
  ///
  /// Los buckets que traen los dos bindings se promedian PONDERANDO por
  /// `count`: los dos miden el mismo sensor, así que el valor no cambia, pero
  /// un binding con 30 lecturas no puede pesar lo mismo que otro con una.
  List<SeriesPoint> merged(String field) {
    final byBucket = <int, List<SeriesPoint>>{};
    for (final s in series) {
      if (s.field != field) continue;
      for (final p in s.points) {
        (byBucket[p.t.millisecondsSinceEpoch] ??= <SeriesPoint>[]).add(p);
      }
    }
    final keys = byBucket.keys.toList()..sort();
    return [
      for (final k in keys)
        if (byBucket[k]!.length == 1)
          byBucket[k]!.first
        else
          _average(byBucket[k]!),
    ];
  }

  static SeriesPoint _average(List<SeriesPoint> group) {
    var peso = 0;
    var suma = 0.0;
    var min = group.first.min;
    var max = group.first.max;
    for (final p in group) {
      peso += p.count;
      suma += p.avg * p.count;
      if (p.min < min) min = p.min;
      if (p.max > max) max = p.max;
    }
    return SeriesPoint(
      t: group.first.t,
      avg: peso == 0 ? group.first.avg : suma / peso,
      min: min,
      max: max,
      count: peso,
    );
  }

  /// La unidad de un campo, según la dijo el servidor.
  String unitOf(String field) {
    for (final s in series) {
      if (s.field == field && s.unit.isNotEmpty) return s.unit;
    }
    return '';
  }
}
