import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_press.dart';
import '../widgets/temp_sparkline.dart';

/// Pantalla de control de un termostato (Tuya cat 'wk'). Réplica EXACTA del
/// rediseño neumórfico del dashboard (thermostat-sidebar):
///
///  - HEADER fuera del control (a nivel del drawer): [badge redondo convexo ·
///    título + dot de estado · cerrar redondo].
///  - CARCASA neoBase radius 40 con sombra externa exagerada, SOBRE un fondo de
///    drawer más oscuro (#16181D) para que flote.
///  - Power redondo 52px arriba-izquierda DEL CONTROL.
///  - Fila [−] dial [+] (steppers flanqueando el dial, como el volumen del JBL).
///  - DIAL = PLATO cóncavo con ARCO de setpoint (gradiente naranja, fracción del
///    rango). Dentro solo el número OBJETIVO + rótulo "Objetivo".
///  - READOUT en cápsula HUNDIDA: temp ACTUAL destacada (🌡 + número + "actual")
///    a la izq, rango (min–max°) a la der.
///  - Actividad del relé (CCE#101): «Calentando» con la llama cuando
///    `state.heating` (DP102), «En temperatura» prendido sin calentar,
///    «Apagado»; y «Falla del termostato (código N)» si `fault` ≠ 0.
///  - Modo Manual / Program = chips convexos sin borde (activo = color de marca
///    + glow, sin borde ni inset).
///
/// Toda la funcionalidad (setpoint, power, modo, optimistic) se conserva via
/// [DevicesService]. Todos los íconos salen de icons0.dev ([CceIcons]).
class ThermostatScreen extends StatelessWidget {
  final Device device;
  final DevicesService service;
  const ThermostatScreen({
    super.key,
    required this.device,
    required this.service,
  });

  /// Fondo de la app (#101014), MÁS oscuro que la carcasa (neoBase) para que el
  /// control FLOTE con claridad (igual que la home; #16181D quedaba casi igual
  /// a neoBase en el OLED).
  static const Color _drawerBg = CceColors.bg;

