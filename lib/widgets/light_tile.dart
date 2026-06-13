import 'dart:math' as math;

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
/// - Long-press + drag: brillo (overlay expandido estilo Hue; arriba = más,
///   abajo = menos). El commit (setBrightness) ocurre UNA vez al soltar.
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
    this.neo = false,
  });

  /// OPT-IN: relieve neumórfico de la card (default false).
  final bool neo;

  double get height => size.tileHeight;

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  /// Ancla del rect del tile (sobre el [LightCard] real, no el PulseOnUpdate).
  final GlobalKey _cardKey = GlobalKey();

  /// null ⇔ no hay overlay activo. Invariante: _entry != null ⇔ insertado.
  /// El OverlayEntry recuerda su propio owner: remove() lo despega de ese mismo
  /// overlay aunque el context del tile ya no resuelva al mismo ancestro.
  OverlayEntry? _entry;

  /// Brillo en vivo durante el gesto (0..254). Fuente de verdad SOLO mientras
  /// dura el long-press; el árbol de la lista NO se reconstruye en el drag.
  final ValueNotifier<double> _liveBri = ValueNotifier<double>(0);

  // Rect global del área de mapeo (card expandida) capturado en Start.
  double _gestureTop = 0; // top global (px)
  double _gestureHeight = 1; // alto (px, >0 para no /0)

  /// Offset de anclaje dedo↔brillo capturado en el PRIMER move. Evita el salto
  /// del mapeo absoluto puro: el primer contacto se ancla al brillo actual y a
  /// partir de ahí el fill sigue el dedo 1:1. null hasta el primer move.
  double? _grabOffset;

  /// Color real que está mostrando la luz (respeta colormode vía
  /// resolveLightColor). Para CT usa el blanco cálido/frío REAL (ámbar para
  /// 2700K) en vez de un gris fijo — así la card no termina casi blanca.
  Color _activeColor() => resolveLightColor(widget.device.state).color;

  // ── Gesto: entrada ───────────────────────────────────────────────────────
  void _onLongPressStart(LongPressStartDetails det) {
    if (_entry != null) return; // guard anti doble-insert
    final ctx = _cardKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final Offset topLeft = box.localToGlobal(Offset.zero);
    final Size tile = box.size;

    // Card expandida: ~2.5x el alto del tile, MISMO ancho, anclada al top del
    // tile, creciendo hacia abajo. Clamp al alto de pantalla menos un margen.
    const double kExpandFactor = 2.5;
    final media = MediaQuery.of(ctx);
    final double topMargin = media.padding.top + 8;
    const double bottomMargin = 24;
    final double rawH = tile.height * kExpandFactor;
    // Alto disponible entre márgenes; piso = alto del tile (nunca colapsa a 1px
    // aunque el tile esté pegado al borde inferior).
    final double maxH =
        math.max(tile.height, media.size.height - topMargin - bottomMargin);
    final double expandedH = math.min(rawH, maxH);

    // Anclamos al top del tile, pero si no entra hacia abajo lo subimos para que
    // la card expandida quepa entera (evita el caso degenerado al fondo).
    double anchorTop = topLeft.dy;
    if (anchorTop + expandedH > media.size.height - bottomMargin) {
      anchorTop = media.size.height - bottomMargin - expandedH;
    }
    if (anchorTop < topMargin) anchorTop = topMargin;

    _gestureTop = anchorTop;
    _gestureHeight = expandedH;
    _grabOffset = null; // se fija en el primer move (anti-salto)

    final double startBri = widget.device.state.on
        ? widget.device.state.bri.toDouble()
        : 0.0;
    _liveBri.value = startBri.clamp(0, 254).toDouble();

    HapticFeedback.mediumImpact(); // confirmación de entrada a modo dim

    // Ícono construido UNA sola vez: es estático durante el gesto. Así el
    // ValueListenableBuilder del overlay NO reconstruye el SVG en cada frame.
    final Widget Function(Color) iconBuilder = _iconBuilder();
    final String name = widget.service.displayName(widget.device);
    final Color color = _activeColor();

    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => _DimOverlay(
        left: topLeft.dx,
        top: anchorTop,
        width: tile.width,
        height: expandedH,
        liveBri: _liveBri,
        name: name,
        color: color,
        reachable: widget.device.state.reachable,
        iconBuilder: iconBuilder,
      ),
    );
    overlay.insert(_entry!);
  }

  Widget Function(Color) _iconBuilder() {
    final d = widget.device;
    return (Color c) => IconResolver.widget(
          d,
          configuredIcon: widget.service.iconFor(d.id),
          customIcons: widget.service.customIcons,
          displayName: widget.service.displayName(d),
          size: widget.size.iconSize,
          color: c,
        );
  }

  // ── Gesto: movimiento (mapeo ABSOLUTO anclado) ───────────────────────────
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails det) {
    if (_entry == null) return;
    final double y = det.globalPosition.dy;
    // Posición Y → fracción [0..1]: top = 100%, top+height = 0%.
    final double rawFrac = 1.0 - ((y - _gestureTop) / _gestureHeight);

    // Anclaje (anti-salto): en el primer move alineamos el brillo actual con la
    // posición del dedo capturando un offset constante. Después el fill sigue
    // el dedo 1:1 partiendo del brillo real, sin salto instantáneo.
    if (_grabOffset == null) {
      final double startFrac = (_liveBri.value / 254.0).clamp(0.0, 1.0);
      _grabOffset = startFrac - rawFrac;
    }
    final double frac = (rawFrac + _grabOffset!).clamp(0.0, 1.0);
    final double bri = (frac * 254.0).clamp(0.0, 254.0);

    // Haptic tick al cruzar los extremos (con histéresis implícita: solo
    // dispara en la transición, no frame a frame estando pegado al tope/piso).
    final double prev = _liveBri.value;
    final bool hitTop = prev < 254 && bri >= 254;
    final bool hitBottom = prev > 0 && bri <= 0;
    if (hitTop || hitBottom) {
      HapticFeedback.selectionClick();
    }

    _liveBri.value = bri; // notifica SOLO al overlay, NO reconstruye la lista
  }

  // ── Gesto: salida ────────────────────────────────────────────────────────
  /// Idempotente. Anula _entry ANTES de remove() para que un dispose reentrante
  /// no reintente sobre un entry roto si remove() llegara a tirar.
  void _removeOverlay() {
    final OverlayEntry? e = _entry;
    _entry = null;
    _grabOffset = null;
    e?.remove();
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (_entry == null) return; // ya limpiado / nunca entró a modo
    final int target = _liveBri.value.round();
    _removeOverlay();
    HapticFeedback.lightImpact(); // salida suave
    widget.service.setBrightness(widget.device, target); // UNA sola llamada
  }

  void _onLongPressCancel() {
    // Cancel NO commitea (gesto abortado); solo limpia.
    _removeOverlay();
  }

  // ── Acciones existentes (sin cambios) ────────────────────────────────────
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
  void dispose() {
    _removeOverlay(); // garantía anti-leak si se desmonta a media gesto
    _liveBri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final on = d.state.on;
    final bri = d.state.bri.toDouble().clamp(0, 254);
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
        onLongPressStart: reachable ? _onLongPressStart : null,
        onLongPressMoveUpdate: reachable ? _onLongPressMoveUpdate : null,
        onLongPressEnd: reachable ? _onLongPressEnd : null,
        onLongPressCancel: reachable ? _onLongPressCancel : null,
        child: LightCard(
          key: _cardKey,
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
          neo: widget.neo,
          // El switch de la franja prende/apaga directo.
          onToggle: reachable ? (_) => _toggle() : null,
        ),
      ),
    );
  }
}

