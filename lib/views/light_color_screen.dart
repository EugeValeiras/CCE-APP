import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
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
  // Posición del marcador (fracción 0..1 del disco) para CADA luz del ambiente.
  final Map<String, Offset> _markerFrac = {};
  // Grupo de cada luz (las del mismo id se ven como una sola pin y se mueven /
  // colorean juntas). Persisten: se pueden tener varios grupos a la vez.
  final Map<String, int> _groupOf = {};
  int _nextGroup = 0;
  // Grupo "en foco": se ve como pin aunque sea de 1 luz (los demás grupos de 1
  // luz son dots). Sólo hay UN foco a la vez → no hay multi-selección suelta.
  int _focus = -1;

  _Mode _mode = _Mode.color;
  double _bri = 254; // 0..254 (compartido en la UI)
  bool _dragging = false; // se está arrastrando una pin
  List<String> _dragMembers = const []; // miembros del grupo que se arrastra
  String? _mergeTarget; // luz destino bajo la pin arrastrada (preview de fusión)
  String? _soloOnMove; // luz marcada (tap en lista) para sacar al MOVERLA

  Timer? _debounce;
  double _diskSize = 1; // px del disco (para el offset cabeza↔punta del pin)
  static const double _ctMin = 153, _ctMax = 500;
  static const double _mergeThr = 0.12; // proximidad (frac) para fusionar
  static const double _grabPx = 34.0; // radio de agarre en px (cubre toda la pin)

  // Saltito del pin (estilo Google Maps) al entrar o al cambiar de luz: sube y
  // cae con un rebote sutil. El offset es en píxeles (negativo = arriba).
  late final AnimationController _hopController;
  late final Animation<double> _hopOffset;

  @override
  void initState() {
    super.initState();
    _bri = widget.device.state.bri.toDouble().clamp(0, 254);
    final r = resolveLightColor(widget.device.state);
    _mode = ((r.isWhite && widget.device.supportsCT) ||
                !widget.device.supportsColor) &&
            widget.device.supportsCT
        ? _Mode.white
        : _Mode.color;
    _initMarkers();
    // La luz abierta arranca en foco (pin); el resto del ambiente, como dots.
    _focus = _groupOf[widget.device.id] ?? -1;
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

  /// Posición en el disco de una luz según su estado real y el modo actual.
  Offset _fracForLight(Device d) {
    if (_mode == _Mode.color) {
      final r = resolveLightColor(d.state);
      return _fracForColor(r.isWhite ? CceColors.warm : r.color);
    }
    return _fracForCt((d.state.ct ?? 350).clamp(_ctMin, _ctMax).toDouble());
  }

  /// Posiciona TODAS las luces del ambiente y reconstruye los grupos POR COLOR:
  /// las luces que están al mismo color (misma posición) arrancan agrupadas. Así
  /// el agrupado "persiste" al salir y volver (el color es el que define el
  /// grupo) sin guardar estado aparte.
  static const double _sameColorEps = 0.025; // tolerancia "mismo color" en frac
  void _initMarkers() {
    final lights = _roomLights();
    for (final d in lights) {
      _markerFrac[d.id] = _fracForLight(widget.service.byId(d.id) ?? d);
    }
    final reps = <int, Offset>{}; // grupo → posición representante
    for (final d in lights) {
      if (_groupOf.containsKey(d.id)) continue;
      final pos = _markerFrac[d.id]!;
      int? join;
      reps.forEach((g, rp) {
        if (join == null && (rp - pos).distance <= _sameColorEps) join = g;
      });
      if (join != null) {
        _groupOf[d.id] = join!;
      } else {
        final g = _nextGroup++;
        _groupOf[d.id] = g;
        reps[g] = pos;
      }
    }
  }

  /// Recalcula posiciones desde el estado (al cambiar de modo). Cada grupo de
  /// >1 luz se reunifica en una sola posición para no dispersarse.
  void _recomputeMarkers() {
    for (final d in _roomLights()) {
      _markerFrac[d.id] = _fracForLight(widget.service.byId(d.id) ?? d);
    }
    final seen = <int>{};
    for (final id in _groupOf.keys.toList()) {
      final g = _groupOf[id]!;
      if (!seen.add(g)) continue;
      final members = _membersOf(g);
      if (members.length > 1) {
        final pos = _markerFrac[members.first]!;
        for (final m in members) {
          _markerFrac[m] = pos;
        }
      }
    }
  }

  /// Luces (del ambiente) que pertenecen al grupo [g].
  List<String> _membersOf(int g) => _roomLights()
      .map((d) => d.id)
      .where((id) => _groupOf[id] == g)
      .toList();

  /// ¿El grupo [g] (con [members]) se dibuja como pin? Sí si tiene >1 luz o si
  /// está en foco. Si no, es un dot.
  bool _isPin(int g, List<String> members) => members.length > 1 || g == _focus;

  /// Posición (frac) del centro de la CABEZA del pin cuya punta está en [tip].
  /// La cabeza está ~(tipY-headCy) px ARRIBA de la punta; es lo que el usuario
  /// ve y alinea contra los dots, así que la usamos para agarrar y fusionar.
  Offset _pinHead(Offset tip) => Offset(
      tip.dx, tip.dy - (_Marker.tipY - _Marker.headCy) / _diskSize);

  /// Saca [id] a su propio grupo y lo pone en foco (lo selecciona solo). Si
  /// estaba agrupada, el resto del grupo sigue junto.
  void _selectSolo(String id) {
    setState(() {
      _groupOf[id] = _nextGroup++;
      _focus = _groupOf[id]!;
    });
    _hop();
  }

  /// Luz más cercana a [f] que NO esté en [exclude], dentro de [within].
  String? _nearestMarker(Offset f, List<String> exclude, double within) {
    String? best;
    var bestD = within;
    for (final d in _roomLights()) {
      if (exclude.contains(d.id)) continue;
      final p = _markerFrac[d.id];
      if (p == null) continue;
      final dist = (p - f).distance;
      if (dist <= bestD) {
        bestD = dist;
        best = d.id;
      }
    }
    return best;
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

  // onPanDown se dispara en CADA toque (tap o inicio de arrastre), así que es el
  // único punto de entrada: decide qué se agarra. Si es un tap (sin mover), no
  // se llama a _drag, así que el color no cambia → tap = seleccionar.
  void _onPanDown(Offset f) {
    _mergeTarget = null;
    // Hit-test en PÍXELES. Una pin se agarra desde CUALQUIER parte visible: la
    // distancia es el mínimo a su cabeza (arriba) y a su punta (el punto de
    // color, abajo) — así no importa dónde de la gota toques. Los dots, por su
    // posición. Mismo umbral en px para que pin y dot compitan parejo y sin
    // depender del tamaño del disco (antes el umbral en frac se achicaba en px
    // en pantallas chicas y la punta quedaba fuera del agarre).
    int? pinGroup;
    List<String>? pinMembers;
    var dPin = double.infinity;
    String? dot;
    var dDot = double.infinity;
    final seen = <int>{};
    for (final d in _roomLights()) {
      final g = _groupOf[d.id];
      if (g == null || !seen.add(g)) continue;
      final members = _membersOf(g);
      final pos = _markerFrac[members.first];
      if (pos == null) continue;
      if (_isPin(g, members)) {
        final dHead = (_pinHead(pos) - f).distance;
        final dTip = (pos - f).distance;
        final dist = math.min(dHead, dTip) * _diskSize;
        if (dist < dPin) {
          dPin = dist;
          pinGroup = g;
          pinMembers = members;
        }
      } else {
        final dist = (pos - f).distance * _diskSize;
        if (dist < dDot) {
          dDot = dist;
          dot = members.first;
        }
      }
    }
    if (pinGroup != null && dPin <= _grabPx && dPin <= dDot) {
      // Agarrar una pin (mover ese grupo); pasa a foco. Si hay una luz marcada
      // para salir (tap en la lista) y no es de este grupo, se descarta.
      setState(() => _focus = pinGroup!);
      _dragMembers = pinMembers!;
      if (_soloOnMove != null && !pinMembers.contains(_soloOnMove)) {
        _soloOnMove = null;
      }
      _dragging = true;
    } else if (dot != null && dDot <= _grabPx) {
      // Tocar un dot → pasa a foco como pin sola, lista para arrastrar.
      _soloOnMove = null;
      HapticFeedback.selectionClick();
      _selectSolo(dot);
      _dragMembers = [dot];
      _dragging = true;
    } else {
      _soloOnMove = null;
      _dragging = false;
    }
  }

  void _drag(Offset localFrac) {
    if (!_dragging || _dragMembers.isEmpty) return;
    // Al primer MOVIMIENTO real: si hay una luz marcada (tap en la lista) dentro
    // del grupo que se arrastra, la sacamos para moverla SOLA (el resto del
    // grupo queda donde estaba). Desagrupar = mover, no seleccionar.
    if (_soloOnMove != null &&
        _dragMembers.contains(_soloOnMove) &&
        _dragMembers.length > 1) {
      final solo = _soloOnMove!;
      setState(() {
        _groupOf[solo] = _nextGroup++;
        _focus = _groupOf[solo]!;
        _dragMembers = [solo];
      });
    }
    _soloOnMove = null;
    final f = _clampFrac(localFrac);
    // Fusión por solapamiento de la CABEZA del pin (lo que el usuario ve) o de
    // la punta, sobre otra luz (pin o dot).
    final target = _nearestMarker(_pinHead(f), _dragMembers, _mergeThr) ??
        _nearestMarker(f, _dragMembers, _mergeThr);
    // Feedback háptico al entrar en rango de fusión sobre un destino nuevo.
    if (target != null && target != _mergeTarget) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      for (final id in _dragMembers) {
        _markerFrac[id] = f;
      }
      _mergeTarget = target;
    });
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 150), () => _applyToIds(_dragMembers));
  }

  void _onPanEnd() {
    _debounce?.cancel();
    if (_dragging && _mergeTarget != null) {
      // Fusionar: TODO el grupo destino pasa al grupo en foco y comparten la
      // posición soltada (así se pueden encadenar 3, 4, ... luces).
      final targetGroup = _groupOf[_mergeTarget!];
      setState(() {
        if (targetGroup != null && targetGroup != _focus) {
          for (final id in _groupOf.keys.toList()) {
            if (_groupOf[id] == targetGroup) _groupOf[id] = _focus;
          }
        }
        final pos = _markerFrac[_dragMembers.first]!;
        for (final id in _membersOf(_focus)) {
          _markerFrac[id] = pos;
        }
        _mergeTarget = null;
      });
      HapticFeedback.mediumImpact();
      _applyToIds(_membersOf(_focus));
      _hop();
    } else if (_dragging) {
      _applyToIds(_dragMembers);
      setState(() => _mergeTarget = null);
    }
    _dragging = false;
  }

  // ----- lista de luces / brillo -----
  /// Tap en una luz de la lista: la pone en foco SIN desagrupar (la luz sigue
  /// con su color/grupo). Si estaba agrupada, queda "marcada" para salir del
  /// grupo recién cuando la MUEVAS (no al seleccionarla).
  void _onLightTap(Device d) {
    HapticFeedback.selectionClick();
    setState(() {
      _focus = _groupOf[d.id] ?? -1;
      _soloOnMove = _membersOf(_focus).length > 1 ? d.id : null;
    });
    _hop();
  }

  void _onBrightness(double bri) => setState(() => _bri = bri.clamp(0, 254));

  void _commitBrightness() {
    for (final id in _membersOf(_focus)) {
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
    _applyToIds(_membersOf(_focus)); // aplicar el modo al grupo en foco
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
    final m = _membersOf(_focus);
    if (m.length == 1) {
      final d = widget.service.byId(m.first);
      return d != null ? widget.service.displayName(d) : 'Luz';
    }
    if (m.isEmpty) return widget.service.displayName(widget.device);
    return '${m.length} luces';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.18),
            radius: 1.05,
            colors: [CceColors.neoBase, Color(0xFF141620), CceColors.neoDark],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
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
      ),
    );
  }

  Widget _buildDisk(double size) {
    _diskSize = size; // para el offset cabeza↔punta en agarre/fusión
    final markers = <Widget>[];

    Color colorAt(Offset f) =>
        _mode == _Mode.color ? _colorForFrac(f) : _ctSwatchForFrac(f);

    // Agrupar luces del ambiente por grupo.
    final byGroup = <int, List<String>>{};
    for (final d in _roomLights()) {
      final g = _groupOf[d.id];
      if (g == null) continue;
      (byGroup[g] ??= []).add(d.id);
    }

    // Dots (grupos de 1 luz que NO están en foco; "circulitos" teñidos con su
    // color). El que está por fusionarse se resalta. Se dibujan primero.
    final pinGroups = <int, List<String>>{};
    byGroup.forEach((g, members) {
      if (_isPin(g, members)) {
        pinGroups[g] = members;
        return;
      }
      final id = members.first;
      final frac =
          _markerFrac[id] ?? _fracForLight(widget.service.byId(id) ?? widget.device);
      final isTarget = _mergeTarget == id;
      final r = isTarget ? 13.0 : 9.0;
      markers.add(Positioned(
        left: frac.dx * size - r,
        top: frac.dy * size - r,
        child: _Dot(color: colorAt(frac), highlighted: isTarget),
      ));
    });

    // Pins (grupos de >1 luz, o el grupo en foco). El que se arrastra muestra el
    // contador resultante ("2", "3", ...) y sólo ese hace el saltito.
    Offset? focusPos;
    pinGroups.forEach((g, members) {
      final pos = _markerFrac[members.first] ?? const Offset(0.5, 0.5);
      if (g == _focus) focusPos = pos;
      final isDragged = _dragging && g == _focus;
      // Seleccionada de la lista (marcada para sacar al mover): se muestra YA
      // como la luz elegida (su ícono), aunque internamente siga agrupada.
      final armedHere =
          g == _focus && _soloOnMove != null && members.contains(_soloOnMove);
      final repId = armedHere ? _soloOnMove! : members.first;
      final mergeAdd = (isDragged && _mergeTarget != null)
          ? _membersOf(_groupOf[_mergeTarget!] ?? -1).length
          : 0;
      final count = (armedHere ? 1 : members.length) + mergeAdd;
      final single = count == 1;
      final pinColor = colorAt(pos);
      final ink = _Marker.inkFor(pinColor); // auto-contraste (CceTint.textOn)
      Widget? child;
      if (single) {
        final d = widget.service.byId(repId) ?? widget.device;
        child = IconResolver.widget(
          d,
          configuredIcon: widget.service.iconFor(repId),
          customIcons: widget.service.customIcons,
          displayName: widget.service.displayName(d),
          size: 24,
          color: ink,
        );
      }
      final pin = _Marker(
        color: pinColor,
        ink: ink,
        label: single ? null : '$count',
        child: child,
      );
      markers.add(Positioned(
        // El aro inferior (la punta) queda exactamente en el punto de color.
        left: pos.dx * size - _Marker.w / 2,
        top: pos.dy * size - _Marker.tipY,
        // Saltito sólo en el pin en foco.
        child: g == _focus
            ? AnimatedBuilder(
                animation: _hopOffset,
                builder: (context, marker) => Transform.translate(
                  offset: Offset(0, _hopOffset.value),
                  child: marker,
                ),
                child: pin,
              )
            : pin,
      ));
    });

    // Mientras se arrastra, dejar el "circulito" teñido en el punto exacto: es
    // el ancla de selección y de drag-and-drop (la punta del pin lo señala).
    if (_dragging && focusPos != null) {
      markers.add(Positioned(
        left: focusPos!.dx * size - 13,
        top: focusPos!.dy * size - 13,
        child: _Dot(color: colorAt(focusPos!), highlighted: true),
      ));
    }

    return _ColorDisk(
      size: size,
      mode: _mode,
      glowColor: _mode == _Mode.color
          ? (focusPos != null ? _colorForFrac(focusPos!) : CceColors.warm)
          : CceColors.warm,
      onPanDown: (local) => _onPanDown(Offset(local.dx / size, local.dy / size)),
      onPanUpdate: (local) => _drag(Offset(local.dx / size, local.dy / size)),
      onPanEnd: _onPanEnd,
      markers: markers,
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // Chip circular de cerrar (neumórfico, ícono icons0).
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.surfaceHigh,
              border: Border.all(color: CceColors.stroke, width: 1),
              boxShadow: CceShadows.neo(blur: 10, offset: 4, intensity: 0.8),
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: const Center(
                  child: CceIcon(CceIcons.close,
                      size: 20, color: CceColors.textPrimary, emboss: false),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _title(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: CceText.title
                  .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          // Chip pill "Listo".
          Material(
            color: CceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.pill),
                  border: Border.all(color: CceColors.stroke, width: 1),
                  boxShadow:
                      CceShadows.neo(blur: 10, offset: 4, intensity: 0.8),
                ),
                child: const Text('Listo',
                    style: TextStyle(
                        color: CceColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlsRow() {
    final focus = _membersOf(_focus);
    final anyColor =
        focus.any((id) => widget.service.byId(id)?.supportsColor ?? false);
    final anyCt =
        focus.any((id) => widget.service.byId(id)?.supportsCT ?? false);
    final anyBri =
        focus.any((id) => widget.service.byId(id)?.supportsBrightness ?? false);
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
    if (lights.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 156,
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
            selected: _groupOf[d.id] == _focus,
            onTap: () => _onLightTap(d),
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
                    color: glowColor.withValues(alpha: 0.22),
                    blurRadius: 34,
                  ),
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.12),
                    blurRadius: 90,
                    spreadRadius: -6,
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
                    stops: [0.0, 0.82],
                  ),
                ),
              ),
            // Feather del borde del disco (ambos modos) → corte suave, no duro.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0x00000000),
                    const Color(0x00000000),
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  stops: const [0.0, 0.92, 1.0],
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

/// Dot de una luz NO activa: circulito teñido con su color, objetivo para
/// agrupar (se le arrastra una pin encima). [highlighted] cuando está por
/// fusionarse: crece y refuerza el aro.
class _Dot extends StatelessWidget {
  final Color color;
  final bool highlighted;
  const _Dot({required this.color, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final d = highlighted ? 26.0 : 18.0;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white.withValues(alpha: highlighted ? 0.95 : 0.78),
          width: highlighted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: highlighted ? 8 : 3,
            offset: const Offset(0, 1),
          ),
        ],
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
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
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
/// triángulo tangente hasta la punta) rellena SÓLIDA con el color seleccionado,
/// con sheen sutil, una hairline blanca fina y sombra baja. La PUNTA inferior
/// (con núcleo blanco) marca el lugar exacto.
class _PinPainter extends CustomPainter {
  final Color color; // relleno (color seleccionado, literal)
  final Color ink; // tinta del contenido (para repintar al cambiar color)
  const _PinPainter({required this.color, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const headR = _Marker.headR;
    const headCy = _Marker.headCy;
    const tipY = _Marker.tipY;
    final cx = w / 2;

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

    // --- 1) Sombra suave y baja (despega sin "stickerear") ----------------
    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.22), 3, true);

    // --- 2) Relleno SÓLIDO con el color seleccionado (opaco, no transparente)
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // --- 3) Sheen sutil en la cabeza --------------------------------------
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5],
      ).createShader(Rect.fromLTWH(
          cx - headR, headCy - headR, 2 * headR, 2 * headR));
    canvas.save();
    canvas.clipPath(head);
    canvas.drawRect(
        Rect.fromLTWH(cx - headR, headCy - headR, 2 * headR, 2 * headR), sheen);
    canvas.restore();

    // --- 4) Contorno: UNA hairline fina (elegante, no el doble contorno) ---
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    // --- 5) Núcleo en la punta → marca el punto EXACTO aunque el color del
    //     pin iguale el fondo (siempre hay blanco-sobre-color ahí).
    canvas.drawCircle(
      Offset(cx, tipY - 5),
      3.0,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      Offset(cx, tipY - 5),
      2.2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
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
        boxShadow: CceShadows.neo(blur: 10, offset: 4, intensity: 0.7),
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
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
            width: selected ? 2.5 : 1.5,
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
              color: CceColors.neoBase,
              shape: BoxShape.circle,
              boxShadow: CceShadows.neo(blur: 12, offset: 5, intensity: 0.9),
            ),
            child: const Center(
              child: CceIcon(CceIcons.sun,
                  size: 26, color: CceColors.textPrimary, emboss: false),
            ),
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
        width: 124,
        decoration: BoxDecoration(
          color: on ? null : CceColors.surface,
          gradient: on ? CceGradients.huePastel([tint]) : null,
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          // Selección con el propio tinte de la luz (dorado para cálido).
          border: Border.all(
            color: selected
                ? mid
                : (on
                    ? Colors.white.withValues(alpha: 0.12)
                    : CceColors.stroke),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? CceShadows.glowOn(mid)
              : (on ? CceShadows.cardFloat(intensity: 0.6) : null),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 13, 10, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: on
                            ? Colors.white.withValues(alpha: 0.16)
                            : CceColors.surfaceHigh,
                      ),
                      child: Center(child: iconBuilder(fg)),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (!reachable) ...[
                      const SizedBox(height: 3),
                      Text('Sin conexión'.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fgSub,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          )),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
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
    const w = 46.0, h = 28.0, thumb = 22.0;
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
              : Colors.white.withValues(alpha: 0.10),
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
              color: value ? Colors.white : const Color(0xFFCFCFD4),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
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