  /// Formatea temperaturas: 0.5 con decimal, enteros sin decimal.
  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);

  static String _normalizeMode(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('program') || m.contains('auto')) return 'Program';
    return 'Manual';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _drawerBg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final d = service.byId(device.id) ?? device;
            final s = d.state;

            // SIN header (se vuelve con el swipe iOS). El control es COMPACTO
            // (alto natural de su contenido, como el dashboard — ya no se
            // estira al alto de la pantalla). FittedBox(contain) lo centra y, si
            // la pantalla es más baja que el control, lo achica para no desbordar.
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 360,
                    child: _panel(child: _buildControl(context, d, s)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// CARCASA del control (réplica exacta del `.panel` del dashboard): radius 40,
  /// fondo neoBase PLANO, sombra EXTERNA exagerada — 10/10/28 negra abajo-der +
  /// -6/-6/20 luz arriba-izq — y padding 22. Los materiales internos (dial
  /// cóncavo, chips convexos, wells) aportan el relieve; la carcasa los sostiene.
  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          // Sombra externa abajo-derecha (exagerada): 10/10/28 negra.
          BoxShadow(
            color: Color(0x73000000), // rgba(0,0,0,0.45)
            blurRadius: 28,
            offset: Offset(10, 10),
          ),
          // Luz externa arriba-izquierda: -6/-6/20.
          BoxShadow(
            color: Color(0x402A2D37), // rgba(42,45,55,0.25)
            blurRadius: 20,
            offset: Offset(-6, -6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildControl(BuildContext context, Device d, DeviceState s) {
    final on = s.on;
    final reachable = s.reachable;
    final target = s.targetTemp;
    final current = s.currentTemp;
    final minT = s.minTemp ?? 5;
    final maxT = s.maxTemp ?? 45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Contenido COMPACTO (alto natural, como el dashboard): gaps fijos en vez
      // de spaceBetween, así no se estira ni queda aire de más arriba.
      mainAxisSize: MainAxisSize.min,
      children: [
        // Power redondo 52px arriba-IZQUIERDA del control.
        _PowerButton(
          on: on,
          onTap: reachable
              ? () {
                  HapticFeedback.selectionClick();
                  service.setThermostatPower(d, !on);
                }
              : null,
        ),

        // Dial pegado al power (poco aire arriba, como el dashboard).
        const SizedBox(height: 6),

        // Control de temperatura: [−] dial [+] (deshabilitado/atenuado si off).
        Opacity(
          opacity: on ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !on,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Stepper(
                      svg: CceIcons.minus,
                      tooltip: 'Bajar 0.5°C',
                      onTap: (reachable && on && target != null && target > minT)
                          ? () {
                              HapticFeedback.selectionClick();
                              service.setTargetTemp(d, target - 0.5);
                            }
                          : null,
                    ),
                    Expanded(
                      child: Center(
                        child: _Dial(
                          targetLabel:
                              target != null ? '${_fmt(target)}°' : '—',
                          fraction: (target != null && maxT > minT)
                              ? ((target - minT) / (maxT - minT))
                                  .clamp(0.0, 1.0)
                                  .toDouble()
                              : 0.0,
                        ),
                      ),
                    ),
                    _Stepper(
                      svg: CceIcons.plus,
                      tooltip: 'Subir 0.5°C',
                      onTap: (reachable && on && target != null && target < maxT)
                          ? () {
                              HapticFeedback.selectionClick();
                              service.setTargetTemp(d, target + 0.5);
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // READOUT: cápsula hundida con la temp ACTUAL centrada.
                _Readout(
                  current: current != null ? '${_fmt(current)}°' : '—',
                ),
              ],
            ),
          ),
        ),

        // Actividad del relé (CCE#101): qué está HACIENDO, no el modo. Fuera
        // del bloque atenuado: «Apagado» se lee a pleno.
        const SizedBox(height: 14),
        Center(
          child: _ActivityChip(
            on: on,
            heating: on && s.heating == true,
          ),
        ),
        if (s.fault != null && s.fault != 0) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Falla del termostato (código ${s.fault})',
              style: CceText.caption.copyWith(
                color: CceColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        // Sparkline del historial de temperatura ambiente (últimos 7 días).
        // El widget maneja su propio espaciado (sin gap colgado si no hay datos).
        if (d.bindingIds.isNotEmpty)
          TempSparkline(
            config: service.config,
            globalId: d.bindingIds.first,
            // Termostato: la temp ambiente viaja en payload.state.currentTemp.
            reader: (p) {
              final state = p['state'];
              final v = (state is Map) ? state['currentTemp'] : null;
              return v is num ? v.toDouble() : null;
            },
          ),

        // Modo (Manual / Program) = chips convexos sin borde.
        if (s.tempMode != null) ...[
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SectionLabel('MODO'),
              const SizedBox(height: 10),
              _ModeChips(
                value: _normalizeMode(s.tempMode!),
                onChanged: reachable
                    ? (m) {
                        HapticFeedback.selectionClick();
                        service.setTempMode(d, m);
                      }
                    : null,
              ),
            ],
          ),
        ],

        // Wordmark grabado al pie.
        const SizedBox(height: 18),
        const _Wordmark('CCE THERMOSTAT'),
      ],
    );
  }
}

// ── Helpers de sombras (recetas del dashboard) ──────────────────────────────

/// Sombra externa ESTÁNDAR de los controles convexos del dashboard
/// (3/3/8 negra abajo-der + -3/-3/8 luz arriba-izq).
List<BoxShadow> _convexShadow() => const [
      BoxShadow(
        color: Color(0xB30C0D11), // rgba(12,13,17,0.70)
        blurRadius: 8,
        offset: Offset(3, 3),
      ),
      BoxShadow(
        color: Color(0x8C2A2D37), // rgba(42,45,55,0.55)
        blurRadius: 8,
        offset: Offset(-3, -3),
      ),
    ];

