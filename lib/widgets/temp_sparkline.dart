import 'package:flutter/material.dart';

import '../models/server_config.dart';
import '../services/api_service.dart';
import '../theme/cce_tokens.dart';

/// Extrae el valor de temperatura de un payload de evento. Cambia según la
/// fuente: el termostato lo trae en `payload.state.currentTemp`; el termómetro
/// (sensor ambiente) en `payload.sensor.temperature`. Devuelve `null` si el
/// evento no aporta una lectura válida.
typedef TempReader = double? Function(Map<String, dynamic> payload);

/// Mini-gráfico del historial de temperatura (últimos 7 días): línea con
/// gradiente naranja sobre una cápsula hundida, con rótulo + rango mín–máx.
/// Trae las lecturas vía GET /api/events y promedia por buckets para mostrar
/// TENDENCIA y no el ruido de cada lectura. Se pide una vez (en initState); si
/// no hay datos suficientes no se muestra nada (→ [SizedBox.shrink]).
///
/// La extracción de la temperatura se delega en [reader] para poder reusar el
/// mismo gráfico tanto para el termostato (state.currentTemp) como para el
/// termómetro (sensor.temperature).
class TempSparkline extends StatefulWidget {
  const TempSparkline({
    super.key,
    required this.config,
    required this.globalId,
    required this.reader,
  });

  final ServerConfig config;
  final String globalId;
  final TempReader reader;

  @override
  State<TempSparkline> createState() => _TempSparklineState();
}

class _TempSparklineState extends State<TempSparkline> {
  List<({int t, double v})> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await ApiService(widget.config)
          .getEvents(globalId: widget.globalId, limit: 1000);
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      final pts = <({int t, double v})>[];
      for (final e in page.items) {
        final payload = e.payload;
        final v = payload == null ? null : widget.reader(payload);
        if (v != null) {
          final t = e.timestamp.millisecondsSinceEpoch;
          if (t >= cutoff) pts.add((t: t, v: v));
        }
      }
      pts.sort((a, b) => a.t.compareTo(b.t));
      final ds = _downsample(pts, 180);
      if (mounted) setState(() => _points = ds);
    } catch (_) {
      // Sin datos / error: el control no muestra el gráfico (build → shrink).
    }
  }

  /// Promedia los puntos en [maxBuckets] cubos temporales iguales (downsample).
  List<({int t, double v})> _downsample(
    List<({int t, double v})> pts,
    int maxBuckets,
  ) {
    if (pts.length <= maxBuckets) return pts;
    final t0 = pts.first.t;
    final span = pts.last.t - t0;
    final spanD = span <= 0 ? 1.0 : span.toDouble();
    final sum = List<double>.filled(maxBuckets, 0);
    final cnt = List<int>.filled(maxBuckets, 0);
    for (final p in pts) {
      var i = ((p.t - t0) / spanD * maxBuckets).floor();
      if (i >= maxBuckets) i = maxBuckets - 1;
      if (i < 0) i = 0;
      sum[i] += p.v;
      cnt[i] += 1;
    }
    final out = <({int t, double v})>[];
    for (var i = 0; i < maxBuckets; i++) {
      if (cnt[i] > 0) {
        final bt = t0 + (spanD * (i + 0.5) / maxBuckets).round();
        out.add((t: bt, v: sum[i] / cnt[i]));
      }
    }
    return out;
  }

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (_points.length < 2) return const SizedBox.shrink();
    double vmin = _points.first.v;
    double vmax = _points.first.v;
    for (final p in _points) {
      if (p.v < vmin) vmin = p.v;
      if (p.v > vmax) vmax = p.v;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: CceColors.neoSunken,
          borderRadius: BorderRadius.circular(16),
          boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ÚLTIMOS 7 DÍAS',
                  style: CceText.caption.copyWith(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: CceColors.neoTextSub,
                  ),
                ),
                Text(
                  '${_fmt(vmin)}° – ${_fmt(vmax)}°',
                  style: CceText.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: CceColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: CustomPaint(
                size: Size.infinite,
                painter: _SparkPainter(_points, vmin, vmax),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dibuja la polilínea del sparkline con el gradiente naranja del arco.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.vmin, this.vmax);

  final List<({int t, double v})> points;
  final double vmin;
  final double vmax;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const pad = 4.0;
    final t0 = points.first.t;
    final span = points.last.t - t0;
    final tspan = span <= 0 ? 1.0 : span.toDouble();
    final vrange = (vmax - vmin) == 0 ? 1.0 : (vmax - vmin);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = (p.t - t0) / tspan * size.width;
      final y =
          size.height - pad - ((p.v - vmin) / vrange) * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF7A00), Color(0xFFFFB36A)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points != points || old.vmin != vmin || old.vmax != vmax;
}
