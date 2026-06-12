import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_tokens.dart';
import 'brightness_slider.dart';
import 'cce_card.dart';
import 'status_dot.dart';

/// Card de habitacion (sidebar tablet y lista phone), estilo Hue:
/// gradiente ámbar uniforme si hay luces encendidas (texto oscuro), dots de
/// estado integrados al subtítulo, switch a la derecha y slider de brillo
/// FINO embebido al pie (solo tablet, cuando [brightness] != null).
///
/// Layout congelado (anti-overflow):
///  - compact == true (phone): altura FIJA 84, NUNCA renderiza slider.
///  - compact == false (tablet): 84 sin slider; 110 con slider thin (24).
class RoomCard extends StatefulWidget {
  const RoomCard({
    super.key,
    required this.title,
    required this.icon,
    required this.lightsOn,
    required this.lightsTotal,
    required this.anyOn,
    this.tint,
    this.brightness,
    this.selected = false,
    this.compact = false,
    this.motion = false,
    this.contactOpen = false,
    this.subtitleOverride,
    this.toggleEnabled = true,
    required this.onTap,
    required this.onToggle,
    this.onBrightnessCommitted,
  });

  final String title;
  final Widget icon; // Icon(MdiIcons...) o CceIcon
  final int lightsOn;
  final int lightsTotal;
  final bool anyOn;

  /// Aceptado por compatibilidad; la card ya NO se tiñe con el color de
  /// las luces (ámbar uniforme estilo Hue).
  final Color? tint;
  final double? brightness; // 0..1; null = sin slider
  final bool selected; // resaltado en sidebar tablet
  final bool compact; // phone vs tablet

  /// true → StatusDot(CceColors.motion, pulse: true).
  final bool motion;

  /// true → StatusDot(CceColors.contact, pulse: true).
  final bool contactOpen;

  /// "Toda la casa": "12/31 · 2 con movimiento".
  final String? subtitleOverride;

  /// false ⇒ Switch deshabilitado (onChanged: null); onTap sigue vivo.
  final bool toggleEnabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle; // switch a la derecha
  final ValueChanged<double>? onBrightnessCommitted; // commit al soltar, 0..1

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  // Drag local del slider: mientras se arrastra (y 800 ms después de
  // soltar) se muestra _dragValue en lugar de widget.brightness, para que
  // el refresh del service no "pelee" con el dedo.
  double? _dragValue;
  Timer? _retainTimer;

  @override
  void dispose() {
    _retainTimer?.cancel();
    super.dispose();
  }

  String get _subtitle {
    final override = widget.subtitleOverride;
    if (override != null) return override;
    if (widget.contactOpen) {
      return 'Puerta abierta · ${widget.lightsOn}/${widget.lightsTotal}';
    }
    if (widget.lightsOn > 0) {
      return '${widget.lightsOn}/${widget.lightsTotal} encendidas';
    }
    if (widget.lightsTotal == 0) return 'Sin luces';
    return '${widget.lightsTotal} luces';
  }

  void _onSliderChanged(double v) {
    _retainTimer?.cancel();
    _retainTimer = null;
    setState(() => _dragValue = v);
  }

  void _onSliderEnd(double v) {
    setState(() => _dragValue = v);
    widget.onBrightnessCommitted?.call(v);
    _retainTimer?.cancel();
    _retainTimer = Timer(const Duration(milliseconds: 800), () {
      _retainTimer = null;
      if (mounted) setState(() => _dragValue = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSlider = !widget.compact && widget.brightness != null;
    final height = widget.compact ? 84.0 : (showSlider ? 110.0 : 84.0);

    final gradient = widget.anyOn
        ? CceGradients.roomOn()
        : (widget.selected ? null : CceGradients.roomOff);
    final glowColor =
        widget.anyOn ? CceColors.amberLo : Colors.transparent;
    final fg =
        widget.anyOn ? CceColors.inkOnAmber : CceColors.textPrimary;
    final fgSub = widget.anyOn
        ? CceColors.inkOnAmber.withValues(alpha: 0.65)
        : CceColors.textSecondary;

    final subtitleRow = Row(
      children: [
        // Dots primero (28 px máx fijos): fin del "7 l…".
        if (widget.contactOpen) ...[
          const StatusDot(
            CceColors.contact,
            pulse: true,
            semanticLabel: 'Puerta abierta',
          ),
          const SizedBox(width: 6),
        ],
        if (widget.motion) ...[
          const StatusDot(
            CceColors.motion,
            pulse: true,
            semanticLabel: 'Movimiento',
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            _subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CceText.caption.copyWith(color: fgSub),
          ),
        ),
      ],
    );

    final headerRow = Row(
      children: [
        // Ícono plano, sin contenedor circular (look Hue).
        SizedBox(
          width: 30,
          child: IconTheme.merge(
            data: IconThemeData(color: fg, size: 24),
            child: widget.icon,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              subtitleRow,
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          height: 36,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch.adaptive(
              value: widget.anyOn,
              onChanged: (!widget.toggleEnabled || widget.lightsTotal == 0)
                  ? null
                  : widget.onToggle,
              activeTrackColor: widget.anyOn
                  ? CceColors.inkOnAmber.withValues(alpha: 0.30)
                  : null,
              thumbColor:
                  const WidgetStatePropertyAll<Color>(Colors.white),
            ),
          ),
        ),
      ],
    );

    final card = CceCard(
      gradient: gradient,
      color:
          widget.selected && !widget.anyOn ? CceColors.surfaceHigh : null,
      padding: EdgeInsets.fromLTRB(16, showSlider ? 10 : 8, 14, 8),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: showSlider
          ? Column(
              children: [
                Expanded(child: headerRow),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CceBrightnessSlider(
                    height: 24,
                    thin: true,
                    showPercent: false,
                    value: (_dragValue ?? widget.brightness!)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    activeColor: Colors.white.withValues(alpha: 0.85),
                    thinTrackColor: widget.anyOn
                        ? CceColors.inkOnAmber.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.22),
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderEnd,
                  ),
                ),
              ],
            )
          : Center(child: headerRow),
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Glow al encender / fade al apagar (300 ms easeOutCubic).
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CceRadii.card),
              boxShadow:
                  widget.anyOn ? CceShadows.glowOn(glowColor) : const [],
            ),
            child: card,
          ),
          // Selección: hairline blanco sutil (el accent violeta chocaba
          // contra el ámbar).
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CceRadii.card),
                  border: Border.all(
                    color: widget.selected
                        ? Colors.white.withValues(alpha: 0.80)
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