/// Sombra INSET de un control convexo presionado (réplica del `:active`).
List<BoxShadow> _convexInset() => const [
      BoxShadow(
        color: Color(0xD90C0D11), // rgba(12,13,17,0.85)
        blurRadius: 6,
        offset: Offset(2, 2),
        blurStyle: BlurStyle.inner,
      ),
      BoxShadow(
        color: Color(0x732A2D37), // rgba(42,45,55,0.45)
        blurRadius: 6,
        offset: Offset(-2, -2),
        blurStyle: BlurStyle.inner,
      ),
    ];

/// Shadows "encendidas" para un label activo: halo del [color] (glow suave).
List<Shadow> _glowTextShadows(Color color) => [
      Shadow(color: color.withValues(alpha: 0.55), blurRadius: 12),
      Shadow(color: color.withValues(alpha: 0.35), blurRadius: 4),
    ];

// ── Botones redondos ────────────────────────────────────────────────────────

/// Botón redondo base del dashboard: base neoBase PLANA + sombra externa
/// estándar → al presionar se hunde (inset) con escala. Réplica del
/// `.neo-btn.round`.
class _RoundNeoButton extends StatelessWidget {
  const _RoundNeoButton({
    required this.svg,
    required this.onTap,
    this.size = 52,
    this.iconSize = 22,
    this.color,
    this.glow = false,
    this.tooltip,
  });

  final String svg;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;
  final bool glow;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconColor = color ?? CceColors.neoTextSub;
    final raised = _convexShadow();
    final inset = _convexInset();

    Widget icon = CceIcon(svg, size: iconSize, emboss: false, color: iconColor);
    if (glow) {
      icon = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.6),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        child: icon,
      );
    }

    final button = CceNeoPress(
      onTap: onTap,
      builder: (ctx, t) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase,
          boxShadow: enabled
              ? [
                  for (var i = 0; i < raised.length; i++)
                    BoxShadow.lerp(raised[i], inset[i], t)!,
                ]
              : const [],
        ),
        child: enabled ? icon : Opacity(opacity: 0.45, child: icon),
      ),
    );

    if (tooltip != null) return Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Botón de POWER redondo 52px, alineado arriba-IZQUIERDA del control. Apagado =
/// neoTextSub; encendido = info con glow. Réplica del `.neo-btn.round.power`.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _RoundNeoButton(
        svg: CceIcons.power,
        size: 52,
        iconSize: 22,
        color: on ? CceColors.info : CceColors.neoTextSub,
        glow: on,
        tooltip: on ? 'Apagar' : 'Encender',
        onTap: onTap,
      ),
    );
  }
}

/// Stepper +/- (56px) que flanquea el dial: superficie CONVEXA (gradiente convexo
/// claro→oscuro + sombra externa) → al presionar pasa a INSET. Réplica del
/// `.neo-btn.step` del dashboard. flex-shrink:0 implícito (tamaño fijo).
class _Stepper extends StatelessWidget {
  const _Stepper({required this.svg, required this.onTap, this.tooltip});

  final String svg;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final raised = _convexShadow();
    final inset = _convexInset();

    final button = CceNeoPress(
      onTap: onTap,
      builder: (ctx, t) {
        final box = Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CceColors.neoBase,
            gradient: CceGradients.convex(CceColors.neoBase),
            boxShadow: enabled
                ? [
                    for (var i = 0; i < raised.length; i++)
                      BoxShadow.lerp(raised[i], inset[i], t)!,
                  ]
                : const [],
          ),
          child: CceIcon(svg, size: 24, emboss: false, color: CceColors.neoText),
        );
        return enabled ? box : Opacity(opacity: 0.45, child: box);
      },
    );

    if (tooltip != null) return Tooltip(message: tooltip!, child: button);
    return button;
  }
}

// ── DIAL (plato cóncavo con arco de setpoint) ───────────────────────────────

