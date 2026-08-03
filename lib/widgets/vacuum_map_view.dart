import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/vacuum_map.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';

/// Mapa del robot (capability vacuum_map): well hundido con la imagen del
/// RRMap, trayectoria, robot y base. Tocar una habitación togglea su selección
/// (mismo set que los chips de LIMPIAR HABITACIONES — [selectedSegments] /
/// [onSegmentTap] los comparte la pantalla).
///
/// El grid llega ya en espacio pantalla (fila 0 arriba — el backend hizo el
/// único flip): acá sólo se rasteriza a un ui.Image (un byte→píxel RGBA, luego
/// drawImageRect con FilterQuality.none para look crisp tipo Valetudo) y se
/// dibuja el overlay vectorial encima.
///
/// Ciclo de vida del dato: un fetch al montar y auto-refresh SOLO mientras el
/// robot trabaja (el mapa cambia por segundo limpiando; dormido en la base es
/// estático). Si el fetch devuelve null (sin sidecar/nube caída) el widget
/// colapsa entero — label incluido — sin romper la pantalla.
class VacuumMapView extends StatefulWidget {
  final Device device;
  final DevicesService service;
  final Set<int> selectedSegments;
  final ValueChanged<int> onSegmentTap;

  /// Sin encabezado "MAPA" ni contenedor propio: dibuja sólo el plano y deja
  /// que quien lo hospeda ponga el marco. Se usa cuando el mapa ES la pantalla.
  final bool bare;

  const VacuumMapView({
    super.key,
    required this.device,
    required this.service,
    required this.selectedSegments,
    required this.onSegmentTap,
    this.bare = false,
  });

  @override
  State<VacuumMapView> createState() => _VacuumMapViewState();
}

class _VacuumMapViewState extends State<VacuumMapView> {
  VacuumMapData? _map;
  ui.Image? _image;
  bool _loading = true;
  Timer? _refreshTimer;
  /// Generación del raster: si llega un mapa nuevo mientras el anterior aún se
  /// rasteriza, el callback viejo no debe pisar al nuevo.
  int _rasterGen = 0;

  static const _refreshInterval = Duration(seconds: 10);

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  @override
  void initState() {
    super.initState();
    _fetch();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (_robotWorking || (_map == null && !_loading)) _fetch();
    });
  }

  @override
  void didUpdateWidget(covariant VacuumMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSelection(oldWidget.selectedSegments, widget.selectedSegments)) {
      _rasterize();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _rasterGen++; // invalida callbacks de raster en vuelo
    super.dispose();
  }

  bool get _robotWorking {
    final s = _device.state;
    return s.vacuumState == 'cleaning' ||
        s.vacuumState == 'returning' ||
        (s.vacuumActivity != null && s.vacuumActivity!.isNotEmpty);
  }

  bool _sameSelection(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _fetch() async {
    final data = await widget.service.fetchVacuumMap(widget.device);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data != null) _map = data;
    });
    if (data != null) _rasterize();
  }

  // ── Raster: grid RRMap → ui.Image RGBA ────────────────────────────────────

  /// Color de piso por segmento: hue estable derivado del id (paleta calma,
  /// misma receta de clamps que CceTint — nada de colores crudos).
  ///
  /// Tres estados, no dos. Cuando hay ALGUNA habitación elegida, las demás se
  /// atenúan ([dimmed]): con sólo subirle el brillo a la elegida, la
  /// diferencia era de unos pocos puntos de saturación sobre un plano lleno de
  /// colores, y había que buscarla. Apagando el resto, la selección salta sin
  /// que haya que compararla con nada.
  static Color segmentColor(
    int seg, {
    required bool selected,
    bool dimmed = false,
  }) {
    final hue = (seg * 47) % 360;
    final double sat, light;
    if (selected) {
      sat = 0.60;
      light = 0.58;
    } else if (dimmed) {
      sat = 0.14;
      light = 0.20;
    } else {
      sat = 0.32;
      light = 0.34;
    }
    return HSLColor.fromAHSL(1, hue.toDouble(), sat, light).toColor();
  }

  void _rasterize() {
    final map = _map;
    if (map == null) return;
    final gen = ++_rasterGen;

    const floorPlain = Color(0xFF2A2E3A); // piso sin segmento
    final rgba = Uint8List(map.width * map.height * 4);
    // Cache de colores por byte de píxel (32 segmentos × 2 estados a lo sumo).
    final colorCache = <int, int>{};

    // ¿Hay alguna habitación elegida? Entonces las NO elegidas se atenúan.
    final hasSelection = widget.selectedSegments.isNotEmpty;

    for (var i = 0; i < map.grid.length; i++) {
      final px = map.grid[i];
      final kind = px & 0x07;
      if (kind == 0) continue; // fuera del mapa: transparente (deja el well)
      final selectedBit =
          widget.selectedSegments.contains((px & 0xf8) >> 3) ? 0x100 : 0;
      final cacheKey = px | selectedBit;
      var packed = colorCache[cacheKey];
      if (packed == null) {
        final Color c;
        if (kind == 1) {
          c = CceColors.planWall;
        } else {
          final seg = (px & 0xf8) >> 3;
          c = seg == 0
              ? floorPlain
              : segmentColor(
                  seg,
                  selected: selectedBit != 0,
                  dimmed: hasSelection && selectedBit == 0,
                );
        }
        packed = (((c.r * 255).round() & 0xff)) |
            (((c.g * 255).round() & 0xff) << 8) |
            (((c.b * 255).round() & 0xff) << 16);
        colorCache[cacheKey] = packed;
      }
      final o = i * 4;
      rgba[o] = packed & 0xff;
      rgba[o + 1] = (packed >> 8) & 0xff;
      rgba[o + 2] = (packed >> 16) & 0xff;
      rgba[o + 3] = 0xff;
    }

    ui.decodeImageFromPixels(
      rgba,
      map.width,
      map.height,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted || gen != _rasterGen) {
          img.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = img;
        });
      },
    );
  }

  // ── Tap → segmento ────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails details, double scale) {
    final map = _map;
    if (map == null) return;
    final x = (details.localPosition.dx / scale).floor();
    final y = (details.localPosition.dy / scale).floor();
    // Tolerancia: si el dedo cayó en pared/borde, busca piso segmentado cerca
    // (radio 2 px de mapa ≈ 10 cm reales por píxel de 50 mm).
    for (var r = 0; r <= 2; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final seg = map.segmentAt(x + dx, y + dy);
          if (seg != null) {
            widget.onSegmentTap(seg);
            return;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    // Sin mapa y sin nada en camino: colapsar TODO (la pantalla no muestra la
    // sección). Mientras carga el primer fetch no se reserva lugar tampoco —
    // aparece de golpe cuando está, como las secciones del sidecar.
    if (map == null) return const SizedBox.shrink();

    final rooms = _device.state.rooms ?? const <VacuumRoom>[];
    final nameOf = {for (final r in rooms) r.segmentId: r.name};

    final mapWidget = LayoutBuilder(
      builder: (context, c) {
        // Escala CONTAIN: cuando la altura está acotada (el mapa es el
        // protagonista de la pantalla y vive en un Expanded), el plano se
        // ajusta al lado que primero se queda corto y queda entero a la vista.
        // Con altura infinita —dentro de un scroll— maxHeight es infinity y el
        // mínimo cae naturalmente en el ancho, que es el comportamiento previo.
        final byWidth = c.maxWidth / map.width;
        final byHeight = c.maxHeight.isFinite
            ? c.maxHeight / map.height
            : double.infinity;
        final scale = math.min(byWidth, byHeight);
        return Center(
          child: GestureDetector(
            onTapUp: (d) => _onTapUp(d, scale),
            child: CustomPaint(
              size: Size(map.width * scale, map.height * scale),
              painter: _VacuumMapPainter(
                image: _image,
                map: map,
                scale: scale,
                names: nameOf,
              ),
            ),
          ),
        );
      },
    );

    // `bare`: sin encabezado ni contenedor propio — el mapa es todo lo que se
    // dibuja y quien lo hospeda decide el marco.
    if (widget.bare) return mapWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text('MAPA', style: CceText.section),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: CceColors.surfaceSunken,
            borderRadius: BorderRadius.circular(CceRadii.card),
            border: Border.all(color: CceColors.stroke),
          ),
          clipBehavior: Clip.antiAlias,
          child: mapWidget,
        ),
      ],
    );
  }
}

