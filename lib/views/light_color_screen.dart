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

class _LightColorScreenState extends State<LightColorScreen>
    with SingleTickerProviderStateMixin {
  // Luces seleccionadas (editables). Siempre ≥ 1.
  final Set<String> _selected = {};
  // Posición del marcador (fracción 0..1 del disco) por luz seleccionada.
  final Map<String, Offset> _markerFrac = {};

  _Mode _mode = _Mode.color;
  double _bri = 254; // 0..254 (compartido en la UI)
  List<String> _dragIds = const []; // grupo que se está arrastrando

  Timer? _debounce;
  static const double _ctMin = 153, _ctMax = 500;

  // Saltito del pin (estilo Google Maps) al entrar o al cambiar de luz: sube y
  // cae con un rebote sutil. El offset es en píxeles (negativo = arriba).
  late final AnimationController _hopController;
  late final Animation<double> _hopOffset;

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
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _hopOffset = TweenSequence<double>([
      // Despegue: 0 → arriba (easeOut, rápido).
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -14.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 32,
      ),
      // Caída + rebote sutil al aterrizar sobre el punto.
      TweenSequenceItem(
        tween: Tween(begin: -14.0, end: 0.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 68,
      ),
    ]).animate(_hopController);
    // Salto de entrada (tras el primer frame, ya con layout listo).
    WidgetsBinding.instance.addPostFrameCallback((_) => _hop());
  }

  /// Dispara el saltito del/los pin(es) seleccionados.
  void _hop() {
    if (!mounted) return;
    _hopController.forward(from: 0);
  }

  @override
  void dispose() {
    _hopController.dispose();
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

  /// Color que muestra el pin en modo blanco/CT, derivado de la posición
  /// vertical (mismos stops que el gradiente del disco en _ColorDisk).
  Color _ctSwatchForFrac(Offset f) {
    final t = f.dy.clamp(0.0, 1.0).toDouble();
    const warm = Color(0xFFFFD08A);
    const midW = Color(0xFFFFF3E0);
    const white = Colors.white;
    const cool = Color(0xFFD6ECFF);
    if (t < 0.42) return Color.lerp(warm, midW, t / 0.42)!;
    if (t < 0.60) return Color.lerp(midW, white, (t - 0.42) / 0.18)!;
    return Color.lerp(white, cool, (t - 0.60) / 0.40)!;
  }

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
    final added = !_selected.contains(d.id);
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
    // Saltito al sumar una luz (cambiar de luz), no al quitarla.
    if (added) _hop();
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
        left: frac.dx * size - 7,
        top: frac.dy * size - 7,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.10),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
          ),
        ),
      ));
    }

    // Pins de las seleccionadas (clusterizadas). Cluster de 1 → ícono real del
    // device; cluster > 1 → contador.
    final clusters = _clusters();
    for (final cl in clusters) {
      final single = cl.ids.length == 1;
      // Color vivo bajo la punta de este cluster (rellena el pin).
      final pinColor = _mode == _Mode.color
          ? _colorForFrac(cl.pos)
          : _ctSwatchForFrac(cl.pos);
      final ink = _Marker.inkFor(pinColor); // auto-contraste (CceTint.textOn)
      Widget? child;
      if (single) {
        final d = widget.service.byId(cl.ids.first) ?? widget.device;
        child = IconResolver.widget(
          d,
          configuredIcon: widget.service.iconFor(cl.ids.first),
          customIcons: widget.service.customIcons,
          displayName: widget.service.displayName(d),
          size: 24,
          color: ink, // tinta auto-contraste en vez del 0xFF1A1A1E fijo
        );
      }
      markers.add(Positioned(
        // El aro inferior (la punta) queda exactamente en el punto de color.
        left: cl.pos.dx * size - _Marker.w / 2,
        top: cl.pos.dy * size - _Marker.tipY,
        // Saltito vertical (estilo Google Maps) al entrar / cambiar de luz: el
        // pin despega del punto y aterriza con un rebote sutil.
        child: AnimatedBuilder(
          animation: _hopOffset,
          builder: (context, marker) => Transform.translate(
            offset: Offset(0, _hopOffset.value),
            child: marker,
          ),
          child: _Marker(
            child: child,
            label: single ? null : '${cl.ids.length}',
            color: pinColor,
            ink: ink,
          ),
        ),
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
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: lights.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final d = widget.service.byId(lights[i].id) ?? lights[i];
          final r = resolveLightColor(d.state);
          final tint = r.isWhite ? CceColors.warm : r.color;
          return _DeviceMiniCard(
            name: widget.service.displayName(d),
            iconBuilder: (c) => IconResolver.widget(
              d,
              configuredIcon: widget.service.iconFor(d.id),
              customIcons: widget.service.customIcons,
              displayName: widget.service.displayName(d),
              size: 22,
              color: c,
            ),
            tint: tint,
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

/// Pin color-aware estilo Google Maps: cabeza circular ANCHA arriba (con el
/// ícono/contador) que se afina por dos lados tangentes hasta una PUNTA inferior
/// que marca el lugar exacto. Va RELLENO con el color seleccionado (el color
/// viaja con el marcador), con gloss superior y un DOBLE contorno (keyline
/// oscuro + aro blanco) que lo separa de cualquier fondo del disco. El contenido
/// usa tinta auto-contraste [ink].
class _Marker extends StatelessWidget {
  final Widget? child; // ícono del device (cluster de 1), ya teñido con [ink]
  final String? label; // contador (cluster > 1)
  final Color color; // color seleccionado bajo la punta (rellena el cuerpo)
  final Color ink; // tinta auto-contraste para ícono/contador (CceTint.textOn)
  const _Marker({
    this.child,
    this.label,
    required this.color,
    required this.ink,
  });

  static const double w = 56; // ancho total (= diámetro de la cabeza + aire)
  static const double headR = 23; // radio de la cabeza circular (ancha arriba)
  static const double headCy = 27; // centro vertical de la cabeza (zona ícono)
  static const double tipY = 70; // punta inferior = punto de color exacto
  static const double h = 76; // alto total (cabeza + punta + aire para sombra)

  /// Tinta auto-contraste para el contenido sobre [c]. Reusa el token del DS
  /// para no divergir del resto de la app.
  static Color inkFor(Color c) => CceTint.textOn(c);

  @override
  Widget build(BuildContext context) {
    final content = label != null
        ? Text(
            label!,
            style: TextStyle(
              color: ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          )
        : child;
    // SizedBox tight → el CustomPaint pinta en EXACTAMENTE w×h (si no, al tener
    // child el CustomPaint se mide por el child y headCy del painter no coincide
    // con el centro real → ícono descentrado). El contenido se posiciona con su
    // centro clavado en el de la cabeza: (w/2, headCy).
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _PinPainter(color: color, ink: ink)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 2 * headCy, // caja [0, 2*headCy] → centro vertical = headCy
            // El pin es un fill de color saturado: se aplana el relieve del
            // glyph (sombra oscura ensuciaria la cabeza). `shadows: []` apaga
            // el emboss del Icon de Material y del CceIcon por igual. (Text no
            // se ve afectado.)
            child: IconTheme.merge(
              data: const IconThemeData(shadows: <Shadow>[]),
              child: Center(child: content),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pin color-aware estilo Google Maps: una sola pieza (cabeza circular ∪
/// triángulo tangente hasta la punta) rellena con el color seleccionado, con
/// gloss superior y DOBLE contorno (keyline oscuro + aro blanco) que lo separa
/// de cualquier fondo del disco. La PUNTA inferior marca el lugar exacto.
class _PinPainter extends CustomPainter {
  final Color color; // relleno (color seleccionado, literal)
  final Color ink; // tinta del contenido (para repintar al cambiar color)
  const _PinPainter({required this.color, required this.ink});

  /// Color para el glow que no se rompe en el centro desaturado: si la
  /// saturación es casi nula (hue inestable cerca del blanco) cae a un neutro
  /// fijo para evitar el shimmer arcoíris al arrastrar por el centro.
  Color get _signal {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.12) {
      return const Color(0xFF8A8A92);
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.45, 1.0).toDouble())
        .withLightness(hsl.lightness.clamp(0.42, 0.60).toDouble())
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const headR = _Marker.headR;
    const headCy = _Marker.headCy;
    const tipY = _Marker.tipY;
    final cx = w / 2;
    final signal = _signal;

    // --- Silueta tipo gota: cabeza circular ∪ triángulo tangente a la punta -
    // Los lados del triángulo son TANGENTES a la cabeza → la unión es suave
    // (sin muescas). beta = semiángulo desde el centro hacia los puntos de
    // tangencia, vistos desde la punta a distancia d.
    final headC = Offset(cx, headCy);
    final d = tipY - headCy;
    final beta = math.acos(headR / d);
    final sinB = math.sin(beta), cosB = math.cos(beta);
    final pa = Offset(cx - headR * sinB, headCy + headR * cosB); // tangente izq
    final pb = Offset(cx + headR * sinB, headCy + headR * cosB); // tangente der

    final head = Path()
      ..addOval(Rect.fromCircle(center: headC, radius: headR));
    final tail = Path()
      ..moveTo(pa.dx, pa.dy)
      ..lineTo(cx, tipY)
      ..lineTo(pb.dx, pb.dy)
      ..close();
    final body = Path.combine(PathOperation.union, head, tail);

    // --- 1) Glow de color suave bajo la punta (premium, color-aware) -------
    canvas.drawCircle(
      Offset(cx, tipY - 2),
      6,
      Paint()
        ..color = signal.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // --- 2) Sombra de elevación (despega del centro blanco del disco) ------
    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.45), 5, false);

    // --- 3) Relleno con el color seleccionado -----------------------------
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // --- 4) Gloss superior en la cabeza (look gema/premium) ---------------
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.6],
      ).createShader(Rect.fromLTWH(
          cx - headR, headCy - headR, 2 * headR, 2 * headR));
    canvas.save();
    canvas.clipPath(head);
    canvas.drawRect(
        Rect.fromLTWH(cx - headR, headCy - headR, 2 * headR, 2 * headR), sheen);
    canvas.restore();

    // --- 5) DOBLE CONTORNO adaptativo (clave de legibilidad universal) -----
    // 5a) Keyline oscuro EXTERIOR → carga la silueta sobre el centro blanco del
    //     disco y sobre colores claros (amarillo/cian).
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    // 5b) Aro blanco crujiente ENCIMA → separa de bordes saturados y del
    //     gradiente CT (rojo-sobre-rojo, azul-sobre-azul, cálido-sobre-cálido).
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    // --- 6) Núcleo blanco en la punta → marca el punto EXACTO incluso si el
    //     color del pin iguala el fondo (siempre hay blanco-sobre-color ahí).
    canvas.drawCircle(
      Offset(cx, tipY - 5),
      2.6,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _PinPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.ink != ink;
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
  final Widget Function(Color color) iconBuilder;
  final Color tint; // color real de la luz (para teñir la card como Hue)
  final bool on, reachable, selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const _DeviceMiniCard({
    required this.name,
    required this.iconBuilder,
    required this.tint,
    required this.on,
    required this.reachable,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Card teñida con el pastel del color de la luz cuando está encendida.
    final mid = CceTint.pastel(tint);
    final fg = on ? CceTint.textOn(mid) : CceColors.textPrimary;
    final fgSub = on ? CceTint.subTextOn(mid) : CceColors.textTertiary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 122,
        decoration: BoxDecoration(
          color: on ? null : CceColors.surface,
          gradient: on ? CceGradients.huePastel([tint]) : null,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: Border.all(
            color: selected
                ? Colors.white
                : (on
                    ? Colors.white.withValues(alpha: 0.15)
                    : CceColors.stroke),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 26, child: Center(child: iconBuilder(fg))),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.12,
                      ),
                    ),
                    if (!reachable) ...[
                      const SizedBox(height: 2),
                      Text('Sin conexión',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fgSub, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HueSwitch(
                value: on,
                onChanged: onToggle,
                onColor:
                    on ? CceTint.inkOnPastel.withValues(alpha: 0.28) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switch estilo Hue: pista pill + thumb circular blanco (reemplaza el Switch
/// verde de iOS). [onColor] tiñe la pista cuando está encendido.
class _HueSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? onColor;
  const _HueSwitch({required this.value, required this.onChanged, this.onColor});

  @override
  Widget build(BuildContext context) {
    const w = 54.0, h = 32.0, thumb = 26.0;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: w,
        height: h,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? (onColor ?? Colors.white.withValues(alpha: 0.45))
              : Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumb,
            height: thumb,
            decoration: BoxDecoration(
              color: value ? Colors.white : const Color(0xFFE6E6E6),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
