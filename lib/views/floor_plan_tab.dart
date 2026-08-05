import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../models/vacuum_map.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_segmented.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';
import '../utils/plan_svg_theme.dart';
import '../utils/vacuum_state.dart';
import '../widgets/light_detail_sheet.dart';
import 'dial_switch_screen.dart';
import 'light_color_screen.dart';
import 'lock_screen.dart';
import 'switch_detail_screen.dart';
import 'thermostat_screen.dart';

/// Teal del robot. No sale de la paleta: el robot no es un estado de la casa
/// (como una luz prendida) sino un aparato TRABAJANDO, y conviene que se
/// distinga del acento violeta. Mismo valor que usa el dashboard web.
const Color _vacuumTeal = Color(0xFF14B8A6);

/// Lo que hay que pintar del robot mientras trabaja.
class _VacuumStatus {
  /// Plano que está limpiando, o null si no hay forma de saberlo (la limpieza
  /// no salió de una cola de CCE — p.ej. lanzada desde la app de Roborock).
  final String? planId;
  final String label;
  final int? battery;

  const _VacuumStatus({this.planId, required this.label, this.battery});
}

/// Diámetro base de los dots de devices sobre el plano (= el "medium" del
/// TileSize global que los gobernaba antes). El tamaño efectivo es esto por
/// el markerScale del plano — un atributo DEL PLANO, compartido con el
/// dashboard, no una preferencia local del tablet.
const double kFloorPlanBaseDotSize = 56;

/// Canvas del plano de la casa, embebible en el panel derecho de la tab Casa.
/// Si [planId] != null fuerza ese plano y oculta el selector (modo "Plano"
/// de una habitacion); con [planId] == null resuelve el default:
/// [UiSettingsService.lastPlanId] persistido → el plano con mas dispositivos
/// posicionados → el primero. Nunca mas "Outside".
class FloorPlanPanel extends StatefulWidget {
  final DevicesService service;
  final UiSettingsService ui;
  final String? planId;
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
  /// [FloorPlansData.visiblePlan] con [UiSettingsService.lastPlanId] como
  /// candidato: la MISMA resolución que usa [PlanMarkerScaleButtons] en la
  /// toolbar. Sin estado local: si el panel y la toolbar resolvieran
  /// distinto, los botones ajustarían un plano que no se ve.
  String _activePlanId(FloorPlansData fp) {
    bool exists(String? id) => id != null && fp.plans.any((p) => p.id == id);
    if (exists(widget.planId)) return widget.planId!;
    return fp.visiblePlan(widget.ui.lastPlanId)!.id;
  }

  void _selectPlan(String id) {
    // lastPlanId notifica y el AnimatedBuilder (que ya escucha widget.ui)
    // re-renderiza: la selección responde igual que con estado local.
    widget.ui.lastPlanId = id;
  }

  /// Cruza el robot con los planos: qué room está limpiando y cómo mostrarlo.
  /// Devuelve null cuando está en la base, que es el caso normal.
  _VacuumStatus? _vacuumStatus(FloorPlansData fp) {
    Device? robot;
    for (final d in widget.service.vacuums) {
      if (vacuumWorking(d)) {
        robot = d;
        break;
      }
    }
    if (robot == null) return null;

    // Mientras hace una faena EN LA BASE no se marca ninguna room: la cola
    // puede seguir viva, pero el robot no está en esa habitación.
    const enLaBase = {'washing_mop', 'emptying_bin', 'charging', 'charge_complete', 'idle'};
    final faena = enLaBase.contains(robot.state.vacuumActivity) ? true : null;

    final q = robot.state.roomQueue;
    final seg = q?.currentSegment;
    String? planId;
    // Durante una faena el robot está EN LA BASE, aunque la cola siga viva:
    // marcar la room siguiente diría que está ahí, y no lo está.
    if (seg != null && faena == null) {
      for (final p in fp.plans) {
        final vr = p.vacuumRoom;
        if (vr != null && vr.deviceId == robot.id && vr.segmentId == seg) {
          planId = p.id;
          break;
        }
      }
    }

    return _VacuumStatus(
      planId: planId,
      // El texto ya viene resuelto (incluye "a <habitación>" cuando se sabe).
      label: vacuumStateLabel(robot) ?? 'Trabajando',
      battery: robot.state.battery,
    );
  }

