import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_segmented.dart';
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

  // Realce del pin al entrar o al cambiar de luz: sube y vuelve, con
  // deceleración. En píxeles (negativo = arriba). Ver initState.
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
    // Brillo inicial = el de la(s) luz(es) en foco (no sólo el del device abierto).
    final ids = _membersOf(_focus);
    if (ids.isNotEmpty) {
      var sum = 0, n = 0;
      for (final id in ids) {
        final d = widget.service.byId(id);
        if (d == null) continue;
        sum += d.state.bri;
        n++;
      }
      if (n > 0) _bri = (sum / n).clamp(0, 254).toDouble();
    }
    // Acuse de recibo al tomar una luz. Antes era un "saltito" de 620ms con
    // Curves.bounceOut — un rebote de mapa, prestado de otro dominio, y lo que
    // más hacía que el selector se leyera como un juguete. Ahora es un realce
    // corto con deceleración: confirma la selección y se va.
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _hopOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -6.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -6.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
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

  /// Posición (frac) del centro visual del marcador.
  ///
  /// Con el pin de mapa esto restaba el offset punta→cabeza: lo que veías
  /// estaba 43 px más arriba de lo que el gesto tomaba como punto. Con el
  /// marcador circular el centro ES el punto, así que la corrección desaparece
  /// — y con ella la sensación de que el marcador "no agarra donde tocás".
  Offset _pinHead(Offset tip) => tip;

  /// Saca [id] a su propio grupo y lo pone en foco (lo selecciona solo). Si
  /// estaba agrupada, el resto del grupo sigue junto.
  void _selectSolo(String id) {
    setState(() {
      _groupOf[id] = _nextGroup++;
      _focus = _groupOf[id]!;
    });
    _syncBriFromFocus();
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
      _syncBriFromFocus();
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
    _syncBriFromFocus();
    _hop();
  }

  void _onBrightness(double bri) => setState(() => _bri = bri.clamp(0, 254));

  void _commitBrightness() {
    for (final id in _membersOf(_focus)) {
      final d = widget.service.byId(id);
      if (d != null) widget.service.setBrightness(d, _bri.round());
    }
  }

  /// Sincroniza `_bri` con el brillo REAL de la(s) luz(es) en foco, para que el
  /// control de la derecha refleje siempre el estado de lo seleccionado.
  /// - 1 luz: su `state.bri`.
  /// - varias: el PROMEDIO de las que reportan brillo (representa al grupo).
  /// Si no hay foco/luces, se deja el valor actual.
  void _syncBriFromFocus() {
    final ids = _membersOf(_focus);
    if (ids.isEmpty) return;
    var sum = 0, n = 0;
    for (final id in ids) {
      final d = widget.service.byId(id);
      if (d == null) continue;
      sum += d.state.bri;
      n++;
    }
    if (n == 0) return;
    setState(() => _bri = (sum / n).clamp(0, 254).toDouble());
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
        // Mismo lienzo que el resto de la app. El RadialGradient propio que
        // tenía esta pantalla era una de las nueve superficies distintas que
        // convivían: al navegar, el fondo cambiaba de tono sin motivo.
        color: CceColors.bg,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: widget.service,
            builder: (context, _) {
            // Un solo eje vertical, de lo principal a lo secundario: qué luces
            // estás editando (barra), con qué color (disco), en qué modo, con
            // cuánto brillo, y recién al final cuáles del ambiente. Antes el
            // modo y el brillo compartían una fila con un hueco en el medio y
            // la tira de luces se comía 156 px del fondo.
            return Column(
              children: [
                _topBar(),
                // El disco se queda con TODO el espacio sobrante y se centra
                // en él; los controles van pegados abajo, en su orden de uso.
                // Con el layout anterior el bloque entero se centraba y
                // quedaba un hueco muerto de ~200 px entre el brillo y las
                // fichas.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = math
                          .min(c.maxWidth * 0.86, c.maxHeight * 0.92)
                          .clamp(240.0, 460.0)
                          .toDouble();
                      return Center(child: _buildDisk(size));
                    },
                  ),
                ),
                SizedBox(height: CceSpace.xl),
                _modeRow(),
                SizedBox(height: CceSpace.xl),
                _brightnessRow(),
                SizedBox(height: CceSpace.xl),
                _deviceStrip(),
                SizedBox(height: CceSpace.lg),
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
          SizedBox(width: CceSpace.md),
          // "Listo" cierra la pantalla: es la acción principal, así que lleva
          // el acento en fill. Antes era un chip gris con relieve, del mismo
          // peso visual que cualquier control secundario.
          Material(
            color: CceColors.accent,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: CceSpace.xl,
                  vertical: CceSpace.md,
                ),
                child: Text(
                  'Listo',
                  style: CceText.label.copyWith(
                    color: CceTint.inkOnPastel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Modo color / blanco. Sólo aparece si la selección soporta ambos.
  Widget _modeRow() {
    final focus = _membersOf(_focus);
    final anyColor =
        focus.any((id) => widget.service.byId(id)?.supportsColor ?? false);
    final anyCt =
        focus.any((id) => widget.service.byId(id)?.supportsCT ?? false);
    if (!(anyColor && anyCt)) return const SizedBox.shrink();
    return _ModeToggle(mode: _mode, onChanged: _setMode);
  }

  Widget _brightnessRow() {
    final focus = _membersOf(_focus);
    final anyBri =
        focus.any((id) => widget.service.byId(id)?.supportsBrightness ?? false);
    if (!anyBri) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: CceSpace.xl),
      child: _BrightnessBar(
        value: _bri,
        count: focus.length,
        onChanged: _onBrightness,
        onEnd: _commitBrightness,
      ),
    );
  }

  Widget _deviceStrip() {
    final lights = _roomLights();
    if (lights.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _LightChip.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: CceSpace.xl),
        itemCount: lights.length,
        separatorBuilder: (_, __) => SizedBox(width: CceSpace.sm),
        itemBuilder: (context, i) {
          final d = widget.service.byId(lights[i].id) ?? lights[i];
          final r = resolveLightColor(d.state);
          final tint = r.isWhite ? CceColors.warm : r.color;
          return _LightChip(
            name: widget.service.displayName(d),
            tint: tint,
            on: d.state.on,
            reachable: d.state.reachable,
            selected: _groupOf[d.id] == _focus,
            onTap: () => _onLightTap(d),
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
                // Halo contenido. Antes eran dos capas (34 y 90 px de blur)
                // que lavaban medio fondo de la pantalla y le quitaban al
                // disco su borde: con el halo tan abierto, el disco dejaba de
                // tener una forma definida y se leía como una mancha.
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.16),
                    blurRadius: 28,
                    spreadRadius: -8,
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

/// Marcador de selección sobre el disco: un CÍRCULO relleno con el color
/// elegido, con aro blanco y sombra de contacto.
///
/// Antes era un pin de mapa (cabeza ancha arriba + punta abajo señalando el
/// punto). Ese patrón viene de la cartografía, donde el marcador tiene que
/// señalar un lugar SIN taparlo. Acá pasa exactamente lo contrario: lo que
/// estás eligiendo es el color que está debajo del dedo, así que el marcador
/// tiene que MOSTRARLO, no apuntarlo. Con el pin, el color seleccionado quedaba
/// a 70 px de donde tenías el dedo, y por eso la selección se sentía imprecisa.
///
/// Ahora el centro del círculo ES el punto: lo que ves adentro es exactamente
/// el color que se va a aplicar. Es lo que hace la app de Hue.
class _Marker extends StatelessWidget {
  final Widget? child; // ícono del device (cluster de 1), ya teñido con [ink]
  final String? label; // contador (cluster > 1)
  final Color color; // color seleccionado bajo el marcador (rellena el cuerpo)
  final Color ink; // tinta auto-contraste para ícono/contador (CceTint.textOn)
  const _Marker({
    this.child,
    this.label,
    required this.color,
    required this.ink,
  });

  static const double w = 52; // diámetro del marcador
  static const double h = w;

  /// El punto exacto es el CENTRO del círculo (antes era la punta inferior).
  static const double tipY = w / 2;

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
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          )
        : child;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // Aro blanco: separa el marcador de cualquier color del disco, incluso
        // cuando el color elegido es casi el mismo que el de su vecindad.
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: IconTheme.merge(
        data: const IconThemeData(shadows: <Shadow>[]),
        child: Center(child: content),
      ),
    );
  }
}

