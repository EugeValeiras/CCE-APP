import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';

/// Pantalla full-screen de color/temperatura estilo Hue, con MULTI-SELECCIÓN:
/// cada luz seleccionada tiene su propio marcador en el disco; al solaparlos
/// se fusionan en un único pin con contador y se mueven juntos. El disco es
/// HSV (modo color) o gradiente cálido↔frío (modo blanco). Abajo, la lista de
/// luces del room (tap = sumar/quitar de la selección, switch = on/off).
class LightColorScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  const LightColorScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<LightColorScreen> createState() => _LightColorScreenState();
}

enum _Mode { color, white }

class _LightColorScreenState extends State<LightColorScreen> {
  // Luces seleccionadas (editables). Siempre ≥ 1.
  final Set<String> _selected = {};
  // Posición del marcador (fracción 0..1 del disco) por luz seleccionada.
  final Map<String, Offset> _markerFrac = {};

  _Mode _mode = _Mode.color;
  double _bri = 254; // 0..254 (compartido en la UI)
  List<String> _dragIds = const []; // grupo que se está arrastrando

  Timer? _debounce;
  static const double _ctMin = 153, _ctMax = 500;

  @override
  void initState() {
    super.initState();
    _selected.add(widget.device.id);
    _bri = widget.device.state.bri.toDouble().clamp(0, 254);
    final r = resolveLightColor(widget.device.state);
    _mode = ((r.isWhite && widget.device.supportsCT) ||
                !widget.device.supportsColor) &&
            widget.device.supportsCT
        ? _Mode.white
        : _Mode.color;
    _recomputeMarkers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ----- conversiones frac <-> color/ct -----
  Offset _fracForColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    final ang = hsv.hue * math.pi / 180.0;
    final r = hsv.saturation * 0.5;
    return Offset(0.5 + r * math.cos(ang), 0.5 + r * math.sin(ang));
  }

  Color _colorForFrac(Offset f) {
    final dx = f.dx - 0.5, dy = f.dy - 0.5;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat = (dist / 0.5).clamp(0.0, 1.0).toDouble();
    final hue = (math.atan2(dy, dx) * 180.0 / math.pi + 360.0) % 360.0;
    return HSVColor.fromAHSV(1.0, hue, sat, 1.0).toColor();
  }

  Offset _fracForCt(double ct) =>
      Offset(0.5, ((_ctMax - ct) / (_ctMax - _ctMin)).clamp(0.0, 1.0));

  double _ctForFrac(Offset f) =>
      (_ctMax - f.dy * (_ctMax - _ctMin)).clamp(_ctMin, _ctMax);

  /// (Re)calcula el marcador de cada luz seleccionada desde su estado real,
  /// según el modo actual.
  void _recomputeMarkers() {
    for (final id in _selected) {
      final d = widget.service.byId(id);
      if (d == null) continue;
      if (_mode == _Mode.color) {
        final r = resolveLightColor(d.state);
        _markerFrac[id] = _fracForColor(r.isWhite ? CceColors.warm : r.color);
      } else {
        _markerFrac[id] =
            _fracForCt((d.state.ct ?? 350).clamp(_ctMin, _ctMax).toDouble());
      }
    }
    _markerFrac.removeWhere((k, v) => !_selected.contains(k));
  }

  /// Aplica el color/temperatura (según el marcador) a las luces [ids].
  void _applyToIds(Iterable<String> ids) {
    for (final id in ids) {
      final f = _markerFrac[id];
      final d = widget.service.byId(id);
      if (f == null || d == null) continue;
      if (_mode == _Mode.color) {
        final hsv = HSVColor.fromColor(_colorForFrac(f));
        widget.service.setColor(
          d,
          hue: ((hsv.hue / 360) * 65535).round().clamp(0, 65535),
          sat: (hsv.saturation * 254).round().clamp(0, 254),
        );
      } else {
        widget.service.setCt(d, _ctForFrac(f).round());
      }
    }
  }

  // ----- interacción del disco -----
  Offset _clampFrac(Offset f) {
    final dx = f.dx - 0.5, dy = f.dy - 0.5;
    final r = math.sqrt(dx * dx + dy * dy);
    if (r <= 0.5 || r == 0) return f;
    final k = 0.5 / r;
    return Offset(0.5 + dx * k, 0.5 + dy * k);
  }

