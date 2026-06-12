import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';

/// Pantalla full-screen de configuración de color/temperatura de una luz,
/// estilo Hue: disco HSV (modo color) o gradiente cálido↔frío (modo blanco),
/// control de brillo a la derecha, y abajo la lista de luces que comparten la
/// habitación (seleccionables para editar cualquiera sin salir).
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
  late Device _selected;
  late _Mode _mode;
  late Color _color; // color actual (modo color)
  late double _ct; // mireds 153..500 (modo blanco)
  late double _bri; // 0..254

  Timer? _debounce;

  static const double _ctMin = 153, _ctMax = 500;

  @override
  void initState() {
    super.initState();
    _selected = widget.device;
    _loadFrom(_selected);
  }

  void _loadFrom(Device d) {
    final s = d.state;
    final r = resolveLightColor(s);
    _color = r.isWhite ? CceColors.warm : r.color;
    _ct = (s.ct ?? 350).clamp(_ctMin, _ctMax).toDouble();
    _bri = s.bri.toDouble().clamp(0, 254);
    // Modo inicial: blanco si la luz está en CT, o si no soporta color.
    final whiteMode = (r.isWhite && d.supportsCT) || !d.supportsColor;
    _mode = whiteMode && d.supportsCT ? _Mode.white : _Mode.color;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // Live device (refrescado por el service) del seleccionado.
  Device get _live => widget.service.byId(_selected.id) ?? _selected;

  /// Luces que comparten habitación con la luz original (o solo ella).
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

  void _selectDevice(Device d) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = d;
      _loadFrom(widget.service.byId(d.id) ?? d);
    });
  }

  void _onColorChanged(Color c) {
    setState(() => _color = c);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final hsv = HSVColor.fromColor(c);
      final hue = ((hsv.hue / 360) * 65535).round().clamp(0, 65535);
      final sat = (hsv.saturation * 254).round().clamp(0, 254);
      widget.service.setColor(_live, hue: hue, sat: sat);
    });
  }

  void _onCtChanged(double ct) {
    setState(() => _ct = ct.clamp(_ctMin, _ctMax));
  }

  void _commitCt() => widget.service.setCt(_live, _ct.round());

  void _onBrightness(double bri) {
    setState(() => _bri = bri.clamp(0, 254));
  }

  void _commitBrightness() =>
      widget.service.setBrightness(_live, _bri.round());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) {
            final d = _live;
            return Column(
              children: [
                _topBar(d),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final disk = math.min(c.maxWidth * 0.62, c.maxHeight * 0.62)
                          .clamp(220.0, 420.0)
                          .toDouble();
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          _ColorDisk(
                            size: disk,
                            mode: _mode,
                            color: _color,
                            ct: _ct,
                            ctMin: _ctMin,
                            ctMax: _ctMax,
                            iconData: IconResolver.resolve(
                              d,
                              configuredIcon: widget.service.iconFor(d.id),
                              displayName: widget.service.displayName(d),
                            ),
                            onColor: _onColorChanged,
                            onCt: _onCtChanged,
                            onCtEnd: _commitCt,
                          ),
                          const SizedBox(height: 28),
                          _controlsRow(d),
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

  Widget _topBar(Device d) {
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
              widget.service.displayName(d),
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

  Widget _controlsRow(Device d) {
    final showSegmented = d.supportsColor && d.supportsCT;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          if (showSegmented)
            _ModeToggle(
              mode: _mode,
              onChanged: (m) {
                HapticFeedback.selectionClick();
                setState(() => _mode = m);
                // Al cambiar a blanco, aplicar el CT actual; a color, el color.
                if (m == _Mode.white) {
                  _commitCt();
                } else {
                  final hsv = HSVColor.fromColor(_color);
                  widget.service.setColor(
                    _live,
                    hue: ((hsv.hue / 360) * 65535).round().clamp(0, 65535),
                    sat: (hsv.saturation * 254).round().clamp(0, 254),
                  );
                }
              },
            )
          else
            const SizedBox.shrink(),
          const Spacer(),
          if (d.supportsBrightness)
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
            icon: IconResolver.resolve(
              d,
              configuredIcon: widget.service.iconFor(d.id),
              displayName: widget.service.displayName(d),
            ),
            on: d.state.on,
            reachable: d.state.reachable,
            selected: d.id == _selected.id,
            onTap: () => _selectDevice(d),
            onToggle: (_) => widget.service.toggleLight(d),
          );
        },
      ),
    );
  }
}