class _VacuumMapPainter extends CustomPainter {
  final ui.Image? image;
  final VacuumMapData map;
  final double scale;
  final Map<int, String> names;

  _VacuumMapPainter({
    required this.image,
    required this.map,
    required this.scale,
    required this.names,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    // Trayectoria: hairline claro con alpha, por debajo de robot/base.
    if (map.path.length > 1) {
      final p = Path()..moveTo(map.path.first.x * scale, map.path.first.y * scale);
      for (final pt in map.path.skip(1)) {
        p.lineTo(pt.x * scale, pt.y * scale);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }

    final charger = map.charger;
    if (charger != null) {
      final c = Offset(charger.x * scale, charger.y * scale);
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = CceColors.ok.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(c, 3.5, Paint()..color = CceColors.ok);
    }

    final robot = map.robot;
    if (robot != null) {
      final c = Offset(robot.x * scale, robot.y * scale);
      canvas.drawCircle(
        c,
        9,
        Paint()
          ..color = CceColors.info.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(c, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = CceColors.info,
      );
      // Tick de orientación (angle ya viene en espacio pantalla).
      final angle = map.robotAngle;
      if (angle != null) {
        final rad = angle * math.pi / 180;
        canvas.drawLine(
          c,
          c + Offset(math.cos(rad), math.sin(rad)) * 9,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = CceColors.info,
        );
      }
    }

    // Nombre de cada habitación en su centroide (solo las nombradas).
    _paintLabels(canvas);
  }

  void _paintLabels(Canvas canvas) {
    if (names.isEmpty) return;
    // Centroides por segmento en una sola pasada del grid.
    final sums = <int, List<int>>{}; // seg → [sumX, sumY, count]
    for (var y = 0; y < map.height; y++) {
      final row = y * map.width;
      for (var x = 0; x < map.width; x++) {
        final px = map.grid[row + x];
        if ((px & 0x07) <= 1) continue;
        final seg = (px & 0xf8) >> 3;
        if (seg == 0 || !names.containsKey(seg)) continue;
        final s = sums.putIfAbsent(seg, () => [0, 0, 0]);
        s[0] += x;
        s[1] += y;
        s[2] += 1;
      }
    }
    for (final e in sums.entries) {
      final name = names[e.key]!;
      final count = e.value[2];
      if (count < 30) continue; // habitación demasiado chica para un label
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 90);
      final cx = e.value[0] / count * scale;
      final cy = e.value[1] / count * scale;
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_VacuumMapPainter old) =>
      old.image != image ||
      old.map != map ||
      old.scale != scale ||
      old.names != names;
}