// Arco de setpoint: arranca 135° (abajo-izquierda) y barre 270° (gap abajo),
// igual que el dashboard (`rotate(135)` + dasharray 188.5/62.83 sobre r=40).
const double _kArcStart = 135 * math.pi / 180;
const double _kArcSweep = 270 * math.pi / 180;

/// DIAL = PLATO cóncavo (sobresale pero hunde la cara): gradiente cóncavo +
/// sombras de plato (relieve externo + inset suave). Encima, un arco de setpoint
/// (track hundido + valor con gradiente naranja). Dentro: número OBJETIVO grande
/// + rótulo "Objetivo". Réplica del `.dial` del dashboard.
class _Dial extends StatelessWidget {
  const _Dial({required this.targetLabel, required this.fraction});

  final String targetLabel;
  final double fraction; // 0..1 del rango [min,max]

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dim = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(132.0, 168.0).toDouble()
            : 150.0;
        return SizedBox(
          width: dim,
          height: dim,
          child: RepaintBoundary(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Plato cóncavo (sobresale + hunde la cara).
                Container(
                  width: dim,
                  height: dim,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CceColors.neoBase,
                    gradient: CceGradients.concave(CceColors.neoBase),
                    boxShadow: CceShadows.plato(blur: 15, offset: 6),
                  ),
                ),
                // Arco de setpoint (track hundido + valor naranja).
                CustomPaint(
                  size: Size(dim, dim),
                  painter: _SetpointArcPainter(fraction: fraction),
                ),
                // Centro: número OBJETIVO grande + rótulo "Objetivo".
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      targetLabel,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        height: 1,
                        color: CceColors.neoText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'OBJETIVO',
                      style: CceText.caption.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: CceColors.neoTextSub,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pinta el arco del setpoint sobre el plato: TRACK como canal hundido
/// (neoSunken + sombra/highlight desplazados) + arco de valor con gradiente
/// naranja (FF7A00→FFB36A) y glow. Geometría: start 135°, sweep 270°.
class _SetpointArcPainter extends CustomPainter {
  _SetpointArcPainter({required this.fraction});

  final double fraction; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // (1) TRACK como canal hundido: base neoSunken + sombra sup-izq + highlight
    // inf-der desplazados (lee como hundido sin clips frágiles).
    final trackBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoSunken;
    canvas.drawArc(rect, _kArcStart, _kArcSweep, false, trackBase);

    final trackShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.62
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoDark.withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawArc(
      rect.shift(const Offset(1, 1)),
      _kArcStart,
      _kArcSweep,
      false,
      trackShadow,
    );

    final trackHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.45
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoLight.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawArc(
      rect.shift(const Offset(-1, -1)),
      _kArcStart,
      _kArcSweep,
      false,
      trackHighlight,
    );

    final value = fraction.clamp(0.0, 1.0);
    if (value <= 0) return;
    final sweep = _kArcSweep * value;

    // (2) GLOW del arco de valor.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF7A00).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawArc(rect, _kArcStart, sweep, false, glow);

    // (3) ARCO de valor (gradiente naranja FF7A00 → FFB36A).
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: _kArcStart,
        endAngle: _kArcStart + _kArcSweep,
        colors: [Color(0xFFFF7A00), Color(0xFFFFB36A)],
      ).createShader(rect);
    canvas.drawArc(rect, _kArcStart, sweep, false, progress);
  }

  @override
  bool shouldRepaint(_SetpointArcPainter old) => old.fraction != fraction;
}

// ── READOUT (cápsula hundida: temp actual + rango) ──────────────────────────