/// Pin color-aware estilo Google Maps: una sola pieza (cabeza circular ∪
/// triángulo tangente hasta la punta) rellena SÓLIDA con el color seleccionado,
/// con sheen sutil, una hairline blanca fina y sombra baja. La PUNTA inferior
/// (con núcleo blanco) marca el lugar exacto.

/// Elige entre disco de color y disco de temperatura de blanco.
///
/// Antes eran dos círculos con gradiente (arcoíris y ámbar) y la selección se
/// marcaba engrosando un borde blanco. Tenía dos problemas: se leía como un
/// switch de encendido en vez de como dos opciones, y el círculo del modo
/// "blanco" era ámbar — o sea que el swatch decía justo lo contrario de lo que
/// la opción significa. Con etiquetas no hay nada que adivinar, y usa el
/// segmented del sistema en vez de un control propio de esta pantalla.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 208,
      child: CceSegmented<_Mode>(
        value: mode,
        onChanged: onChanged,
        segments: const [
          CceSegment(value: _Mode.color, label: 'Color'),
          CceSegment(value: _Mode.white, label: 'Blanco'),
        ],
      ),
    );
  }
}

/// Control de brillo VERTICAL para la(s) luz(es) en foco: track alto con relleno
/// proporcional, % grande arriba e ícono de sol. Arrastrar (o tap) sobre la pista
/// fija el brillo; `onEnd` commitea vía el servicio. Con varias luces en foco
/// ([count] > 1) muestra "N luces" debajo para dejar claro que afecta al grupo.
/// Barra de brillo HORIZONTAL, a todo el ancho bajo el disco.
///
/// Antes era una píldora vertical de 58×168 flotando en el margen derecho.
/// Tres problemas: un gesto vertical en el borde de la pantalla compite con el
/// scroll y con el gesto de volver de iOS; el recorrido útil era de 168 px
/// contra los ~330 que da el ancho; y visualmente dejaba a la izquierda un
/// hueco que desbalanceaba toda la pantalla.
///
/// Horizontal, el pulgar la barre de una pasada, el recorrido se duplica y la
/// composición queda en un eje: disco → modo → brillo → luces.
class _BrightnessBar extends StatelessWidget {
  final double value; // 0..254
  final int count; // cantidad de luces en foco (para el caso multi-luz)
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  const _BrightnessBar({
    required this.value,
    required this.count,
    required this.onChanged,
    required this.onEnd,
  });