  void _onPanDown(Offset localFrac) {
    // Engancha el grupo (cluster) cuyo pin esté más cerca del toque.
    final clusters = _clusters();
    if (clusters.isEmpty) {
      _dragIds = _selected.toList();
    } else {
      var best = clusters.first;
      var bestD = double.infinity;
      for (final c in clusters) {
        final d = (c.pos - localFrac).distance;
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      _dragIds = best.ids;
    }
    _drag(localFrac);
  }

  void _drag(Offset localFrac) {
    final f = _clampFrac(localFrac);
    setState(() {
      for (final id in _dragIds) {
        _markerFrac[id] = f;
      }
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150),
        () => _applyToIds(_dragIds));
  }

  void _onPanEnd() {
    _debounce?.cancel();
    _applyToIds(_dragIds);
  }

  /// Agrupa las luces seleccionadas cuyos marcadores están muy cerca.
  List<({Offset pos, List<String> ids})> _clusters() {
    const thr = 0.07; // en fracción del disco
    final out = <({Offset pos, List<String> ids})>[];
    for (final id in _selected) {
      final f = _markerFrac[id];
      if (f == null) continue;
      var placed = false;
      for (var i = 0; i < out.length; i++) {
        if ((out[i].pos - f).distance <= thr) {
          final ids = [...out[i].ids, id];
          // centroide
          var cx = 0.0, cy = 0.0;
          for (final j in ids) {
            cx += _markerFrac[j]!.dx;
            cy += _markerFrac[j]!.dy;
          }
          out[i] = (pos: Offset(cx / ids.length, cy / ids.length), ids: ids);
          placed = true;
          break;
        }
      }
      if (!placed) out.add((pos: f, ids: [id]));
    }
    return out;
  }

  // ----- selección / brillo -----
  void _toggleSelect(Device d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(d.id)) {
        if (_selected.length > 1) {
          _selected.remove(d.id);
          _markerFrac.remove(d.id);
        }
      } else {
        _selected.add(d.id);
        final live = widget.service.byId(d.id) ?? d;
        if (_mode == _Mode.color) {
          final r = resolveLightColor(live.state);
          _markerFrac[d.id] =
              _fracForColor(r.isWhite ? CceColors.warm : r.color);
        } else {
          _markerFrac[d.id] = _fracForCt(
              (live.state.ct ?? 350).clamp(_ctMin, _ctMax).toDouble());
        }
      }
    });
  }

  void _onBrightness(double bri) => setState(() => _bri = bri.clamp(0, 254));

  void _commitBrightness() {
    for (final id in _selected) {
      final d = widget.service.byId(id);
      if (d != null) widget.service.setBrightness(d, _bri.round());
    }
  }

  void _setMode(_Mode m) {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = m;
      _recomputeMarkers();
    });
    _applyToIds(_selected); // aplicar el modo elegido a todas las seleccionadas
  }

  List<Device> _roomLights() {
    final svc = widget.service;
    for (final room in svc.rooms) {
      if (room.deviceIds.contains(widget.device.id)) {
        final lights = room.deviceIds
            .map(svc.byId)
            .whereType<Device>()
            .where((d) => d.isLight && !d.isSensorDevice)
            .toList();
        if (lights.isNotEmpty) return lights;
      }
    }
    return [widget.device];
  }

  String _title() {
    if (_selected.length == 1) {
      final d = widget.service.byId(_selected.first);
      return d != null ? widget.service.displayName(d) : 'Luz';
    }
    return '${_selected.length} luces';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) {
            return Column(
              children: [
                _topBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = math
                          .min(c.maxWidth * 0.70, c.maxHeight * 0.66)
                          .clamp(240.0, 480.0)
                          .toDouble();
                      return Column(
                        children: [
                          const Spacer(),
                          _buildDisk(size),
                          const SizedBox(height: 28),
                          _controlsRow(),
                          const Spacer(),
                        ],
                      );
                    },
                  ),
                ),
                _deviceStrip(),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDisk(double size) {
    // Marcadores: dots tenues para luces NO seleccionadas + pins (con
    // contador si hay fusión) para las seleccionadas.
    final markers = <Widget>[];

    // Dots de luces del room no seleccionadas (referencia, no interactivos).
    for (final d in _roomLights()) {
      if (_selected.contains(d.id)) continue;
      final live = widget.service.byId(d.id) ?? d;
      final frac = _mode == _Mode.color
          ? _fracForColor(() {
              final r = resolveLightColor(live.state);
              return r.isWhite ? CceColors.warm : r.color;
            }())
          : _fracForCt((live.state.ct ?? 350).clamp(_ctMin, _ctMax).toDouble());
      markers.add(Positioned(
        left: frac.dx * size - 6,
        top: frac.dy * size - 6,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.55),
            border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
          ),
        ),
      ));
    }

    // Pins de las seleccionadas (clusterizadas). Cluster de 1 → ícono real del
    // device; cluster > 1 → contador.
    final clusters = _clusters();
    for (final cl in clusters) {
      final single = cl.ids.length == 1;
      Widget? child;
      if (single) {
        final d = widget.service.byId(cl.ids.first) ?? widget.device;
        child = IconResolver.widget(
          d,
          configuredIcon: widget.service.iconFor(cl.ids.first),
          customIcons: widget.service.customIcons,
          displayName: widget.service.displayName(d),
          size: 22,
          color: const Color(0xFF1A1A1E),
        );
      }
      markers.add(Positioned(
        // Centro del círculo del pin en el punto de color (cola hacia abajo).
        left: cl.pos.dx * size - _Marker.w / 2,
        top: cl.pos.dy * size - _Marker.w / 2,
        child: _Marker(child: child, label: single ? null : '${cl.ids.length}'),
      ));
    }

    return _ColorDisk(
      size: size,
      mode: _mode,
      glowColor: _mode == _Mode.color
          ? (_selected.isNotEmpty && _markerFrac[_selected.first] != null
              ? _colorForFrac(_markerFrac[_selected.first]!)
              : CceColors.warm)
          : CceColors.warm,
      onPanDown: (local) => _onPanDown(Offset(local.dx / size, local.dy / size)),
      onPanUpdate: (local) => _drag(Offset(local.dx / size, local.dy / size)),
      onPanEnd: _onPanEnd,
      markers: markers,
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: CceColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _title(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.title,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo',
                style: TextStyle(
                    color: CceColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _controlsRow() {
    final anyColor =
        _selected.any((id) => widget.service.byId(id)?.supportsColor ?? false);
    final anyCt =
        _selected.any((id) => widget.service.byId(id)?.supportsCT ?? false);
    final anyBri = _selected
        .any((id) => widget.service.byId(id)?.supportsBrightness ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          if (anyColor && anyCt)
            _ModeToggle(mode: _mode, onChanged: _setMode)
          else
            const SizedBox.shrink(),
          const Spacer(),
          if (anyBri)
            _BrightnessPill(
              value: _bri,
              onChanged: _onBrightness,
              onEnd: _commitBrightness,
            ),
        ],
      ),
    );
  }

  Widget _deviceStrip() {
    final lights = _roomLights();
    if (lights.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: lights.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final d = widget.service.byId(lights[i].id) ?? lights[i];
          return _DeviceMiniCard(
            name: widget.service.displayName(d),
            icon: IconResolver.widget(
              d,
              configuredIcon: widget.service.iconFor(d.id),
              customIcons: widget.service.customIcons,
              displayName: widget.service.displayName(d),
              size: 22,
              color: CceColors.textPrimary,
            ),
            on: d.state.on,
            reachable: d.state.reachable,
            selected: _selected.contains(d.id),
            onTap: () => _toggleSelect(d),
            onToggle: (_) => widget.service.toggleLight(d),
          );
        },
      ),
    );
  }
}

