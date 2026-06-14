import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cce_tokens.dart';
import 'brightness_slider.dart';
import 'cce_card.dart';
import 'cce_switch.dart';
import 'status_dot.dart';

/// Card de habitacion (sidebar tablet y lista phone), estilo Hue:
/// gradiente pastel del tint real de las luces si hay encendidas (foreground
/// por luminancia del pastel), SOLO el nombre como Hue (sin subtítulo), dots
/// de estado inline a la derecha del título, switch a la derecha y slider de
/// brillo FINO embebido al pie (solo tablet, [brightness] != null).
///
/// Layout congelado (anti-overflow):
///  - compact == true (phone): altura FIJA 76, NUNCA renderiza slider.
///  - compact == false (tablet): 76 sin slider; 104 con slider thin (24).
class RoomCard extends StatefulWidget {
  const RoomCard({
    super.key,
    required this.title,
    required this.icon,
    required this.lightsOn,
    required this.lightsTotal,
    required this.anyOn,
    this.tint,
    this.tintColors = const [],
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
    this.neo = false,
  });

  final String title;
  final Widget icon; // Icon(MdiIcons...) o CceIcon
  final int lightsOn;
  final int lightsTotal;
  final bool anyOn;

  /// Color dominante (fallback del gradiente si [tintColors] viene vacío).
  final Color? tint;

  /// Colores de todas las luces ON: gradiente multicolor estilo Hue. Vacío
  /// ⇒ se usa [tint] como color único.
  final List<Color> tintColors;
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

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ render
  /// idéntico al actual (el sidebar del tablet no lo pasa, queda intacto).
  /// OFF ⇒ extrusión gris [CceShadows.neo]; ON ⇒ solo el glow de color
  /// [CceShadows.glowOn] (no se ensucia el halo). Badge y switch hundidos
  /// vía [CceShadows.neoInset].
  final bool neo;

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

  /// Promedio RGB simple de las paradas del gradiente (para decidir el fg).
  static Color _avgColor(List<Color> colors) {
    if (colors.isEmpty) return CceColors.warm;
    if (colors.length == 1) return colors.first;
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in colors) {
      r += (c.r * 255.0);
      g += (c.g * 255.0);
      b += (c.b * 255.0);
    }
    final n = colors.length;
    return Color.fromARGB(
        255, (r / n).round(), (g / n).round(), (b / n).round());
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
    final height = widget.compact ? 76.0 : (showSlider ? 104.0 : 76.0);

    // Gradiente multicolor estilo Hue: una parada por cada luz ON con color.
    // Con 0/1 colores cae al tint dominante (o ámbar) — comportamiento previo.
    final colors = widget.tintColors.isNotEmpty
        ? widget.tintColors
        : [widget.tint ?? CceColors.warm];

    final gradient = widget.anyOn ? CceGradients.huePastel(colors) : null;
    // Foreground por LUMINANCIA del pastel medio (promedio de las paradas):
    // pasteles oscuros → texto blanco, claros → casi-negro.
    final mid = CceTint.pastel(_avgColor(colors));
    final fg = widget.anyOn ? CceTint.textOn(mid) : CceColors.textPrimary;
    final fgSub =
        widget.anyOn ? CceTint.subTextOn(mid) : CceColors.textSecondary;

    // T3 — Badge/ícono con el color REAL del item (tint). Una sola definición
    // (con guarda hasRealTint) para phone y tablet: "Toda la casa" (sin tint)
    // u otra entrada agregada sin color mantiene el badge neo/genérico aun
    // encendida; solo se tinta cuando hay un color real que destacar.
    final bool hasRealTint =
        widget.tint != null || widget.tintColors.isNotEmpty;
    final Color? badgeTint = (widget.anyOn && hasRealTint)
        ? CceTint.normalize(widget.tintColors.isNotEmpty
            ? _avgColor(widget.tintColors)
            : widget.tint!)
        : null;
    final Color badgeFill = badgeTint != null
        ? badgeTint // ON con color: círculo = color real de la room.
        : (widget.neo ? CceColors.neoSunken : CceColors.surfaceHigh);
    final Color badgeGlyph = badgeTint != null
        ? CceTint.textOn(badgeTint) // contraste garantizado sobre el tint.
        : (widget.neo ? CceColors.neoText : fg);
    // El inset neo está calibrado para fill oscuro (neoSunken); sobre un fill
    // claro tintado proyectaría un halo sucio → se suprime cuando hay tint.
    final List<BoxShadow>? badgeShadow =
        (widget.neo && badgeTint == null) ? CceShadows.neoInset() : null;

    // Subtítulo de estado (como la card del JBL): override > conteo > apagado.
    final lo = widget.lightsOn, lt = widget.lightsTotal;
    final subtitle = widget.subtitleOverride ??
        (lt == 0
            ? 'Sin luces'
            : (widget.anyOn ? '$lo de $lt encendidas' : 'Apagado'));

    final headerRow = Row(
      children: [
        // Ícono en badge circular (como la card del JBL).
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: badgeFill,
            boxShadow: badgeShadow,
          ),
          alignment: Alignment.center,
          child: IconTheme.merge(
            data: IconThemeData(
              color: badgeGlyph,
              size: 22,
            ),
            child: widget.icon,
          ),
        ),
        const SizedBox(width: 14),
        // Nombre + subtítulo de estado (dos líneas).
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
              Row(
                children: [
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
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption.copyWith(color: fgSub),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Switch unificado (CceSwitch): tamaño natural del JBL, sin FittedBox.
        // El título Expanded cede ancho; entra al final del Row sin desbordar.
        CceSwitch(
          value: widget.anyOn,
          onChanged: (!widget.toggleEnabled || widget.lightsTotal == 0)
              ? null
              : widget.onToggle,
        ),
      ],
    );

    final card = CceCard(
      gradient: gradient,
      color: widget.anyOn
          ? null
          : (widget.neo
              ? CceColors.neoBase
              : (widget.selected
                  ? CceColors.surfaceHigh
                  : CceColors.cardOff)),
      radius: CceRadii.hueCard,
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
                    activeColor: Colors.white,
                    thinTrackColor: fg.withValues(alpha: 0.15),
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
              borderRadius: BorderRadius.circular(CceRadii.hueCard),
              boxShadow: widget.anyOn
                  ? CceShadows.glowOn(mid)
                  : (widget.neo ? CceShadows.neo() : const []),
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
                  borderRadius: BorderRadius.circular(CceRadii.hueCard),
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
