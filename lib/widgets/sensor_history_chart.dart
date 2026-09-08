import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/event_series.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../theme/cce_tokens.dart';
import '../views/history/numeric_readings.dart';

/// Gráfico del historial de un sensor (CCE#129): una o dos series con ejes,
/// leyenda, selector de rango y toque para leer un punto.
///
/// Reemplaza al sparkline de siete días que mostraba doce horas. El defecto no
/// era el dibujo sino de dónde salían los datos: pedía los últimos 1000
/// eventos crudos y recién ahí descartaba los de más de una semana, así que en
/// un sensor que reporta seguido el rango lo decidía el límite de filas. Ahora
/// el rango viaja a `GET /api/events/series`, el servidor agrega con
/// `time_bucket`, y **el rótulo sale de lo que el servidor contesta**
/// (`from`/`to` de la respuesta), no del botón que se apretó.
///
/// Sirve al termómetro y al termostato con el mismo componente: la indirección
/// que antes era el `reader` del payload ahora es [fields] —el termómetro pide
/// `temperature,humidity` y el termostato `currentTemp`—, y el mapeo de cada
/// campo al lugar del evento vive en el servidor, en un solo lugar.
class SensorHistoryChart extends StatefulWidget {
  const SensorHistoryChart({
    super.key,
    required this.config,
    required this.globalIds,
    required this.fields,
  });

  final ServerConfig config;

  /// Los BINDINGS del device (`d.bindingIds`), todos: un termómetro mergeado
  /// reporta por eWeLink y por Matter, y si uno se queda mudo una tarde el
  /// otro tiene el dato. El servidor los agrega y [EventSeriesPage.merged] los
  /// une en una línea.
  final List<String> globalIds;

  /// Qué se grafica, en orden: el primero manda la escala izquierda y el
  /// segundo (si hay) la derecha.
  final List<String> fields;

  @override
  State<SensorHistoryChart> createState() => _SensorHistoryChartState();
}

/// Los presets del selector. El rango arbitrario no está acá: sale del
/// calendario y se guarda como `DateTimeRange`.
enum ChartRange {
  day('24 H', Duration(hours: 24)),
  week('7 D', Duration(days: 7)),
  month('30 D', Duration(days: 30));

  const ChartRange(this.label, this.span);
  final String label;
  final Duration span;
}

class _SensorHistoryChartState extends State<SensorHistoryChart> {
  ChartRange _preset = ChartRange.day;
  DateTimeRange? _custom;

  EventSeriesPage? _page;
  bool _loading = true;
  bool _failed = false;

  /// Qué punto está tocado, por índice del bucket de la primera serie.
  int? _touched;