  /// Chip flotante sobre el plano. `IgnorePointer` para no comerle los gestos
  /// de pan/zoom al canvas.
  Widget _vacuumChip(_VacuumStatus vs) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: CceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          border: Border.all(color: _vacuumTeal.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CceIcon(CceIcons.robotVacuum,
                size: 16, color: _vacuumTeal, emboss: false),
            const SizedBox(width: 7),
            Text(vs.label, style: CceText.caption),
            if (vs.battery != null) ...[
              const SizedBox(width: 7),
              Text('${vs.battery}%', style: CceText.caption),
            ],
          ],
        ),
      ),
    );
  }

  /// [vacuumPlanId] marca con el ícono del robot el plano que se está
  /// limpiando. En el modo segmentado (≤5 planos) no se marca: CceSegment sólo
  /// acepta un label de texto. Ahí alcanza el chip, que nombra la habitación.
  Widget _planSelector(FloorPlansData fp, FloorPlan active,
      [String? vacuumPlanId]) {
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: CceColors.textPrimary,
                        ),
                      ),
                      if (p.id == vacuumPlanId) ...[
                        const SizedBox(width: 6),
                        const CceIcon(CceIcons.robotVacuum,
                            size: 15, color: _vacuumTeal, emboss: false),
                      ],
                    ],
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
        // Tamaño por plano: acá ya se conoce `plan`, así que el diámetro se
        // resuelve acá y _PlanCanvas/_DeviceDot/_DeviceMarker no cambian.
        final dotSize = kFloorPlanBaseDotSize * (plan.markerScale ?? 1.0);
        // Posición única (por plano) de los dispositivos dedicados.
        final tvPos = fp.tvPositions[plan.id];
        final jblPos = fp.jblPositions[plan.id];
        final showChips =
            widget.showPlanChips && widget.planId == null && fp.plans.length > 1;
        final vacuum = _vacuumStatus(fp);

        return Column(
          children: [
            if (showChips)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _planSelector(fp, plan, vacuum?.planId),
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _PlanCanvas(
                      plan: plan,
                      positions: positions,
                      service: widget.service,
                      dotSize: dotSize,
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
                  // El plano que se está mirando ES el que limpia el robot.
                  if (vacuum != null && vacuum.planId == plan.id)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _vacuumTeal.withValues(alpha: 0.55),
                                width: 2),
                            borderRadius:
                                BorderRadius.circular(CceRadii.control),
                          ),
                        ),
                      ),
                    ),
                  if (vacuum != null)
                    Positioned(top: 10, left: 12, child: _vacuumChip(vacuum)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Botones –/+ del tamaño de los markers del plano VISIBLE. Van en la toolbar
/// de las vistas tablet, donde antes estaba el ciclo global de TileSize (que
/// ahora gobierna solo las grillas de cards): en modo Plano el control de
/// tamaño ajusta ESTE plano, lo persiste en el backend y lo comparte con el
/// dashboard. Clamp 0.1–3.0 con paso 0.2 que baja a 0.1 por debajo de 0.6,
/// el mismo esquema del dashboard.
class PlanMarkerScaleButtons extends StatelessWidget {
  const PlanMarkerScaleButtons({
    super.key,
    required this.service,
    required this.ui,
    this.planId,
    this.neo = false,
  });

  final DevicesService service;
  final UiSettingsService ui;

  /// Plano forzado (el modo Plano de una habitación); null = el visible en
  /// "Toda la casa", resuelto igual que en [FloorPlanPanel].
  final String? planId;
  final bool neo;

  static const double _min = 0.1;
  static const double _max = 3.0;

  void _bump(FloorPlan plan, int dir) {
    final current = plan.markerScale ?? 1.0;
    // Por debajo de 0.6 el paso baja a 0.1: con paso fijo de 0.2 el salto
    // entre "chico" y "mínimo" era demasiado brusco para afinar.
    final step = (dir > 0 ? current < 0.6 : current <= 0.6) ? 0.1 : 0.2;
    // Snap a décimas: acumular pasos en double junta ruido binario
    // (0.6000…01) que desalinearía el clamp y los pasos del dashboard.
    final next = (((current + dir * step) * 10).roundToDouble() / 10)
        .clamp(_min, _max);
    service.setPlanMarkerScale(plan.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final fp = service.floorPlans;
    if (fp == null) return const SizedBox.shrink();
    final plan = planId != null
        ? fp.plans.where((p) => p.id == planId).firstOrNull
        : fp.visiblePlan(ui.lastPlanId);
    if (plan == null) return const SizedBox.shrink();

    final scale = plan.markerScale ?? 1.0;
    final canShrink = scale > _min;
    final canGrow = scale < _max;

    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) {
      if (neo) {
        return CceNeoIconButton(
            icon: icon, tooltip: tooltip, onPressed: onPressed);
      }
      return Tooltip(
        message: tooltip,
        child: IconButton(icon: Icon(icon), onPressed: onPressed),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove, 'Markers más chicos',
            canShrink ? () => _bump(plan, -1) : null),
        const SizedBox(width: 8),
        button(Icons.add, 'Markers más grandes',
            canGrow ? () => _bump(plan, 1) : null),
      ],
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

  /// Robot a dibujar en vivo sobre ESTE plano, o null (el caso normal: todos
  /// los planos dibujados a mano no tienen ancla). Pide las tres cosas: que el
  /// plano haya nacido del mapa del robot, que el device exista y que esté
  /// trabajando — con el criterio de siempre, [vacuumWorking].
  VacuumPosition? _vacuumPosition() {
    final anchor = plan.vacuumAnchor;
    if (anchor == null) return null;
    final robot = service.byId(anchor.deviceId);
    if (robot == null || !vacuumWorking(robot)) return null;
    return robot.state.vacuumPosition;
  }

  @override
  Widget build(BuildContext context) {
    final vb = _viewBox();
    final anchor = plan.vacuumAnchor;
    final vacuumPos = _vacuumPosition();
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
                              // El robot moviéndose, sobre el SVG y debajo de
                              // los marcadores. Sólo existe en los planos
                              // generados desde el mapa; en el resto ni se
                              // monta y la pantalla queda igual que siempre.
                              if (anchor != null && vacuumPos != null)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: _VacuumLiveLayer(
                                      anchor: anchor,
                                      position: vacuumPos,
                                      viewBox: vb,
                                      scale: scale,
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

/// Diferencia entre dos ángulos por el camino corto. Sin esto, pasar de 350° a
/// 10° hace girar al robot casi una vuelta entera para el lado equivocado.
double _shortestAngleDelta(double from, double to) {
  final d = (to - from) % 360;
  return d > 180 ? d - 360 : d;
}

/// Capa en vivo del robot sobre el plano: dónde está, hacia dónde mira y por
/// dónde viene. El chip de estado dice QUÉ hace; esto dice DÓNDE.
///
/// La posición se refresca cada ~10 s (el ritmo del poll del sidecar), así que
/// el marcador se ANIMA de una lectura a la siguiente en vez de saltar. Con la
/// app en background Flutter no produce frames: no se anima nada, y al volver
/// el marcador retoma el tramo donde había quedado.
class _VacuumLiveLayer extends StatefulWidget {
  final VacuumAnchor anchor;
  final VacuumPosition position;
  final ({double minX, double minY, double w, double h}) viewBox;

  /// Píxeles de pantalla por unidad del plano (el del viewBox, no el del ancla).
  final double scale;

  const _VacuumLiveLayer({
    required this.anchor,
    required this.position,
    required this.viewBox,
    required this.scale,
  });

  @override
  State<_VacuumLiveLayer> createState() => _VacuumLiveLayerState();
}

class _VacuumLiveLayerState extends State<_VacuumLiveLayer>
    with SingleTickerProviderStateMixin {
  /// Estela corta: las últimas ~30 lecturas (5 minutos a 10 s). La trayectoria
  /// completa la muestra la sección MAPA de la pantalla del robot.
  static const _trailMax = 30;

  /// Diámetro real del Qrevo: 35 cm = 7 píxeles de RRMap (50 mm cada uno).
  /// Mismo criterio que el dashboard, para que las dos pantallas se vean igual.
  static const _robotMapPx = 7.0;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// Lecturas ya consumidas, en unidades del plano.
  final _trail = <Offset>[];
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  double? _fromAngle;
  double? _toAngle;
  int? _lastAt;

  @override
  void initState() {
    super.initState();
    _consume(animate: false);
  }

  @override
  void didUpdateWidget(covariant _VacuumLiveLayer old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor) {
      // Cambió la transformada: la estela vieja quedó en otro sistema de
      // coordenadas y dibujaría una línea inventada.
      _trail.clear();
      _consume(animate: false);
    } else if (old.position != widget.position) {
      _consume(animate: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Offset get _currentPoint => Offset.lerp(_from, _to, _ctrl.value)!;

  double? get _currentAngle {
    final a = _fromAngle, b = _toAngle;
    if (b == null) return a;
    if (a == null) return b;
    return a + _shortestAngleDelta(a, b) * _ctrl.value;
  }

  void _consume({required bool animate}) {
    final p = widget.position;
    final plan = widget.anchor.toPlan(p.x, p.y);
    final target = Offset(plan.x, plan.y);
    // El ángulo viene en el espacio del mapa: si el ancla rota el plano, el
    // tick de orientación rota con ella. Sin ángulo se conserva el anterior.
    final angle =
        p.angle == null ? _toAngle : p.angle! + widget.anchor.rotationDeg;

    if (_trail.isEmpty || _trail.last != target) {
      _trail.add(target);
      if (_trail.length > _trailMax) _trail.removeAt(0);
    }

    if (!animate) {
      _from = _to = target;
      _fromAngle = _toAngle = angle;
      _lastAt = p.at;
      _ctrl.value = 1;
      return;
    }
    // Arranca desde lo que se está VIENDO, no desde la lectura anterior: si
    // llega una posición nueva a mitad del tramo, el marcador sigue de largo
    // en vez de pegar un tirón hacia atrás.
    _from = _currentPoint;
    _fromAngle = _currentAngle;
    _to = target;
    _toAngle = angle;
    _ctrl.duration = _legDuration(_lastAt, p.at);
    _lastAt = p.at;
    _ctrl.forward(from: 0);
  }

  /// El robot se mueve a velocidad constante, así que el tramo se recorre en el
  /// tiempo REAL que pasó entre las dos lecturas: eso es lo que lo hace ver
  /// caminando. Tope de 6 s para que el marcador nunca quede más atrás que eso
  /// de la realidad si las lecturas vinieron espaciadas.
  static Duration _legDuration(int? prevAt, int? at) {
    final delta = (prevAt != null && at != null) ? at - prevAt : 0;
    return Duration(milliseconds: delta > 0 ? delta.clamp(700, 6000) : 1200);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VacuumLivePainter(
        t: _ctrl,
        from: _from,
        to: _to,
        fromAngle: _fromAngle,
        toAngle: _toAngle,
        trail: List.of(_trail),
        viewBox: widget.viewBox,
        scale: widget.scale,
        radiusPlan: _robotMapPx / 2 * widget.anchor.scale,
      ),
    );
  }
}

class _VacuumLivePainter extends CustomPainter {
  final Animation<double> t;
  final Offset from;
  final Offset to;
  final double? fromAngle;
  final double? toAngle;

  /// Lecturas en unidades del plano; la última es [to].
  final List<Offset> trail;
  final ({double minX, double minY, double w, double h}) viewBox;
  final double scale;

  /// Radio del robot en unidades del plano (35 cm reales).
  final double radiusPlan;

  _VacuumLivePainter({
    required this.t,
    required this.from,
    required this.to,
    required this.fromAngle,
    required this.toAngle,
    required this.trail,
    required this.viewBox,
    required this.scale,
    required this.radiusPlan,
  }) : super(repaint: t);

  /// Unidades del plano → píxeles del canvas. Misma proyección que los dots de
  /// luces, pero SIN clamp: el clamp mentiría sobre dónde está el robot.
  Offset _screen(Offset p) =>
      Offset((p.dx - viewBox.minX) * scale, (p.dy - viewBox.minY) * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final head = _screen(Offset.lerp(from, to, t.value)!);
    // Piso de 5 px: en un plano de una habitación entera el robot real mide
    // apenas unos píxeles y quedaría invisible.
    final r = math.max(radiusPlan * scale, 5.0);

    // Estela: los tramos ya recorridos, desvaneciéndose hacia el pasado. El
    // último llega hasta donde se está viendo al robot, no hasta la lectura.
    if (trail.length > 1) {
      final pts = [
        for (var i = 0; i < trail.length - 1; i++) _screen(trail[i]),
        head,
      ];
      for (var i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(
          pts[i],
          pts[i + 1],
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = _vacuumTeal.withValues(
                alpha: 0.10 + 0.35 * ((i + 1) / (pts.length - 1))),
        );
      }
    }

    // Robot: halo, disco y aro — el mismo criterio visual que el marcador del
    // mapa en la pantalla del robot, con el teal del plano.
    canvas.drawCircle(
      head,
      r * 1.9,
      Paint()
        ..color = _vacuumTeal.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.2),
    );
    canvas.drawCircle(
        head, r, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawCircle(
      head,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(r * 0.28, 1.2)
        ..color = _vacuumTeal,
    );

    // Tick de orientación (hacia dónde mira), sólo si el robot la reportó.
    final a = fromAngle, b = toAngle;
    final angle = b == null
        ? a
        : (a == null ? b : a + _shortestAngleDelta(a, b) * t.value);
    if (angle != null) {
      final rad = angle * math.pi / 180;
      canvas.drawLine(
        head,
        head + Offset(math.cos(rad), math.sin(rad)) * (r * 1.55),
        Paint()
          ..strokeWidth = math.max(r * 0.3, 1.5)
          ..strokeCap = StrokeCap.round
          ..color = _vacuumTeal,
      );
    }
  }

  @override
  bool shouldRepaint(_VacuumLivePainter old) =>
      old.from != from ||
      old.to != to ||
      old.fromAngle != fromAngle ||
      old.toAngle != toAngle ||
      old.trail.length != trail.length ||
      old.viewBox != viewBox ||
      old.scale != scale ||
      old.radiusPlan != radiusPlan;
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
    } else if (device.isVacuum) {
      // Sin esta rama el robot caía al `else` de abajo y su marcador quedaba
      // SIEMPRE gris, incluso limpiando: no usa `state.on` (Matter lo maneja
      // por el cluster RVC y reporta on:false trabajando).
      active = vacuumWorking(device);
      accent = _vacuumTeal;
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
        // Espeja el marker del dashboard (floor-plan.component): panel vertical
        // TRANSLÚCIDO con BORDE del color de marca + wordmark de marca girado
        // 90° (color de marca encendido, gris apagado) y dot de estado. SIN
        // relleno sólido ni "pantalla" triangular (eso no existe en la web).

        // Proporción ~18×100 de la web, escalada al dotSize del plano.
        final pillW = size * 0.34;
        final pillH = size * 1.40;
        final isTv = shape == _MarkerShape.tv;
        final double border = (size * 0.05).clamp(1.4, 2.6).toDouble();

        // Wordmark de marca girado 90° para correr a lo largo de la píldora
        // vertical (igual que la web). Tamaño por forma: el JBL es ~cuadrado y
        // llena el ancho; el Samsung es un wordmark ancho que corre a lo largo.
        // OverflowBox: el glifo puede exceder el ancho de la píldora sin que las
        // constraints lo achiquen (la tinta visible igual entra en el ancho).
        final double glyphSize = isTv ? pillH * 0.58 : pillW * 1.12;
        final Widget logo = OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: RotatedBox(
            quarterTurns: 1,
            child: CceIcon(
              isTv ? CceIcons.samsung : CceIcons.jbl,
              size: glyphSize,
              color: active ? onColor : _offColor,
              emboss: false,
            ),
          ),
        );

        final pill = Container(
          width: pillW,
          height: pillH,
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            // Relleno casi transparente (tinte de marca tenue al encender); el
            // panel se lee por el BORDE + el wordmark, como en la web.
            color: active
                ? onColor.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(pillW * 0.42),
            border: Border.all(
              color: active ? onColor : _offColor.withValues(alpha: 0.55),
              width: border,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: onColor.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: logo,
        );

        final onlineDot = Container(
          width: size * 0.20,
          height: size * 0.20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? CceColors.ok : _offColor,
            border: Border.all(color: CceColors.surface, width: 1.5),
          ),
        );

        // Píldora + dot online en la esquina superior derecha (como la web).
        final body = Stack(
          clipBehavior: Clip.none,
          children: [
            pill,
            Positioned(
              right: -size * 0.06,
              top: -size * 0.06,
              child: onlineDot,
            ),
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