  static const double _trackH = 56;

  double _briForDx(double dx, double w) =>
      ((dx / w) * 254).clamp(0, 254).toDouble();

  @override
  Widget build(BuildContext context) {
    final pct = (value / 254 * 100).round();
    final t = (value / 254).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Brillo', style: CceText.label),
            const Spacer(),
            Text('$pct%', style: CceText.data),
            if (count > 1) ...[
              Text(' · ', style: CceText.caption),
              Text('$count luces', style: CceText.caption),
            ],
          ],
        ),
        SizedBox(height: CceSpace.sm),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) =>
                  onChanged(_briForDx(d.localPosition.dx, w)),
              onHorizontalDragEnd: (_) => onEnd(),
              onTapDown: (d) => onChanged(_briForDx(d.localPosition.dx, w)),
              onTapUp: (_) => onEnd(),
              child: Container(
                height: _trackH,
                // Ancho explícito: dentro de un Column con crossAxisAlignment
                // .start, un Container sin width colapsa al tamaño de su
                // contenido — el track quedaba tan largo como el relleno, así
                // que la barra se veía cortada en vez de llena hasta el valor.
                width: double.infinity,
                decoration: BoxDecoration(
                  // El track usa surfaceHigh, no surfaceSunken: sobre un
                  // lienzo casi negro, un hueco todavía más oscuro es
                  // invisible, y la barra se leía CORTADA en el punto del
                  // relleno en vez de llena hasta ahí. El recorrido completo
                  // tiene que verse para que el porcentaje signifique algo.
                  color: CceColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(CceRadii.control),
                  border: Border.all(color: CceColors.stroke),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Relleno. Color plano, no gradiente: el degradado hacia
                    // crema hacía que el extremo derecho se aclarara justo
                    // donde termina, y la barra parecía seguir más allá de su
                    // propio borde.
                    FractionallySizedBox(
                      widthFactor: t == 0 ? 0.0001 : t,
                      heightFactor: 1,
                      child: const ColoredBox(color: CceColors.accent),
                    ),
                    // ASA. Es lo que le faltaba: sin una marca en el extremo
                    // del relleno, la barra no dice dónde estás parado ni que
                    // se puede arrastrar — al 100% se lee como un bloque de
                    // color, no como un control.
                    if (t > 0.02)
                      LayoutBuilder(
                        builder: (context, cc) {
                          const grip = 5.0;
                          final x = (cc.maxWidth * t - grip - CceSpace.sm)
                              .clamp(0.0, cc.maxWidth - grip - CceSpace.sm);
                          return Padding(
                            padding: EdgeInsets.only(left: x),
                            child: Container(
                              width: grip,
                              height: 24,
                              decoration: BoxDecoration(
                                color: CceTint.inkOnPastel.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(grip / 2),
                              ),
                            ),
                          );
                        },
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: CceSpace.lg),
                      child: CceIcon(
                        CceIcons.sun,
                        size: 22,
                        // Sobre el relleno la tinta se invierte; con el brillo
                        // bajo el ícono queda sobre el hueco oscuro.
                        color: t > 0.12
                            ? CceTint.inkOnPastel
                            : CceColors.textSecondary,
                        emboss: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Ficha de una luz del ambiente en la tira inferior.
///
/// COMPACTA: swatch del color real + nombre, en una fila de 56 px. Antes era
/// una card de 124×156 con ícono, nombre, estado y switch adentro — un tercio
/// de la pantalla dedicado a *elegir cuál* luz estás editando, que es lo
/// secundario acá. El disco es lo que importa y necesita ese espacio.
///
/// El switch se fue de la ficha: apagar una luz desde el selector de color es
/// una acción de otra pantalla (la del ambiente), y su presencia hacía que la
/// mitad de los toques en la tira cambiaran el estado en vez de la selección.
/// Acá el toque hace una sola cosa: elegir qué luz estás pintando.
class _LightChip extends StatelessWidget {
  final String name;
  final Color tint; // color real de la luz
  final bool on, reachable, selected;
  final VoidCallback onTap;
  const _LightChip({
    required this.name,
    required this.tint,
    required this.on,
    required this.reachable,
    required this.selected,
    required this.onTap,
  });

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final swatch = CceTint.pastel(tint);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: height,
        padding: EdgeInsets.symmetric(horizontal: CceSpace.md),
        decoration: BoxDecoration(
          gradient: CceGradients.cardSurface(
            selected ? CceColors.surfaceHigh : CceColors.surface,
          ),
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: Border.all(
            color: selected ? CceColors.accent : CceColors.stroke,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: CceShadows.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Swatch: el color real de la lámpara. Apagada o sin conexión, el
            // círculo queda hueco — no hay color que mostrar si no hay luz.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (on && reachable) ? swatch : CceColors.surfaceSunken,
                border: Border.all(
                  color: (on && reachable)
                      ? Colors.white.withValues(alpha: 0.35)
                      : CceColors.stroke,
                ),
              ),
            ),
            SizedBox(width: CceSpace.sm),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.label.copyWith(
                color: selected ? CceColors.textPrimary : CceColors.textSecondary,
              ),
            ),
            if (!reachable) ...[
              SizedBox(width: CceSpace.sm),
              // Mismo glyph que usa LightCard para el estado sin conexión.
              const Icon(Icons.wifi_off, size: 14, color: CceColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}