/// Cápsula HUNDIDA con la temperatura ACTUAL centrada y protagonista (🌡 +
/// número + "actual"). Réplica del `.th-readout` del dashboard (sin el rango).
class _Readout extends StatelessWidget {
  const _Readout({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(14),
        boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Temp actual destacada, centrada.
          CceIcon(
            CceIcons.thermometer,
            size: 16,
            emboss: false,
            color: const Color(0xFFFF9F6A),
          ),
          const SizedBox(width: 8),
          Text(
            current,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CceColors.neoText,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'actual',
            style: CceText.caption.copyWith(
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: CceColors.neoTextSub,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actividad del relé (CCE#101): Calentando / En temperatura / Apagado ─────

/// Píldora convexa con la actividad del termostato. Calentando = llama en el
/// cálido de marca con glow; en temperatura = tilde en ok; apagado = power
/// atenuado. Réplica de la `.th-activity` del dashboard.
class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.on, required this.heating});

  final bool on;
  final bool heating;

  /// «Calentando» / «En temperatura» / «Apagado» (también para los tests).
  static String labelFor({required bool on, required bool heating}) {
    if (!on) return 'Apagado';
    return heating ? 'Calentando' : 'En temperatura';
  }

  @override
  Widget build(BuildContext context) {
    final label = labelFor(on: on, heating: heating);
    final Color color = !on
        ? CceColors.neoTextSub
        : (heating ? CceColors.warm : CceColors.ok);
    final String svg =
        !on ? CceIcons.power : (heating ? CceIcons.flame : CceIcons.check);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22252E), Color(0xFF16181D)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: _convexShadow(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(svg, size: 16, color: color, emboss: false),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              shadows: heating ? _glowTextShadows(color) : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Modo (Manual / Program) = chips convexos ────────────────────────────────

/// Chips de modo convexos sin borde: activo = color de marca (info) + glow, sin
/// borde ni inset. Réplica del `.chips` + `.chip.active` del dashboard.
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  static const _items = [
    (value: 'Manual', label: 'Manual', icon: CceIcons.handTap),
    (value: 'Program', label: 'Programa', icon: CceIcons.calendar),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          Expanded(
            child: _ModeChip(
              svg: _items[i].icon,
              label: _items[i].label,
              active: value == _items[i].value,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(_items[i].value),
            ),
          ),
          if (i != _items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

/// Chip de modo individual: superficie CONVEXA (sobresale) → INSET al presionar.
/// ACTIVO = ícono + label info con glow (sin borde ni inset). Réplica `.chip`.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.svg,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String svg;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final raised = _convexShadow();
    final inset = _convexInset();
    final accent = CceColors.info;

    Widget icon = CceIcon(
      svg,
      size: 20,
      emboss: false,
      color: active ? accent : CceColors.neoText,
    );
    if (active) {
      icon = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.55),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        child: icon,
      );
    }

    final chip = CceNeoPress(
      onTap: onTap,
      builder: (ctx, t) {
        final box = Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            gradient: CceGradients.convex(CceColors.neoBase),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    for (var i = 0; i < raised.length; i++)
                      BoxShadow.lerp(raised[i], inset[i], t)!,
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CceText.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? accent : CceColors.neoTextSub,
                  shadows: active ? _glowTextShadows(accent) : null,
                ),
              ),
            ],
          ),
        );
        return enabled ? box : Opacity(opacity: 0.45, child: box);
      },
    );
    return chip;
  }
}

// ── Section label + wordmark ────────────────────────────────────────────────

/// Encabezado de sección chico (MODO). Réplica del `.section-cap`.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Text(
        text.toUpperCase(),
        style: CceText.caption.copyWith(
          color: CceColors.neoTextSub,
          fontSize: 12,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Wordmark grabado al pie del control. Réplica del `.wordmark`: tracking ancho,
/// tinte terciario, con relieve "goma" (canto de luz arriba-izq + sombra abajo-der).
class _Wordmark extends StatelessWidget {
  const _Wordmark(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: CceColors.textTertiary,
          shadows: [
            Shadow(
              color: Color(0x2EFFFFFF),
              offset: Offset(-0.6, -0.8),
            ),
            Shadow(
              color: Color(0xCC05060A),
              offset: Offset(0.8, 1.2),
              blurRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