/// Disco que pinta el gradiente (HSV o cálido↔frío) y superpone [markers] ya
/// posicionados; reporta los gestos en coordenadas locales (píxeles).
class _ColorDisk extends StatelessWidget {
  final double size;
  final _Mode mode;
  final Color glowColor;
  final List<Widget> markers;
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  const _ColorDisk({
    required this.size,
    required this.mode,
    required this.glowColor,
    required this.markers,
    required this.onPanDown,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  static const List<Color> wheel = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => onPanDown(d.localPosition),
      onPanUpdate: (d) => onPanUpdate(d.localPosition),
      onPanEnd: (_) => onPanEnd(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: mode == _Mode.color
                    ? const SweepGradient(colors: wheel)
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFD08A),
                          Color(0xFFFFF3E0),
                          Colors.white,
                          Color(0xFFD6ECFF),
                        ],
                        stops: [0.0, 0.42, 0.6, 1.0],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 60,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            if (mode == _Mode.color)
              Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white, Color(0x00FFFFFF)],
                    stops: [0.0, 0.9],
                  ),
                ),
              ),
            ...markers,
          ],
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  final Widget? child; // ícono del device (cluster de 1)
  final String? label; // contador (cluster > 1)
  const _Marker({this.child, this.label});

  static const double w = 46; // diámetro del círculo
  static const double h = 60; // alto total con la cola

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(w, h),
      painter: _PinPainter(),
      child: Padding(
        // Reserva la cola abajo → el contenido queda centrado en el círculo.
        padding: const EdgeInsets.only(bottom: h - w),
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : child,
        ),
      ),
    );
  }
}