  /// Descarta la respuesta de un pedido que quedó viejo: tocar 24 H y 7 D
  /// rápido puede resolver al revés y dejar en pantalla el rango que no es.
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SensorHistoryChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.globalIds, widget.globalIds) ||
        !listEquals(old.fields, widget.fields)) {
      _load();
    }
  }

  DateTimeRange get _range {
    final custom = _custom;
    if (custom != null) return custom;
    final to = DateTime.now();
    return DateTimeRange(start: to.subtract(_preset.span), end: to);
  }

  Future<void> _load() async {
    if (widget.globalIds.isEmpty) return;
    final id = ++_reqId;
    setState(() {
      _loading = true;
      _failed = false;
      _touched = null;
    });
    try {
      final range = _range;
      final page = await ApiService(widget.config).getEventSeries(
        globalIds: widget.globalIds,
        fields: widget.fields,
        from: range.start,
        to: range.end,
      );
      if (!mounted || id != _reqId) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // El techo del calendario es la retención de la hypertable: ofrecer
      // fechas donde el servidor ya borró los datos sería mentir otra vez.
      firstDate: now.subtract(const Duration(days: 180)),
      lastDate: now,
      initialDateRange: _custom,
      helpText: 'Rango del historial',
      saveText: 'Ver',
    );
    if (picked == null) return;
    setState(() {
      // El día elegido va COMPLETO: un rango que termina a las 00:00 del
      // último día deja afuera el día que el dueño acaba de pedir.
      _custom = DateTimeRange(
        start: picked.start,
        end: DateTime(picked.end.year, picked.end.month, picked.end.day)
            .add(const Duration(days: 1)),
      );
    });
    await _load();
  }

  void _selectPreset(ChartRange r) {
    setState(() {
      _preset = r;
      _custom = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.globalIds.isEmpty) return const SizedBox.shrink();
    final page = _page;
    final lines = <_ChartLine>[];
    if (page != null) {
      for (final field in widget.fields) {
        final points = page.merged(field);
        if (points.isEmpty) continue;
        lines.add(_ChartLine(
          field: field,
          points: points,
          unit: page.unitOf(field),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: CceColors.neoSunken,
          borderRadius: BorderRadius.circular(16),
          boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RangeChips(
              preset: _custom == null ? _preset : null,
              onPreset: _selectPreset,
              onPick: _pickRange,
            ),
            const SizedBox(height: 10),
            // El rótulo sale de la RESPUESTA, no del preset: lo que dice es lo
            // que se está mostrando, con el ancho del bucket incluido para que
            // se entienda qué es cada punto.
            Text(
              page == null
                  ? rangeLabel(_range.start, _range.end)
                  : '${rangeLabel(page.from, page.to)} · ${bucketLabel(page.bucket)}',
              style: CceText.caption.copyWith(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: CceColors.neoTextSub,
              ),
            ),
            const SizedBox(height: 10),
            if (lines.isNotEmpty) ...[
              _Legend(lines: lines),
              const SizedBox(height: 8),
            ],
            SizedBox(height: 132, child: _body(lines)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<_ChartLine> lines) {
    if (_loading && _page == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_failed) {
      return _Message(
        text: 'No se pudo cargar el historial',
        action: TextButton(onPressed: _load, child: const Text('Reintentar')),
      );
    }
    final page = _page;
    if (page != null && !page.enabled) {
      return const _Message(text: 'El historial está desactivado');
    }
    if (lines.isEmpty) {
      return const _Message(text: 'Sin lecturas en este rango');
    }

    return LayoutBuilder(
      builder: (context, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _touch(d.localPosition.dx, box.maxWidth, lines),
          onHorizontalDragUpdate: (d) =>
              _touch(d.localPosition.dx, box.maxWidth, lines),
          onHorizontalDragEnd: (_) => setState(() => _touched = null),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  // La usan los tests para tocar el área del gráfico sin
                  // adivinar cuál de los CustomPaint de la pantalla es.
                  key: const ValueKey('sensor-history-plot'),
                  painter: _ChartPainter(
                    lines: lines,
                    from: _page?.from ?? _range.start,
                    to: _page?.to ?? _range.end,
                    touched: _touched,
                  ),
                ),
              ),
              if (_touched != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _Tooltip(lines: lines, index: _touched!),
                ),
              if (_loading)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _touch(double dx, double width, List<_ChartLine> lines) {
    final points = lines.first.points;
    if (points.isEmpty) return;
    final from = (_page?.from ?? _range.start).millisecondsSinceEpoch;
    final to = (_page?.to ?? _range.end).millisecondsSinceEpoch;
    final span = math.max(1, to - from);
    final x = dx.clamp(_ChartPainter.padLeft, width - _ChartPainter.padRight);
    final usable = math.max(
      1.0,
      width - _ChartPainter.padLeft - _ChartPainter.padRight,
    );
    final at = from + ((x - _ChartPainter.padLeft) / usable * span).round();
    var best = 0;
    var bestDist = (points.first.t.millisecondsSinceEpoch - at).abs();
    for (var i = 1; i < points.length; i++) {
      final d = (points[i].t.millisecondsSinceEpoch - at).abs();
      if (d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    if (best != _touched) setState(() => _touched = best);
  }
}

/// Una línea del gráfico: un campo, ya fusionado entre bindings.
class _ChartLine {
  const _ChartLine({
    required this.field,
    required this.points,
    required this.unit,
  });

  final String field;
  final List<SeriesPoint> points;
  final String unit;

  /// El color y el formato salen de `numericReadings`, la misma tabla que usa
  /// el historial (CCE#112): naranja para la temperatura, azul para la
  /// humedad. Inventarlos acá era garantizar que se despeguen.
  NumericReading? get spec {
    final key = field == 'currentTemp' ? 'temperature' : field;
    for (final r in numericReadings) {
      if (r.key == key) return r;
    }
    return null;
  }

  Color get color => spec?.color ?? CceColors.warm;

  String get title {
    switch (field) {
      case 'humidity':
        return 'Humedad';
      case 'lux':
        return 'Luz';
      default:
        return 'Temperatura';
    }
  }

  String format(double v) => spec?.format(v) ?? v.toStringAsFixed(1);

  double get min => points.map((p) => p.min).reduce(math.min);
  double get max => points.map((p) => p.max).reduce(math.max);
}

// ── Las funciones del eje, puras y probadas aparte ─────────────────────────

/// El rótulo del rango, en castellano y con la fecha REAL que se está
/// mostrando. Nunca dice "últimos 7 días": dice del 1 al 8 de septiembre.
String rangeLabel(DateTime from, DateTime to) {
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  String dia(DateTime d) => '${d.day} ${meses[d.month - 1]}';
  String hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  final span = to.difference(from);
  if (span.inHours <= 26) {
    final mismoDia = from.year == to.year &&
        from.month == to.month &&
        from.day == to.day;
    if (mismoDia) return '${dia(from)} · ${hora(from)} – ${hora(to)}';
    return '${dia(from)} ${hora(from)} – ${dia(to)} ${hora(to)}';
  }
  return '${dia(from)} – ${dia(to)}';
}

/// 'prom. 1 h': qué representa cada punto. Sin esto, dos gráficos con la misma
/// forma y distinto bucket parecen la misma medición.
String bucketLabel(String bucket) {
  switch (bucket) {
    case '1m':
      return 'prom. 1 min';
    case '5m':
      return 'prom. 5 min';
    case '15m':
      return 'prom. 15 min';
    case '1h':
      return 'prom. 1 h';
    case '6h':
      return 'prom. 6 h';
    case '1d':
      return 'prom. 1 día';
    default:
      return 'promedio';
  }
}

/// Las marcas del eje de valores: números redondos dentro del rango, con un
/// paso de 1, 2 ó 5 por década. Devuelve al menos una marca aunque el sensor
/// no se haya movido en todo el rango (una línea plana también tiene valor).
List<double> valueTicks(double min, double max, {int target = 3}) {
  if (!min.isFinite || !max.isFinite) return const [];
  if ((max - min).abs() < 1e-9) return [min];
  final crudo = (max - min) / target;
  final magnitud = math.pow(10, (math.log(crudo) / math.ln10).floor()).toDouble();
  final norm = crudo / magnitud;
  final paso = (norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))) * magnitud;
  final ticks = <double>[];
  var v = (min / paso).ceil() * paso;
  while (v <= max + 1e-9 && ticks.length < 8) {
    ticks.add(double.parse(v.toStringAsFixed(6)));
    v += paso;
  }
  return ticks.isEmpty ? [min, max] : ticks;
}

/// Las marcas del eje de tiempo, con su etiqueta: horas cuando el rango es de
/// horas, días cuando es de días. El paso se elige para que entren entre tres
/// y seis marcas, que es lo que se lee en el ancho de un teléfono.
List<({DateTime t, String label})> timeTicks(DateTime from, DateTime to) {
  final span = to.difference(from);
  final out = <({DateTime t, String label})>[];
  String hh(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h';
  String dm(DateTime d) => '${d.day}/${d.month}';

  if (span.inHours <= 36) {
    final paso = span.inHours <= 12 ? 3 : 6;
    var t = DateTime(from.year, from.month, from.day, from.hour);
    while (t.hour % paso != 0) {
      t = t.add(const Duration(hours: 1));
    }
    while (t.isBefore(to)) {
      if (!t.isBefore(from)) out.add((t: t, label: hh(t)));
      t = t.add(Duration(hours: paso));
    }
    return out;
  }

  final dias = math.max(1, (span.inDays / 5).ceil());
  var t = DateTime(from.year, from.month, from.day).add(Duration(days: dias));
  while (t.isBefore(to)) {
    out.add((t: t, label: dm(t)));
    t = t.add(Duration(days: dias));
  }
  return out;
}

// ── Piezas de UI ───────────────────────────────────────────────────────────

class _RangeChips extends StatelessWidget {
  const _RangeChips({
    required this.preset,
    required this.onPreset,
    required this.onPick,
  });

  /// null cuando está activo un rango arbitrario del calendario.
  final ChartRange? preset;
  final ValueChanged<ChartRange> onPreset;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in ChartRange.values) ...[
          _Chip(
            label: r.label,
            selected: preset == r,
            onTap: () => onPreset(r),
          ),
          const SizedBox(width: 6),
        ],
        _Chip(
          label: 'FECHAS',
          selected: preset == null,
          onTap: onPick,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? CceColors.warm.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? CceColors.warm.withValues(alpha: 0.55)
                : CceColors.textTertiary.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: CceText.caption.copyWith(
            fontSize: 10,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: selected ? CceColors.warm : CceColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.lines});

  final List<_ChartLine> lines;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final l in lines)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                '${l.title} ${l.format(l.min)} – ${l.format(l.max)}',
                style: CceText.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CceColors.textTertiary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.lines, required this.index});

  final List<_ChartLine> lines;
  final int index;

  @override
  Widget build(BuildContext context) {
    final base = lines.first.points;
    if (index >= base.length) return const SizedBox.shrink();
    final at = base[index].t;
    final partes = <String>[];
    for (final l in lines) {
      final p = _closest(l.points, at);
      if (p != null) partes.add(l.format(p.avg));
    }
    final hora = '${at.day}/${at.month} '
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$hora · ${partes.join(' · ')}',
          style: CceText.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: CceColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// El punto del bucket más cercano: las dos series comparten el eje de
  /// tiempo pero no tienen por qué tener los mismos buckets (la humedad puede
  /// faltar en una hora en la que sí hubo temperatura).
  static SeriesPoint? _closest(List<SeriesPoint> points, DateTime at) {
    SeriesPoint? best;
    var bestDist = 0;
    for (final p in points) {
      final d = p.t.difference(at).inMilliseconds.abs();
      if (best == null || d < bestDist) {
        best = p;
        bestDist = d;
      }
    }
    return best;
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: CceText.caption.copyWith(
              fontSize: 12,
              color: CceColors.textTertiary,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Dibuja las líneas, la grilla y los dos ejes de valores.
///
/// Dos escalas: la serie de la izquierda manda el eje izquierdo y la segunda
/// (la humedad) el derecho. Compartir escala entre grados y porcentaje aplasta
/// las dos curvas contra los bordes y no se lee ninguna.
class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.lines,
    required this.from,
    required this.to,
    required this.touched,
  });

  // Los márgenes los fijan las ETIQUETAS de los ejes, no la estética: a 9 px,
  // '22.0°' mide unos 22 y '1000 lx' unos 34. Con menos que esto, la marca del
  // eje se come el borde de la cápsula.
  static const padLeft = 36.0;
  static const padRight = 36.0;
  static const padTop = 6.0;
  static const padBottom = 16.0;

  final List<_ChartLine> lines;
  final DateTime from;
  final DateTime to;
  final int? touched;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - padLeft - padRight;
    final plotH = size.height - padTop - padBottom;
    if (plotW <= 0 || plotH <= 0 || lines.isEmpty) return;

    final t0 = from.millisecondsSinceEpoch;
    final tspan = math.max(1, to.millisecondsSinceEpoch - t0).toDouble();
    double xOf(DateTime t) =>
        padLeft + (t.millisecondsSinceEpoch - t0) / tspan * plotW;

    // Eje de tiempo.
    final ejePaint = Paint()
      ..color = CceColors.textTertiary.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (final tick in timeTicks(from, to)) {
      final x = xOf(tick.t);
      if (x < padLeft || x > padLeft + plotW) continue;
      canvas.drawLine(
        Offset(x, padTop),
        Offset(x, padTop + plotH),
        ejePaint,
      );
      _text(canvas, tick.label, Offset(x, padTop + plotH + 3),
          align: TextAlign.center);
    }

    // Escalas: [min, max] con un respiro arriba y abajo para que la línea no
    // toque el borde.
    final escalas = <(double, double)>[];
    for (final l in lines) {
      var lo = l.min;
      var hi = l.max;
      if ((hi - lo).abs() < 0.5) {
        lo -= 0.5;
        hi += 0.5;
      }
      final aire = (hi - lo) * 0.12;
      escalas.add((lo - aire, hi + aire));
    }

    double yOf(int serie, double v) {
      final (lo, hi) = escalas[serie];
      final rango = (hi - lo) == 0 ? 1.0 : (hi - lo);
      return padTop + plotH - ((v - lo) / rango) * plotH;
    }

    // Marcas de valor: la primera serie a la izquierda, la segunda a la
    // derecha, cada una con el color de su línea.
    for (var i = 0; i < lines.length && i < 2; i++) {
      final l = lines[i];
      for (final v in valueTicks(l.min, l.max)) {
        final y = yOf(i, v);
        if (y < padTop - 1 || y > padTop + plotH + 1) continue;
        if (i == 0) {
          canvas.drawLine(
            Offset(padLeft, y),
            Offset(padLeft + plotW, y),
            ejePaint,
          );
        }
        _text(
          canvas,
          l.format(v),
          Offset(i == 0 ? padLeft - 3 : padLeft + plotW + 3, y - 6),
          align: i == 0 ? TextAlign.right : TextAlign.left,
          color: l.color.withValues(alpha: 0.75),
          // El margen es fijo y el texto no: con la letra agrandada por
          // accesibilidad, una marca de cuatro dígitos se comería el gráfico.
          // Antes que pisarlo, esa marca no se dibuja.
          maxWidth: (i == 0 ? padLeft : padRight) - 3,
        );
      }
    }

    // Las líneas, recortadas al área de dibujo: un punto que caiga fuera de la
    // escala (o un rango que el servidor devuelva más ancho de lo pedido) no
    // puede pintar encima de las etiquetas.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padLeft, 0, plotW, size.height));
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final path = Path();
      for (var j = 0; j < l.points.length; j++) {
        final p = l.points[j];
        final x = xOf(p.t);
        final y = yOf(i, p.avg);
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = l.color;
      if (l.points.length == 1) {
        canvas.drawCircle(
          Offset(xOf(l.points.first.t), yOf(i, l.points.first.avg)),
          2.5,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    }

    canvas.restore();

    // El punto tocado: línea vertical y un círculo por serie.
    final idx = touched;
    if (idx != null && idx < lines.first.points.length) {
      final at = lines.first.points[idx].t;
      final x = xOf(at);
      canvas.drawLine(
        Offset(x, padTop),
        Offset(x, padTop + plotH),
        Paint()
          ..color = CceColors.textTertiary.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      for (var i = 0; i < lines.length; i++) {
        final p = _Tooltip._closest(lines[i].points, at);
        if (p == null) continue;
        canvas.drawCircle(
          Offset(xOf(p.t), yOf(i, p.avg)),
          3,
          Paint()..color = lines[i].color,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String texto,
    Offset at, {
    TextAlign align = TextAlign.left,
    Color? color,
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color ?? CceColors.textTertiary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (maxWidth != null && tp.width > maxWidth) return;
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.lines != lines ||
      old.from != from ||
      old.to != to ||
      old.touched != touched;
}
