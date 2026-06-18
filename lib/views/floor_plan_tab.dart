import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_segmented.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';
import '../utils/plan_svg_theme.dart';
import '../widgets/light_detail_sheet.dart';
import 'dial_switch_screen.dart';
import 'light_color_screen.dart';
import 'lock_screen.dart';
import 'switch_detail_screen.dart';
import 'thermostat_screen.dart';

/// Canvas del plano de la casa, embebible en el panel derecho de la tab Casa.
/// Si [planId] != null fuerza ese plano y oculta el selector (modo "Plano"
/// de una habitacion); con [planId] == null resuelve el default:
/// seleccion local → [UiSettingsService.lastPlanId] persistido → el plano
/// con mas dispositivos posicionados → el primero. Nunca mas "Outside".
class FloorPlanPanel extends StatefulWidget {
  final DevicesService service;
  final UiSettingsService ui;
  final String? planId;
  final double dotSize;
  final bool showPlanChips;

  /// Opt-in neumórfico (solo el TABLET lo activa). Default `false` deja el
  /// render actual intacto (phone / room_detail montan flat).
  final bool neo;

  /// Servicios de los dispositivos dedicados, opcionales. Cuando vienen, el
  /// canvas dibuja un marker de TV / JBL si hay posición para el plano activo
  /// (item 4) y el color del marker sigue su status.online/power (vía listen).
  final TvService? tv;
  final JblService? jbl;

  /// Callbacks de apertura del control dedicado (tablet): tap en el marker de
  /// TV / JBL del plano. En el tablet los setea _CasaSplit (_selectedDevice).
  final VoidCallback? onOpenTv;
  final VoidCallback? onOpenJbl;

  /// Tablet: tap en el marker de un TERMOSTATO abre el control INLINE en el
  /// panel derecho (igual que TV/JBL) en vez de empujar una ruta fullscreen.
  /// Si es null, el marker cae al Navigator.push de siempre.
  final ValueChanged<Device>? onOpenThermostat;

  const FloorPlanPanel({
    super.key,
    required this.service,
    required this.ui,
    this.planId,
    this.dotSize = 56,
    this.showPlanChips = true,
    this.neo = false,
    this.tv,
    this.jbl,
    this.onOpenTv,
    this.onOpenJbl,
    this.onOpenThermostat,
  });

  @override
  State<FloorPlanPanel> createState() => _FloorPlanPanelState();
}

class _FloorPlanPanelState extends State<FloorPlanPanel> {
  String? _selectedPlanId;

  String _activePlanId(FloorPlansData fp) {
    bool exists(String? id) => id != null && fp.plans.any((p) => p.id == id);
    if (exists(widget.planId)) return widget.planId!;
    if (exists(_selectedPlanId)) return _selectedPlanId!;
    if (exists(widget.ui.lastPlanId)) return widget.ui.lastPlanId!;
    // Default: el plano con más dispositivos posicionados.
    FloorPlan? best;
    var bestCount = -1;
    for (final p in fp.plans) {
      final count = fp.positions[p.id]?.length ?? 0;
      if (count > bestCount) {
        best = p;
        bestCount = count;
      }
    }
    return (best ?? fp.plans.first).id;
  }

  void _selectPlan(String id) {
    setState(() => _selectedPlanId = id);
    widget.ui.lastPlanId = id;
  }

