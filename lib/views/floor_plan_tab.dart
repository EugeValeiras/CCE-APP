import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../utils/icon_resolver.dart';
import '../widgets/light_detail_sheet.dart';
import '../widgets/pulse_on_update.dart';

class FloorPlanTab extends StatefulWidget {
  final DevicesService service;
  final TileSize tileSize;
  const FloorPlanTab({super.key, required this.service, this.tileSize = TileSize.medium});

  @override
  State<FloorPlanTab> createState() => _FloorPlanTabState();
}

class _FloorPlanTabState extends State<FloorPlanTab> {
  String? _selectedPlanId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final fp = widget.service.floorPlans;
        if (fp == null || fp.plans.isEmpty) {
          if (widget.service.loading) {
            return const Center(child: CircularProgressIndicator(color: Colors.white54));
          }
          return const Center(
            child: Text('No hay planos configurados', style: TextStyle(color: Colors.white54)),
          );
        }

        final activeId = _selectedPlanId ?? fp.activePlanId ?? fp.plans.first.id;
        final plan = fp.plans.firstWhere(
          (p) => p.id == activeId,
          orElse: () => fp.plans.first,
        );
        final positions = fp.positions[plan.id] ?? const <String, LightPosition>{};

        return Column(
          children: [
            if (fp.plans.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: fp.plans
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(p.name),
                                selected: p.id == plan.id,
                                onSelected: (_) => setState(() => _selectedPlanId = p.id),
                                backgroundColor: const Color(0xFF1E2A44),
                                selectedColor: const Color(0xFF0F3460),
                                labelStyle: const TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            Expanded(child: _PlanCanvas(plan: plan, positions: positions, service: widget.service, dotSize: widget.tileSize.floorPlanDotSize)),
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

  const _PlanCanvas({required this.plan, required this.positions, required this.service, required this.dotSize});

  // Parse viewBox from SVG string — default 800x600 for built-in plans.
  ({double w, double h}) _viewBox() {
    final svg = plan.svg;
    final match = RegExp(r'viewBox=["]\s*([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)').firstMatch(svg);
    if (match != null) {
      return (w: double.parse(match.group(3)!), h: double.parse(match.group(4)!));
    }
    return (w: 800, h: 600);
  }

  @override
  Widget build(BuildContext context) {
    final vb = _viewBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - 32;
        final availH = constraints.maxHeight - 32;
        final scale = (availW / vb.w < availH / vb.h) ? availW / vb.w : availH / vb.h;
        final w = vb.w * scale;
        final h = vb.h * scale;

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
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SvgPicture.string(
                          plan.svg,
                          fit: BoxFit.fill,
                          width: w,
                          height: h,
                        ),
                      ),
                    ),
                    ...positions.entries.map((e) {
                      final device = service.byId(e.key);
                      if (device == null) return const SizedBox.shrink();
                      final px = e.value.x * scale;
                      final py = e.value.y * scale;
                      return Positioned(
                        left: px,
                        top: py,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: _DeviceDot(device: device, service: service, size: dotSize),
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

class _DeviceDot extends StatelessWidget {
  final Device device;
  final DevicesService service;
  final double size;

  const _DeviceDot({required this.device, required this.service, required this.size});

  Color _lightColor() {
    final s = device.state;
    if (s.hue != null && s.sat != null && (s.sat ?? 0) > 40) {
      final h = (s.hue! / 65535) * 360.0;
      final sat = (s.sat! / 254).clamp(0.0, 1.0);
      return HSVColor.fromAHSV(1.0, h, sat, 1.0).toColor();
    }
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = device.isLight && !device.isSensorDevice;
    final isContact = device.isContactSensor;
    final isMotion = device.isMotionSensor;
    final temp = device.sensor?.temperature;
    final hum = device.sensor?.humidity;
    final hasReading = temp != null || hum != null;

    Color color;
    if (isLight) {
      color = device.state.on ? _lightColor() : Colors.white38;
    } else if (isContact) {
      color = device.sensor?.contact == true ? const Color(0xFFFF9800) : Colors.white60;
    } else if (isMotion) {
      color = device.sensor?.motion == true ? const Color(0xFF2196F3) : Colors.white60;
    } else if (temp != null) {
      color = _colorForTemp(temp);
    } else if (hum != null) {
      color = const Color(0xFF4FC3F7);
    } else {
      color = Colors.white54;
    }

    final icon = IconResolver.resolve(device, configuredIcon: service.iconFor(device.id), displayName: service.displayName(device));

    final gesture = GestureDetector(
      onTap: isLight
          ? () {
              HapticFeedback.selectionClick();
              service.toggleLight(device);
            }
          : null,
      onLongPress: isLight
          ? () {
              HapticFeedback.mediumImpact();
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => LightDetailSheet(device: device, service: service),
              );
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: _dotOrBadge(icon, color, temp, hum, hasReading),
    );

    return PulseOnUpdate(
      triggerAt: device.lastEventAt,
      color: color,
      borderRadius: hasReading ? size * 0.45 : size / 2,
      child: gesture,
    );
  }

  Widget _dotOrBadge(IconData icon, Color color, double? temp, double? hum, bool hasReading) {
    // Temperature/humidity sensors get a pill-style badge so the value is visible.
    if (hasReading) {
      final label = temp != null ? '${temp.toStringAsFixed(1)}°' : '${hum!.toStringAsFixed(0)}%';
      return Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.18, vertical: size * 0.14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1D38).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(size * 0.45),
          border: Border.all(color: color, width: 2.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1),
          ],
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

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B1D38).withValues(alpha: 0.92),
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }

  static Color _colorForTemp(double t) {
    if (t < 15) return const Color(0xFF42A5F5);
    if (t < 20) return const Color(0xFF66BB6A);
    if (t < 25) return const Color(0xFFFFB74D);
    if (t < 30) return const Color(0xFFFF8A65);
    return const Color(0xFFE53935);
  }
}