/// Disco interactivo: HSV (color) o gradiente vertical cálido↔frío (blanco).
class _ColorDisk extends StatelessWidget {
  final double size;
  final _Mode mode;
  final Color color;
  final double ct, ctMin, ctMax;
  final IconData iconData;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onCt;
  final VoidCallback onCtEnd;

  const _ColorDisk({
    required this.size,
    required this.mode,
    required this.color,
    required this.ct,
    required this.ctMin,
    required this.ctMax,
    required this.iconData,
    required this.onColor,
    required this.onCt,
    required this.onCtEnd,
  });

  // Rainbow del SweepGradient (debe coincidir con el cálculo de hue del drag).
  static const List<Color> _wheel = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  void _handle(Offset local) {
    final c = size / 2;
    final dx = local.dx - c;
    final dy = local.dy - c;
    if (mode == _Mode.white) {
      // Vertical: arriba = cálido (ctMax), abajo = frío (ctMin).
      final frac = (local.dy / size).clamp(0.0, 1.0);
      onCt(ctMax - frac * (ctMax - ctMin));
      return;
    }
    final r = math.sqrt(dx * dx + dy * dy);
    final maxR = size / 2;
    final sat = (r / maxR).clamp(0.0, 1.0).toDouble();
    var hue = math.atan2(dy, dx) * 180.0 / math.pi;
    hue = (hue + 360.0) % 360.0;
    onColor(HSVColor.fromAHSV(1.0, hue, sat, 1.0).toColor());
  }

  Offset _markerPos() {
    final c = size / 2;
    if (mode == _Mode.white) {
      final frac = ((ctMax - ct) / (ctMax - ctMin)).clamp(0.0, 1.0);
      return Offset(c, frac * size);
    }
    final hsv = HSVColor.fromColor(color);
    final ang = hsv.hue * math.pi / 180.0;
    final r = hsv.saturation * (size / 2);
    return Offset(c + r * math.cos(ang), c + r * math.sin(ang));
  }

  @override
  Widget build(BuildContext context) {
    final marker = _markerPos();
    return GestureDetector(
      onPanDown: (d) => _handle(d.localPosition),
      onPanUpdate: (d) => _handle(d.localPosition),
      onPanEnd: (_) {
        if (mode == _Mode.white) onCtEnd();
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Disco
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: mode == _Mode.color
                    ? const SweepGradient(colors: _wheel)
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFD08A), // cálido
                          Color(0xFFFFF3E0),
                          Colors.white,
                          Color(0xFFD6ECFF), // frío
                        ],
                        stops: [0.0, 0.42, 0.6, 1.0],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: (mode == _Mode.color ? color : CceColors.warm)
                        .withValues(alpha: 0.35),
                    blurRadius: 60,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            // Saturación: blanco al centro → transparente al borde (solo color).
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
            // Marcador (pin con la luminaria).
            Positioned(
              left: marker.dx - 22,
              top: marker.dy - 30,
              child: _Marker(icon: iconData),
            ),
          ],
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  final IconData icon;
  const _Marker({required this.icon});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: CustomPaint(
        painter: _PinPainter(),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Icon(icon, color: const Color(0xFF1A1A1E), size: 22),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final r = size.width / 2;
    final path = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.width))
      ..moveTo(size.width / 2 - 6, size.width - 4)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 6, size.width - 4)
      ..close();
    canvas.drawPath(path.shift(const Offset(0, 2)), shadow);
    canvas.drawPath(path, paint);
    // Aro sutil.
    canvas.drawCircle(
      Offset(size.width / 2, r),
      r - 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Toggle color/blanco (pill con círculo arcoíris + círculo ámbar).
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
            gradient: const SweepGradient(colors: _ColorDisk._wheel),
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

/// Pill de brillo: drag vertical, muestra el % arriba.
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

/// Card mini de luz en la fila inferior (selección + toggle).
class _DeviceMiniCard extends StatelessWidget {
  final String name;
  final IconData icon;
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
                    Icon(icon, color: CceColors.textPrimary, size: 22),
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
