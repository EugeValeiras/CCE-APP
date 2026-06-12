import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/light_card.dart';
import '../utils/icon_resolver.dart';
import '../utils/light_color.dart';
import '../views/light_color_screen.dart';
import 'pulse_on_update.dart';

/// Tile de luz estilo Hue (los gestos viven acá; el render es [LightCard]).
/// - Tap (sobre la card): abre la pantalla de color/temperatura.
/// - Switch (franja inferior): prende/apaga.
/// - Drag vertical: brillo (arriba = más, abajo = menos).
/// - El fill de fondo refleja el color real de la luz.
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

  /// Color real que está mostrando la luz (respeta colormode vía
  /// resolveLightColor). Blancos/CT: champagne plateado como Hue.
  Color _activeColor() {
    final r = resolveLightColor(widget.device.state);
    if (r.isWhite) return widget.device.state.ct != null ? const Color(0xFFE7E2D8) : CceColors.warm;
    return r.color;
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
    // Divisor constante (no la altura del tile): las cards Hue son bajas y
    // dividir por widget.height haria el drag 2x mas sensible.
    final delta = -d.delta.dy / 180.0 * 254;
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

  void _toggle() {
    HapticFeedback.selectionClick();
    widget.service.toggleLight(widget.device);
  }

  void _openColor() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LightColorScreen(
          device: widget.device,
          service: widget.service,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final on = _dragging ? _currentBri > 0 : d.state.on;
    final bri = _displayBri.clamp(0, 254);
    final briPct = (bri / 254).clamp(0.0, 1.0).toDouble();
    final reachable = d.state.reachable;
    final color = _activeColor();

    // El brillo se comunica por el relleno de la card, no como texto %.
    final String? stateLabel;
    if (!reachable) {
      stateLabel = 'Sin conexión';
    } else if (on) {
      stateLabel = null;
    } else {
      stateLabel = 'Apagada';
    }

    return PulseOnUpdate(
      triggerAt: d.lastEventAt,
      color: on ? color : CceColors.info,
      borderRadius: CceRadii.hueCard,
      child: GestureDetector(
        // Tap en la card abre la pantalla de color (también offline, como Hue).
        onTap: _openColor,
        onVerticalDragStart: reachable ? _onVerticalDragStart : null,
        onVerticalDragUpdate: reachable ? _onVerticalDragUpdate : null,
        onVerticalDragEnd: reachable ? _onVerticalDragEnd : null,
        child: LightCard(
          name: widget.service.displayName(d),
          iconBuilder: (c) => IconResolver.widget(
            d,
            configuredIcon: widget.service.iconFor(d.id),
            customIcons: widget.service.customIcons,
            displayName: widget.service.displayName(d),
            size: widget.size.iconSize,
            color: c,
          ),
          on: on,
          brightness: briPct,
          color: color,
          reachable: reachable,
          stateLabel: stateLabel,
          height: widget.height,
          // El switch de la franja prende/apaga directo.
          onToggle: reachable ? (_) => _toggle() : null,
        ),
      ),
    );
  }
}