/// Pin estilo Hue: gota (círculo + cola curva) blanca con sombra suave.
class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w / 2;
    final cx = w / 2, cy = r;
    final tipY = size.height;

    final circle = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    // Unión de la cola con el círculo (~±42° desde abajo) hacia la punta.
    final th = 42 * math.pi / 180;
    final lx = cx - r * math.sin(th), ly = cy + r * math.cos(th);
    final rx = cx + r * math.sin(th), ry = ly;
    final tail = Path()
      ..moveTo(lx, ly)
      ..quadraticBezierTo(cx - r * 0.10, (ly + tipY) / 2, cx, tipY)
      ..quadraticBezierTo(cx + r * 0.10, (ry + tipY) / 2, rx, ry)
      ..close();
    final pin = Path.combine(PathOperation.union, circle, tail);

    canvas.drawShadow(pin, Colors.black.withValues(alpha: 0.45), 4, false);
    canvas.drawPath(pin, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      r - 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _opt(
            selected: mode == _Mode.color,
            onTap: () => onChanged(_Mode.color),
            gradient: const SweepGradient(colors: _ColorDisk.wheel),
          ),
          const SizedBox(width: 6),
          _opt(
            selected: mode == _Mode.white,
            onTap: () => onChanged(_Mode.white),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD08A), Color(0xFFFFB46B)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _opt({
    required bool selected,
    required VoidCallback onTap,
    required Gradient gradient,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
        ),
      ),
    );
  }
}

class _BrightnessPill extends StatelessWidget {
  final double value; // 0..254
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  const _BrightnessPill({
    required this.value,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value / 254 * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$pct%',
            style: const TextStyle(
                color: CceColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        GestureDetector(
          onVerticalDragUpdate: (d) {
            onChanged((value - d.delta.dy * (254 / 160)).clamp(0, 254));
          },
          onVerticalDragEnd: (_) => onEnd(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CceColors.surfaceHigh,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.wb_sunny_rounded,
                color: CceColors.textPrimary, size: 26),
          ),
        ),
      ],
    );
  }
}

class _DeviceMiniCard extends StatelessWidget {
  final String name;
  final Widget icon;
  final bool on, reachable, selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const _DeviceMiniCard({
    required this.name,
    required this.icon,
    required this.on,
    required this.reachable,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 116,
        decoration: BoxDecoration(
          color: CceColors.surface,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: Border.all(
            color: selected ? Colors.white : CceColors.stroke,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 22, child: Center(child: icon)),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CceColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.12,
                      ),
                    ),
                    if (!reachable) ...[
                      const SizedBox(height: 2),
                      const Text('Sin conexión',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: CceColors.textTertiary, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: Center(
                child: Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: on,
                    onChanged: onToggle,
                    thumbColor:
                        const WidgetStatePropertyAll<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