  Widget _planSelector(FloorPlansData fp, FloorPlan active) {
    if (fp.plans.length <= 5) {
      return CceSegmented<String>(
        value: active.id,
        segments: [
          for (final p in fp.plans) CceSegment(value: p.id, label: p.name),
        ],
        onChanged: _selectPlan,
        neo: widget.neo,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in fp.plans)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _selectPlan(p.id),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // Neo: sólo la pill ACTIVA lleva relieve (hundida); las
                  // inactivas quedan PLANAS (neoBase sin boxShadow) para no
                  // pisar sombras entre pills contiguas. Flat: render actual.
                  decoration: widget.neo
                      ? BoxDecoration(
                          color: CceColors.neoBase,
                          borderRadius: BorderRadius.circular(CceRadii.pill),
                          boxShadow: p.id == active.id
                              ? CceShadows.neoInset(blur: 6, offset: 2)
                              : null,
                        )
                      : BoxDecoration(
                          color: p.id == active.id
                              ? CceColors.accent.withValues(alpha: 0.24)
                              : CceColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(CceRadii.pill),
                          border: Border.all(
                            color: p.id == active.id
                                ? CceColors.accent.withValues(alpha: 0.60)
                                : Colors.transparent,
                          ),
                        ),
                  alignment: Alignment.center,
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: CceColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.service, widget.ui]),
      builder: (context, _) {
        final fp = widget.service.floorPlans;
        if (fp == null || fp.plans.isEmpty) {
          if (widget.service.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(
            child: Text('No hay planos configurados', style: CceText.caption),
          );
        }

        final activeId = _activePlanId(fp);
        final plan = fp.plans.firstWhere(
          (p) => p.id == activeId,
          orElse: () => fp.plans.first,
        );
        final positions =
            fp.positions[plan.id] ?? const <String, LightPosition>{};
        // Posición única (por plano) de los dispositivos dedicados.
        final tvPos = fp.tvPositions[plan.id];
        final jblPos = fp.jblPositions[plan.id];
        final showChips =
            widget.showPlanChips && widget.planId == null && fp.plans.length > 1;

        return Column(
          children: [
            if (showChips)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _planSelector(fp, plan),
              ),
            if (showChips && positions.length < 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: CceCard(
                  radius: CceRadii.control,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: true,
                  child: Text(
                    'Este plano tiene ${positions.length} '
                    '${positions.length == 1 ? 'dispositivo' : 'dispositivos'}'
                    ' — elegí otro',
                    style: CceText.caption,
                  ),
                ),
              ),
            Expanded(
              child: _PlanCanvas(
                plan: plan,
                positions: positions,
                service: widget.service,
                dotSize: widget.dotSize,
                neo: widget.neo,
                // En el tablet (neo) el tap abre el control en vez de toggle.
                openOnTap: widget.neo,
                tv: widget.tv,
                jbl: widget.jbl,
                tvPos: tvPos,
                jblPos: jblPos,
                onOpenTv: widget.onOpenTv,
                onOpenJbl: widget.onOpenJbl,
                onOpenThermostat: widget.onOpenThermostat,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlanCanvas extends StatelessWidget {
  final FloorPlan plan;
  final Map<String, LightPosition> positions;
  final DevicesService service;
  final double dotSize;
  final bool neo;

  /// Tablet: el tap en un dot de luz ABRE su control (LightColorScreen) en vez
  /// de hacer toggle. En phone (`false`) se mantiene tap = toggle.
  final bool openOnTap;

  /// Dispositivos dedicados + su posición única en el plano activo (o null si
  /// no hay posición / no se pasaron los services).
  final TvService? tv;
  final JblService? jbl;
  final LightPosition? tvPos;
  final LightPosition? jblPos;
  final VoidCallback? onOpenTv;
  final VoidCallback? onOpenJbl;
  final ValueChanged<Device>? onOpenThermostat;

  const _PlanCanvas({
    required this.plan,
    required this.positions,
    required this.service,
    required this.dotSize,
    this.neo = false,
    this.openOnTap = false,
    this.tv,
    this.jbl,
    this.tvPos,
    this.jblPos,
    this.onOpenTv,
    this.onOpenJbl,
    this.onOpenThermostat,
  });

  /// Parser completo del viewBox: comillas simples o dobles, captura los 4
  /// valores (min-x, min-y, w, h). Fallback 800×600 SOLO si no hay viewBox.
  ({double minX, double minY, double w, double h}) _viewBox() {
    final match = RegExp(
      "viewBox=[\"']\\s*([\\d.eE+\\-]+)[\\s,]+([\\d.eE+\\-]+)"
      "[\\s,]+([\\d.eE+\\-]+)[\\s,]+([\\d.eE+\\-]+)",
    ).firstMatch(plan.svg);
    if (match != null) {
      final minX = double.tryParse(match.group(1)!);
      final minY = double.tryParse(match.group(2)!);
      final w = double.tryParse(match.group(3)!);
      final h = double.tryParse(match.group(4)!);
      if (minX != null && minY != null && w != null && h != null && w > 0 && h > 0) {
        return (minX: minX, minY: minY, w: w, h: h);
      }
    }
    debugPrint('[FloorPlan] SVG de "${plan.name}" sin viewBox parseable — '
        'fallback 800×600');
    return (minX: 0.0, minY: 0.0, w: 800.0, h: 600.0);
  }

  @override
  Widget build(BuildContext context) {
    final vb = _viewBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - 32;
        final availH = constraints.maxHeight - 32;
        final scale =
            (availW / vb.w < availH / vb.h) ? availW / vb.w : availH / vb.h;
        final w = vb.w * scale;
        final h = vb.h * scale;
        final half = dotSize / 2;

        // Clamp del CENTRO del dot a [half+4, lado − half − 4]; si el canvas
        // es más chico que el dot, centrar.
        double clampCenter(double v, double side) {
          final lo = half + 4;
          final hi = side - half - 4;
          if (hi <= lo) return side / 2;
          return v.clamp(lo, hi).toDouble();
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 3.5,
              // Neo: relieve raised por DETRÁS del ClipRRect. intensity:1 y
              // offset:8 porque el contraste neoBase→neoLight es bajo (con los
              // defaults el relieve sería casi invisible). El color opaco
              // neoBase asienta la sombra; el RadialGradient interno y el
              // borde hairline se conservan dentro del ClipRRect.
              child: Container(
                width: w,
                height: h,
                decoration: neo
                    ? BoxDecoration(
                        color: CceColors.neoBase,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow:
                            CceShadows.neo(blur: 20, offset: 8, intensity: 1),
                      )
                    : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0, -0.2),
                              radius: 1.1,
                              colors: [
                                CceColors.planCanvasHi,
                                CceColors.planCanvasLo,
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: SvgPicture.string(
                                  PlanSvgTheme.darken(plan.svg),
                                  fit: BoxFit.fill,
                                  width: w,
                                  height: h,
                                ),
                              ),
                              // Vignette inferior para asentar el plano.
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 80,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          const Color(0xFF101014)
                                              .withValues(alpha: 0.55),
                                          const Color(0xFF101014)
                                              .withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Borde hairline por encima del clip.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: CceColors.stroke),
                          ),
                        ),
                      ),
                    ),
                    ...positions.entries.map((e) {
                      final device = service.byId(e.key);
                      if (device == null) return const SizedBox.shrink();
                      final px =
                          clampCenter((e.value.x - vb.minX) * scale, w);
                      final py =
                          clampCenter((e.value.y - vb.minY) * scale, h);
                      return Positioned(
                        left: px,
                        top: py,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: _DeviceDot(
                            device: device,
                            service: service,
                            size: dotSize,
                            openOnTap: openOnTap,
                            onOpenThermostat: onOpenThermostat,
                          ),
                        ),
                      );
                    }),
                    // Markers de dispositivos dedicados (TV / JBL): misma
                    // fórmula de proyección que las luces; sólo si hay posición
                    // para el plano activo y el service correspondiente vino.
                    if (tv != null && tvPos != null)
                      Positioned(
                        left: clampCenter((tvPos!.x - vb.minX) * scale, w),
                        top: clampCenter((tvPos!.y - vb.minY) * scale, h),
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: _DeviceMarker(
                            listenable: tv!,
                            shape: _MarkerShape.tv,
                            label: '', // sin nombre en el plano
                            onColor: const Color(0xFF3A6BC5), // azul (el que tenía el soundbar)
                            isOnline: () => tv!.online,
                            isOn: () => tv!.isOn,
                            size: dotSize,
                            onTap: onOpenTv,
                          ),
                        ),
                      ),
                    if (jbl != null && jblPos != null)
                      Positioned(
                        left: clampCenter((jblPos!.x - vb.minX) * scale, w),
                        top: clampCenter((jblPos!.y - vb.minY) * scale, h),
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: _DeviceMarker(
                            listenable: jbl!,
                            shape: _MarkerShape.jbl,
                            label: '', // sin nombre en el plano
                            onColor: const Color(0xFFE06A2C), // naranja JBL (no chillón)
                            isOnline: () => jbl!.online,
                            isOn: () => jbl!.isOn,
                            size: dotSize,
                            onTap: onOpenJbl,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceDot extends StatefulWidget {
  final Device device;
  final DevicesService service;
  final double size;

  /// Tablet: tap ABRE el control (LightColorScreen) en vez de togglear.
  final bool openOnTap;

  /// Tablet: abre el termostato INLINE en el panel derecho (si no es null, el
  /// tap del marker llama esto en vez de empujar ThermostatScreen).
  final ValueChanged<Device>? onOpenThermostat;

  const _DeviceDot({
    required this.device,
    required this.service,
    required this.size,
    this.openOnTap = false,
    this.onOpenThermostat,
  });

  @override
  State<_DeviceDot> createState() => _DeviceDotState();
}

class _DeviceDotState extends State<_DeviceDot> with TickerProviderStateMixin {
  // Tap = pulso de escala 1 → 1.15 → 1 en 250 ms.
  late final AnimationController _tapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _tapScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.15)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.15, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_tapCtrl);

  // Update por WS = pulso de glow (blur 18 → 30 → 18), sin escala.
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _glowBlur = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 18.0, end: 30.0), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 30.0, end: 18.0), weight: 50),
  ]).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

  DateTime? _lastSeenEvent;

  @override
  void initState() {
    super.initState();
    _lastSeenEvent = widget.device.lastEventAt;
  }

  @override
  void didUpdateWidget(covariant _DeviceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = widget.device.lastEventAt;
    if (t != null && t != _lastSeenEvent) {
      _lastSeenEvent = t;
      _glowCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Color _lightColor() {
    final r = resolveLightColor(widget.device.state);
    return r.isWhite ? CceColors.warm : r.color;
  }

  /// Ícono del device con la MISMA resolución que la lista (MDI / icons0 SVG /
  /// emoji), para que plano y lista coincidan.
  Widget _iconWidget(double size, Color color) => IconResolver.widget(
        widget.device,
        configuredIcon: widget.service.iconFor(widget.device.id),
        customIcons: widget.service.customIcons,
        displayName: widget.service.displayName(widget.device),
        size: size,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    // Termostato y cerradura cortan ANTES que los branches genéricos: tienen
    // marker propio (badge de temperatura / candado) y nunca caen en el dot de
    // luz/sensor. isLight ya los excluye (Device.isLight devuelve false), pero
    // explicitamos el guard para que el orden de prioridad quede claro.
    final isThermostat = device.isThermostat;
    final isLock = device.isLock;
    final isLight =
        device.isLight && !device.isSensorDevice && !isThermostat && !isLock;
    final isContact = device.isContactSensor;
    final isMotion = device.isMotionSensor;
    final temp = device.sensor?.temperature;
    final hum = device.sensor?.humidity;
    final hasReading = temp != null || hum != null;

    // Luz sin conexión: nunca activa, se pinta como ghost + badge wifi-off.
    final offline = isLight && !device.state.reachable;

    // Cerradura: trabada (state.on) = verde / destrabada = ámbar / offline =
    // gris. Espeja la convención del LockScreen (state.on == isLocked).
    final lockLocked = device.state.on;
    final lockOnline = device.state.reachable;
    // Batería baja del sensor de la cerradura ("NN%" → int) <= 20%.
    int? lockBatteryPct;
    if (isLock) {
      final raw = device.sensor?.battery;
      if (raw != null) {
        final m = RegExp(r'(\d+)').firstMatch(raw);
        if (m != null) lockBatteryPct = int.tryParse(m.group(1)!);
      }
    }

    // active = el dot se pinta pleno con glow; inactive = ghost dark.
    bool active;
    Color accent;
    if (isThermostat) {
      // El termostato siempre "vive": glow tenue con el acento del modo.
      active = device.state.on;
      accent = _thermostatAccent(device.state);
    } else if (isLock) {
      active = lockOnline && lockLocked;
      accent = !lockOnline
          ? CceColors.textTertiary
          : (lockLocked ? CceColors.ok : CceColors.contact);
    } else if (isLight) {
      active = device.state.on && !offline;
      accent = active ? CceTint.normalize(_lightColor()) : CceColors.warm;
    } else if (isContact) {
      active = device.sensor?.contact == true;
      accent = CceColors.contact;
    } else if (isMotion) {
      active = device.sensor?.motion == true;
      accent = CceColors.motion;
    } else if (temp != null) {
      active = true;
      accent = _colorForTemp(temp);
    } else if (hum != null) {
      active = true;
      accent = CceColors.info;
    } else {
      active = false;
      accent = Colors.white54;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_tapCtrl, _glowCtrl]),
      builder: (context, _) {
        final blur = _glowCtrl.isAnimating ? _glowBlur.value : 18.0;
        final List<BoxShadow> shadows;
        if (active) {
          shadows = [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: blur,
              spreadRadius: 2,
            ),
          ];
        } else if (_glowCtrl.isAnimating) {
          // Dots inactivos también avisan el update, más tenue.
          shadows = [
            BoxShadow(
              color: accent.withValues(alpha: 0.30),
              blurRadius: blur,
              spreadRadius: 2,
            ),
          ];
        } else {
          shadows = const [];
        }

        final Widget body;
        if (isThermostat) {
          body = _thermostatBadge(accent, device.state, shadows);
        } else if (isLock) {
          body = _lockMarker(accent, lockLocked, lockOnline, lockBatteryPct,
              shadows);
        } else if (hasReading) {
          body = _readingBadge(accent, temp, hum, shadows);
        } else {
          body = _circleDot(accent, active, isLight, shadows, offline);
        }

        // Item 5: el botón/switch sólo es tocable en el tablet (openOnTap); en
        // el phone queda inerte (sin openOnTap) para no cambiar su conducta.
        // Termostato y cerradura SIEMPRE abren su pantalla (este plano vive en
        // el tablet); la luz siempre togglea (ver onTap).
        final isSwitch = device.isSwitch;
        final tappable =
            isLight || isThermostat || isLock || (widget.openOnTap && isSwitch);

        return Transform.scale(
          scale: _tapScale.value,
          child: GestureDetector(
            onTap: !tappable
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    _tapCtrl.forward(from: 0);
                    if (isThermostat) {
                      // Termostato: en tablet abre INLINE en el panel derecho
                      // (onOpenThermostat); si no, empuja ThermostatScreen.
                      // Nunca togglea desde el plano.
                      if (widget.onOpenThermostat != null) {
                        widget.onOpenThermostat!(device);
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ThermostatScreen(
                              device: device,
                              service: widget.service,
                            ),
                          ),
                        );
                      }
                    } else if (isLock) {
                      // Cerradura: abrir LockScreen. NUNCA togglear desde el
                      // plano: la apertura es una acción de seguridad con
                      // hold-to-confirm dentro de la pantalla dedicada.
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LockScreen(
                            device: device,
                            service: widget.service,
                          ),
                        ),
                      );
                    } else if (isLight) {
                      // El tap de una LUZ SIEMPRE togglea (prender/apagar),
                      // incluso en el tablet (openOnTap), donde el resto de los
                      // devices abre su control. Divergencia deliberada: el
                      // gesto más rápido y frecuente sobre una luz es encender/
                      // apagar, no recolorear; el selector de color se movió al
                      // long-press (ver onLongPress).
                      widget.service.toggleLight(device);
                    } else {
                      // Tablet + botón/switch: abrir su pantalla canónica (la
                      // misma que usa SensorTile): dial si es multi-botón.
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => device.isMultiButton
                              ? DialSwitchScreen(
                                  device: device,
                                  service: widget.service,
                                )
                              : SwitchDetailScreen(
                                  device: device,
                                  service: widget.service,
                                ),
                        ),
                      );
                    }
                  },
            onLongPress: isLight
                ? () {
                    HapticFeedback.mediumImpact();
                    if (widget.openOnTap) {
                      // Tablet: como el tap ahora togglea, el acceso al color
                      // vive en el long-press → LightColorScreen (su top bar
                      // tiene cerrar + "Listo", así que el back funciona).
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LightColorScreen(
                            device: device,
                            service: widget.service,
                          ),
                        ),
                      );
                    } else {
                      // Phone: se mantiene el sheet de detalle de la luz.
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => LightDetailSheet(
                          device: device,
                          service: widget.service,
                        ),
                      );
                    }
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: body,
          ),
        );
      },
    );
  }

  Widget _circleDot(Color accent, bool active, bool isLight,
      List<BoxShadow> shadows, bool offline) {
    final size = widget.size;
    if (active) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: shadows,
        ),
        // Dot activo: glyph sobre fill accent saturado -> sin relieve (mismo
        // criterio que RoomCard / LightCard). `shadows: []` aplana el Icon de
        // Material y el CceIcon por igual; el dot apagado (sobre superficie
        // oscura) conserva su relieve.
        child: IconTheme.merge(
          data: const IconThemeData(shadows: <Shadow>[]),
          child: _iconWidget(size * 0.52, CceTint.textOn(accent)),
        ),
      );
    }
    // Apagado / sin actividad: ghost dark sobre el canvas.
    final ghost = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.surfaceHigh.withValues(alpha: 0.80),
        border: Border.all(
          color: offline
              ? CceColors.danger.withValues(alpha: 0.55)
              : CceColors.stroke,
        ),
        boxShadow: shadows,
      ),
      child: _iconWidget(
        size * 0.52,
        Colors.white.withValues(alpha: isLight ? 0.22 : 0.38),
      ),
    );
    if (!offline) return ghost;
    // Badge wifi-off en la esquina inferior derecha para luces sin conexión.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ghost,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: size * 0.40,
            height: size * 0.40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.surface,
              border: Border.all(color: CceColors.danger, width: 1.5),
            ),
            child: Icon(
              Icons.wifi_off,
              size: size * 0.22,
              color: CceColors.danger,
              // Badge minusculo (~10px) en circulo: el relieve lo ensuciaria.
              shadows: const [],
            ),
          ),
        ),
      ],
    );
  }

  Widget _readingBadge(Color color, double? temp, double? hum,
      List<BoxShadow> shadows) {
    final size = widget.size;
    final label = temp != null
        ? '${temp.toStringAsFixed(1)}°'
        : '${hum!.toStringAsFixed(0)}%';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.18,
        vertical: size * 0.14,
      ),
      decoration: BoxDecoration(
        color: CceColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(size * 0.45),
        border: Border.all(color: color, width: 2.5),
        boxShadow: shadows,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconWidget(size * 0.48, color),
          SizedBox(width: size * 0.12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Acento del termostato por systemMode (frío → info, resto → cálido),
  /// espejando ThermostatScreen._accentFor.
  static Color _thermostatAccent(DeviceState s) {
    final mode = (s.systemMode ?? '').toLowerCase();
    if (mode.contains('cool') || mode.contains('frio') || mode.contains('frío')) {
      return CceColors.info;
    }
    return CceColors.warm;
  }

  /// Glifo del termostato por systemMode (copo / llama), igual que la pantalla.
  static String _thermostatIcon(DeviceState s) {
    final mode = (s.systemMode ?? '').toLowerCase();
    if (mode.contains('cool') || mode.contains('frio') || mode.contains('frío')) {
      return CceIcons.snowflake;
    }
    return CceIcons.flame;
  }

  /// Badge del termostato: temperatura ambiente (currentTemp) GRANDE + setpoint
  /// (targetTemp) chico debajo, con el glifo del modo. Reemplaza al dot
  /// genérico para que el plano muestre de un vistazo cuánto hace y a cuánto va.
  Widget _thermostatBadge(
      Color accent, DeviceState s, List<BoxShadow> shadows) {
    final size = widget.size;
    final current = s.currentTemp;
    final target = s.targetTemp;
    final currentLabel =
        current != null ? '${current.toStringAsFixed(1)}°' : '—';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.20,
        vertical: size * 0.12,
      ),
      decoration: BoxDecoration(
        color: CceColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: accent, width: 2.5),
        boxShadow: shadows,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(_thermostatIcon(s), size: size * 0.42, color: accent),
          SizedBox(width: size * 0.12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentLabel,
                style: TextStyle(
                  color: accent,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
              if (target != null)
                Text(
                  '→ ${target.toStringAsFixed(1)}°',
                  style: TextStyle(
                    color: CceColors.textSecondary,
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Marker dedicado de la cerradura: círculo con el candado (trabado/destrabado
  /// según [locked]), tinte del estado ([accent]: verde / ámbar / gris offline)
  /// y badge de batería baja en la esquina si [batteryPct] <= 20%.
  Widget _lockMarker(Color accent, bool locked, bool online, int? batteryPct,
      List<BoxShadow> shadows) {
    final size = widget.size;
    final glyph = locked ? CceIcons.lockLocked : CceIcons.lockUnlocked;
    final marker = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Trabada/online: fill pleno (lectura inmediata "todo cerrado");
        // destrabada u offline: ghost con borde de color.
        color: (online && locked)
            ? accent
            : CceColors.surfaceHigh.withValues(alpha: 0.80),
        border: Border.all(
          color: accent.withValues(alpha: online ? 0.85 : 0.55),
          width: 2,
        ),
        boxShadow: shadows,
      ),
      child: IconTheme.merge(
        data: const IconThemeData(shadows: <Shadow>[]),
        child: CceIcon(
          glyph,
          size: size * 0.50,
          color: (online && locked) ? CceTint.textOn(accent) : accent,
          emboss: !(online && locked),
        ),
      ),
    );
    final lowBattery = batteryPct != null && batteryPct <= 20;
    if (!lowBattery) return marker;
    // Badge batería baja en la esquina inferior derecha.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        marker,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: size * 0.40,
            height: size * 0.40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.surface,
              border: Border.all(color: CceColors.danger, width: 1.5),
            ),
            child: CceIcon(
              CceIcons.batteryWarning,
              size: size * 0.24,
              color: CceColors.danger,
              emboss: false,
            ),
          ),
        ),
      ],
    );
  }

  static Color _colorForTemp(double t) {
    if (t < 15) return CceColors.motion;
    if (t < 20) return CceColors.ok;
    if (t < 25) return CceColors.warm;
    if (t < 30) return const Color(0xFFFF8A5C);
    return CceColors.danger;
  }
}

