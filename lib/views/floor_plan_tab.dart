import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_segmented.dart';
import '../utils/icon_resolver.dart';
import '../utils/plan_svg_theme.dart';
import '../widgets/light_detail_sheet.dart';

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
  const FloorPlanPanel({
    super.key,
    required this.service,
    required this.ui,
    this.planId,
    this.dotSize = 56,
    this.showPlanChips = true,
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
                  decoration: BoxDecoration(
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

  const _PlanCanvas({
    required this.plan,
    required this.positions,
    required this.service,
    required this.dotSize,
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
              child: SizedBox(
                width: w,
                height: h,
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
                          ),
                        ),
                      );
                    }),
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

  const _DeviceDot({
    required this.device,
    required this.service,
    required this.size,
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
    final s = widget.device.state;
    if (s.hue != null && s.sat != null && (s.sat ?? 0) > 40) {
      final h = ((s.hue! / 65535) * 360.0).clamp(0.0, 360.0).toDouble();
      final sat = (s.sat! / 254).clamp(0.0, 1.0).toDouble();
      return HSVColor.fromAHSV(1.0, h, sat, 1.0).toColor();
    }
    return CceColors.warm;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final isLight = device.isLight && !device.isSensorDevice;
    final isContact = device.isContactSensor;
    final isMotion = device.isMotionSensor;
    final temp = device.sensor?.temperature;
    final hum = device.sensor?.humidity;
    final hasReading = temp != null || hum != null;

    // active = el dot se pinta pleno con glow; inactive = ghost dark.
    bool active;
    Color accent;
    if (isLight) {
      active = device.state.on;
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

    final icon = IconResolver.resolve(
      device,
      configuredIcon: widget.service.iconFor(device.id),
      displayName: widget.service.displayName(device),
    );

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

        final body = hasReading
            ? _readingBadge(icon, accent, temp, hum, shadows)
            : _circleDot(icon, accent, active, isLight, shadows);

        return Transform.scale(
          scale: _tapScale.value,
          child: GestureDetector(
            onTap: isLight
                ? () {
                    HapticFeedback.selectionClick();
                    _tapCtrl.forward(from: 0);
                    widget.service.toggleLight(device);
                  }
                : null,
            onLongPress: isLight
                ? () {
                    HapticFeedback.mediumImpact();
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
                : null,
            behavior: HitTestBehavior.opaque,
            child: body,
          ),
        );
      },
    );
  }

  Widget _circleDot(IconData icon, Color accent, bool active, bool isLight,
      List<BoxShadow> shadows) {
    final size = widget.size;
    if (active) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: shadows,
        ),
        child: Icon(icon, color: CceTint.textOn(accent), size: size * 0.52),
      );
    }
    // Apagado / sin actividad: ghost dark sobre el canvas.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.surfaceHigh.withValues(alpha: 0.80),
        border: Border.all(color: CceColors.stroke),
        boxShadow: shadows,
      ),
      child: Icon(
        icon,
        color: Colors.white.withValues(alpha: isLight ? 0.22 : 0.38),
        size: size * 0.52,
      ),
    );
  }

  Widget _readingBadge(IconData icon, Color color, double? temp, double? hum,
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
          Icon(icon, color: color, size: size * 0.48),
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

  static Color _colorForTemp(double t) {
    if (t < 15) return CceColors.motion;
    if (t < 20) return CceColors.ok;
    if (t < 25) return CceColors.warm;
    if (t < 30) return const Color(0xFFFF8A5C);
    return CceColors.danger;
  }
}