/// Overlay del modo dim (press-and-hold). NO interactivo: el gesto lo maneja el
/// GestureDetector del tile original (por eso IgnorePointer en todo el árbol).
/// NO reusa LightCard a propósito: con onToggle:null el Switch.adaptive se
/// renderiza igual (deshabilitado pero visible) → switch fantasma en el medio.
/// Acá se pinta el fill directamente (lightFull + capa de vaciado lightFill).
class _DimOverlay extends StatelessWidget {
  const _DimOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.liveBri,
    required this.name,
    required this.color,
    required this.reachable,
    required this.iconBuilder,
  });

  final double left, top, width, height;
  final ValueNotifier<double> liveBri;
  final String name;
  final Color color;
  final bool reachable;
  final Widget Function(Color) iconBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // (a) Barrera tenue: atenúa el fondo, NO captura punteros. Vive DENTRO
        // del overlay para limpiarse atómicamente con un solo remove().
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: CceColors.hueDim),
          ),
        ),
        // (b) Card expandida anclada al rect del tile, con badge % arriba.
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: liveBri,
              builder: (_, bri, __) {
                final double pct = (bri / 254).clamp(0.0, 1.0).toDouble();
                final bool on = bri > 0;
                final int pctInt = (pct * 100).round();
                final Color fgBase = on
                    ? CceGradients.lightFullSampleColor(color, pct, reachable)
                    : CceColors.cardOff;
                final Color fg = on ? CceTint.textOn(fgBase) : CceColors.textPrimary;

                return Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: CceColors.cardOff,
                    borderRadius: BorderRadius.circular(CceRadii.hueCard),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Fill base estilo Hue (color modulado por brillo).
                      if (on)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient:
                                  CceGradients.lightFull(color, pct, reachable),
                            ),
                          ),
                        ),
                      // Capa de "vaciado" vertical que sigue el dedo: lleno
                      // abajo hasta pct de la altura, transparente arriba.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: CceGradients.lightFill(color, pct),
                          ),
                        ),
                      ),
                      // Ícono + nombre centrados.
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconBuilder(fg),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                  height: 1.15,
                                  color: fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge % arriba (pill negro semitransparente, siempre
                      // legible sobre cualquier fill).
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$pctInt%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