/// Forma del marker dedicado. Espeja la web (floor-plan.component.ts):
/// ambas son píldoras verticales; la TV dibuja la pantalla mirando a la
/// izquierda (línea de borde + triángulo), la JBL es una píldora lisa.
enum _MarkerShape { tv, jbl }

/// Marker de un dispositivo dedicado (TV / JBL) en el plano, espejando el
/// dashboard web: una píldora vertical con el logo de marca centrado
/// ([CceIcons.samsung] / [CceIcons.jbl]), un punto de estado online en la
/// esquina superior derecha y un [label] debajo. Color de marca [onColor]
/// cuando online && encendido; gris [_offColor] si no. Escucha el
/// [listenable] (el propio service) para recolorear con el status.
/// Tap → [onTap] (abre el control dedicado).
class _DeviceMarker extends StatelessWidget {
  final Listenable listenable;
  final _MarkerShape shape;
  final String label;
  final Color onColor;
  final bool Function() isOnline;
  final bool Function() isOn;
  final double size;
  final VoidCallback? onTap;

  static const Color _offColor = Color(0xFF9E9E9E);

  const _DeviceMarker({
    required this.listenable,
    required this.shape,
    required this.label,
    required this.onColor,
    required this.isOnline,
    required this.isOn,
    required this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final online = isOnline();
        final active = online && isOn();
        final accent = active ? onColor : _offColor;

        // Proporción ~18×100 de la web, escalada al dotSize del plano sin
        // pisar dots vecinos.
        final pillW = size * 0.34;
        final pillH = size * 1.40;
        final isTv = shape == _MarkerShape.tv;

        final pill = Container(
          width: pillW,
          height: pillH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(pillW),
            // TV: borde izquierdo marcado = la pantalla mira a la izquierda.
            border: isTv
                ? Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 2,
                    ),
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          // El logo de Samsung (TV) va GIRADO 90° dentro de la píldora vertical;
          // el de JBL queda derecho.
          child: () {
            final glyph = CceIcon(
              isTv ? CceIcons.samsung : CceIcons.jbl,
              size: pillW * 0.78,
              color: active
                  ? CceTint.textOn(accent)
                  : Colors.white.withValues(alpha: 0.85),
              emboss: false,
            );
            return isTv
                ? RotatedBox(quarterTurns: 1, child: glyph)
                : glyph;
          }(),
        );

        // Triángulo apuntando a la IZQUIERDA, pegado al borde de la pantalla.
        // El CUERPO del TV NO se gira; solo el logo Samsung de adentro (arriba).
        final pillWithScreen = isTv
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CustomPaint(
                    size: Size(size * 0.12, size * 0.20),
                    painter: _LeftTrianglePainter(accent),
                  ),
                  pill,
                ],
              )
            : pill;

        final onlineDot = Container(
          width: size * 0.20,
          height: size * 0.20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? CceColors.ok : _offColor,
            border: Border.all(color: CceColors.surface, width: 1.5),
          ),
        );

        final body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                pillWithScreen,
                Positioned(
                  right: -size * 0.06,
                  top: -size * 0.06,
                  child: onlineDot,
                ),
              ],
            ),
            if (label.isNotEmpty) ...[
              SizedBox(height: size * 0.10),
              Text(
                label,
                style: TextStyle(
                  color: CceColors.textPrimary,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ],
        );

        return GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          behavior: HitTestBehavior.opaque,
          child: body,
        );
      },
    );
  }
}

/// Triángulo isósceles que apunta a la izquierda (la pantalla del TV).
class _LeftTrianglePainter extends CustomPainter {
  final Color color;
  const _LeftTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LeftTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
