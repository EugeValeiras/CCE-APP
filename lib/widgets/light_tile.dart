import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../utils/icon_resolver.dart';
import 'light_detail_sheet.dart';
import 'pulse_on_update.dart';

/// Philips Hue-inspired light tile.
/// - Tap: toggle on/off
/// - Long-press: open color/brightness detail sheet
/// - Vertical drag: adjust brightness (up = brighter, down = dimmer)
/// - Background fill reflects the actual color the light is set to.
class LightTile extends StatefulWidget {
  final Device device;
  final DevicesService service;
  final TileSize size;

  const LightTile({
    super.key,
    required this.device,
    required this.service,
    this.size = TileSize.medium,
  });

  double get height => size.tileHeight;

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  double? _dragStartBri;
  double _currentBri = 0;
  bool _dragging = false;

  double get _displayBri => _dragging ? _currentBri : widget.device.state.bri.toDouble();

  /// The actual color the light is displaying.
  /// - If in colour mode with hue/sat → HSV to Color
  /// - Else default to warm amber
  Color _activeColor() {
    final s = widget.device.state;
    if (s.hue != null && s.sat != null && (s.sat ?? 0) > 40) {
      final h = (s.hue! / 65535) * 360.0;
      final sat = (s.sat! / 254).clamp(0.0, 1.0);
      return HSVColor.fromAHSV(1.0, h, sat, 1.0).toColor();
    }
    return const Color(0xFFFFB74D); // warm amber default
  }

  void _onVerticalDragStart(DragStartDetails _) {
    _dragStartBri = widget.device.state.on ? widget.device.state.bri.toDouble() : 0;
    _currentBri = _dragStartBri!;
    _dragging = true;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dragStartBri == null) return;
    final delta = -d.delta.dy / widget.height * 254;
    _currentBri = (_currentBri + delta).clamp(0, 254);
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    if (!_dragging) return;
    final target = _currentBri.round();
    _dragging = false;
    _dragStartBri = null;
    widget.service.setBrightness(widget.device, target);
    HapticFeedback.lightImpact();
    setState(() {});
  }

  void _onTap() {
    HapticFeedback.selectionClick();
    widget.service.toggleLight(widget.device);
  }

  void _openDetail() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LightDetailSheet(device: widget.device, service: widget.service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final on = _dragging ? _currentBri > 0 : d.state.on;
    final bri = _displayBri.clamp(0, 254);
    final briPct = bri / 254;
    final reachable = d.state.reachable;
    final color = _activeColor();

    final fillTop = on ? color.withValues(alpha: 0.55) : const Color(0xFF37474F).withValues(alpha: 0.30);
    final fillBottom = on ? color.withValues(alpha: 0.85) : const Color(0xFF263238).withValues(alpha: 0.55);
    final iconData = IconResolver.resolve(d, configuredIcon: widget.service.iconFor(d.id), displayName: widget.service.displayName(d));
    final iconColor = on ? _contrastingOn(color) : Colors.white38;

    return PulseOnUpdate(
      triggerAt: d.lastEventAt,
      color: on ? color : const Color(0xFF4FC3F7),
      borderRadius: 24,
      child: GestureDetector(
      onTap: reachable ? _onTap : null,
      onLongPress: reachable ? _openDetail : null,
      onVerticalDragStart: reachable ? _onVerticalDragStart : null,
      onVerticalDragUpdate: reachable ? _onVerticalDragUpdate : null,
      onVerticalDragEnd: reachable ? _onVerticalDragEnd : null,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A44),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: on ? color.withValues(alpha: 0.65) : Colors.white12,
            width: 1.5,
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Brightness fill from bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
                height: widget.height * briPct * (on ? 1.0 : 0.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [fillTop, fillBottom],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(iconData, color: iconColor, size: widget.size.iconSize),
                      Row(
                        children: [
                          if (!reachable)
                            const Icon(Icons.wifi_off, color: Colors.white24, size: 20)
                          else if (on)
                            Text(
                              '${((bri / 254) * 100).round()}%',
                              style: TextStyle(
                                color: _contrastingOn(color),
                                fontSize: widget.size.stateSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: reachable ? _openDetail : null,
                            behavior: HitTestBehavior.translucent,
                            child: Icon(
                              Icons.more_horiz,
                              color: on ? Colors.white.withValues(alpha: 0.75) : Colors.white38,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    widget.service.displayName(d),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: reachable ? (on ? _contrastingOn(color) : Colors.white) : Colors.white38,
                      fontSize: widget.size.nameSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Returns a readable foreground color for text/icon over the given background color.
  Color _contrastingOn(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.55 ? const Color(0xFF1A1A2E) : Colors.white;
  }
}
