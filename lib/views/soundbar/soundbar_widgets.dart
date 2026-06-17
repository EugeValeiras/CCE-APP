// Parte de la librería de soundbar_screen.dart: así los sub-widgets privados
// (`_SoundbarHeaderCard`, etc.) y los helpers (`_handle`, `showIpDialog`)
// quedan visibles para la pantalla sin exportarse al resto de la app.
//
// PART LIBRARY: este archivo es `part of 'soundbar_screen.dart'`. NO puede
// declarar imports propios — todos los imports viven en soundbar_screen.dart.
part of 'soundbar_screen.dart';

/// Sub-widgets del panel de Soundbar (PAQUETE C2). Privados al paquete: los
/// usa solo soundbar_screen.dart. Todos reciben el [JblService] y/o callbacks.
///
/// Lenguaje "super neumórfico": las CARDS son superficies RAISED-almohada
/// (CceCard neo:true), los CONTROLES pasivos/tracks/badges son WELLS hundidos
/// (neoSunken + neoInset, color OPACO siempre) y los CONTROLES accionables se
/// hunden (raised→inset) al presionar con haptic vía [_NeoPressable].
///
/// Todos los comandos pasan por [_handle] para reportar 502/fallos vía
/// SnackBar sin asumir éxito (los comandos del service devuelven bool).

/// Fondo del "drawer"/pantalla, MÁS OSCURO que la carcasa (neoBase) para que el
/// control flote sobre él. Réplica del `#16181D` del dashboard.
const Color _kDrawerBg = Color(0xFF16181D);

/// Sombra externa ESTÁNDAR de los controles convexos del dashboard
/// (3/3/8 negra abajo-der + -3/-3/8 luz arriba-izq). Es el relieve "sobresale"
/// de los chips, botones de acceso, +/- y la píldora de mute en reposo.
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

/// Sombra INSET de un control convexo presionado / activo "apagado" (no glow):
/// inset 2/2/6 negra + inset -2/-2/6 luz. Réplica del `:active` del dashboard.
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

/// Ejecuta un comando y muestra un SnackBar si devolvió false (falló/ignorado).
Future<void> _handle(Future<bool> action, BuildContext context) async {
  final ok = await action;
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No se pudo completar la acción'),
        backgroundColor: CceColors.neoSunken,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CceRadii.control),
        ),
      ),
    );
  }
}

// ── Helper neumórfico reutilizable ──────────────────────────────────────────

/// CHIP / BOTÓN CONVEXO del dashboard: superficie que SOBRESALE (gradiente
/// convexo claro→oscuro + sombra externa estándar). Al presionar pasa a INSET
/// (sombra interna) — réplica del `:active` del `.chip`/`.quick`. El estado
/// ACTIVO ("encendido") NO usa inset ni borde: lo comunica el call-site
/// encendiendo ícono+label con glow (color de marca + text-shadow + drop-shadow
/// del ícono), exactamente como el dashboard (`.chip.active`).
///
/// El color de fondo se mantiene SIEMPRE en neoBase OPACO (requisito de
/// `BlurStyle.inner` para que el inset al presionar no se vea plano); el
/// gradiente convexo se pinta encima.
///
/// Lo usan [_SourceChip], [_QuickButton] y la píldora de mute del volumen.
class _NeoPressable extends StatelessWidget {
  const _NeoPressable({
    required this.child,
    required this.onTap,
    this.active = false,
    this.activeColor,
    this.radius = CceRadii.control,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap; // null o enabled:false => deshabilitado
  // ACTIVO = "encendido" con glow (lo aplica el call-site con su color). El
  // convexo NO se hunde ni cambia material al estar activo (igual que el
  // dashboard): la superficie sigue sobresaliendo, solo se prende la luz.
  final bool active;
  // ignore: unused_field
  final Color? activeColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool haptic;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    final br = BorderRadius.circular(radius);
    final rest = _convexShadow(); // sobresale (relieve externo)
    final pressed = _convexInset(); // se hunde al apretar

    Widget surface(double t) {
      final shadow = !on
          ? const <BoxShadow>[]
          : [
              for (var i = 0; i < rest.length; i++)
                BoxShadow.lerp(rest[i], pressed[i], t)!,
            ];
      final box = Container(
        padding: padding,
        decoration: BoxDecoration(
          // Fondo opaco SIEMPRE (para el inset al presionar) + gradiente convexo
          // claro→oscuro encima: la superficie "sobresale" como el dashboard.
          color: CceColors.neoBase,
          gradient: CceGradients.convex(CceColors.neoBase),
          borderRadius: br,
          boxShadow: shadow,
        ),
        child: child,
      );
      return on ? box : Opacity(opacity: 0.4, child: box);
    }

    return CceNeoPress(
      onTap: on ? onTap : null,
      haptic: haptic,
      builder: (ctx, t) => surface(t),
    );
  }
}

/// Ícono que "se enciende" como luz interna cuando [on]: un glow suave del
/// [color] (BoxShadow difuso, blur ~14) detrás del [CceIcon], que pasa a tinte
/// [color]. Apagado: ícono en [offColor] sin glow. Reemplaza al borde del
/// estado activo de [_NeoPressable] (los chips/botones se "prenden" en vez de
/// enmarcarse).
class _GlowIcon extends StatelessWidget {
  const _GlowIcon({
    required this.svg,
    required this.on,
    required this.color,
    required this.offColor,
    this.size = 22,
  });

  final String svg;
  final bool on;
  final Color color;
  final Color offColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = CceIcon(svg, size: size, color: on ? color : offColor);
    if (!on) return icon;
    // Glow difuso del color accent detrás del ícono (la "luz" encendida).
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: icon,
    );
  }
}

/// Shadows "encendidas" para un label activo: halo del [color] alrededor del
/// texto (glow suave), para que la etiqueta también "prenda" junto al ícono.
List<Shadow> _glowTextShadows(Color color) => [
      Shadow(color: color.withValues(alpha: 0.55), blurRadius: 12),
      Shadow(color: color.withValues(alpha: 0.35), blurRadius: 4),
    ];

/// Well hundido reutilizable para badges/avatares: contenedor con fill OPACO
/// [CceColors.neoSunken] + inner-shadow [CceShadows.neoInset]. El color opaco es
/// requisito de `BlurStyle.inner`.
class _NeoWell extends StatelessWidget {
  const _NeoWell({
    required this.child,
    this.size,
    this.radius = CceRadii.control,
    this.circle = false,
    this.blur = 8,
    this.offset = 3,
  });

  final Widget child;
  final double? size;
  final double radius;
  final bool circle;
  final double blur;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        boxShadow: CceShadows.neoInset(blur: blur, offset: offset),
      ),
      child: child,
    );
  }
}

// ── Power ─────────────────────────────────────────────────────────────────

/// Etiqueta amigable para la fuente actual. La barra reporta ids crudos
/// (p.ej. "RADIO-NETWORK"); acá los acortamos para mostrarlos en la UI.
/// Conservado para call-sites externos que muestren la fuente (la home card).
// ignore: unused_element
String _sourceLabel(String src) {
  final s = src.toLowerCase();
  if (s.contains('radio') || s.contains('network')) return 'RADIO';
  return src;
}

/// Botón de POWER redondo 52px, alineado arriba-IZQUIERDA de la carcasa (réplica
/// del `.neo-btn.round.power` del dashboard): base neoBase plana + sombra
/// EXTERNA estándar (4/4/10) → al presionar se hunde (inset). El ícono va
/// neoTextSub apagado y jbl-orange cuando la barra está encendida. Wake-friendly:
/// el toggle de power funciona también en standby.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final on = service.isOn;
    final raised = const [
      BoxShadow(
        color: Color(0xB30C0D11), // rgba(12,13,17,0.70)
        blurRadius: 10,
        offset: Offset(4, 4),
      ),
      BoxShadow(
        color: Color(0x8C2A2D37), // rgba(42,45,55,0.55)
        blurRadius: 10,
        offset: Offset(-4, -4),
      ),
    ];
    final inset = const [
      BoxShadow(
        color: Color(0xD90C0D11),
        blurRadius: 7,
        offset: Offset(3, 3),
        blurStyle: BlurStyle.inner,
      ),
      BoxShadow(
        color: Color(0x732A2D37),
        blurRadius: 7,
        offset: Offset(-3, -3),
        blurStyle: BlurStyle.inner,
      ),
    ];

    // Alineado a la izquierda (no estira): la fila lo deja flush-left.
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: on ? 'Apagar' : 'Encender',
        child: CceNeoPress(
          onTap: () => _handle(service.togglePower(), context),
          builder: (ctx, t) => Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              boxShadow: [
                for (var i = 0; i < raised.length; i++)
                  BoxShadow.lerp(raised[i], inset[i], t)!,
              ],
            ),
            child: CceIcon(
              CceIcons.power,
              size: 24,
              emboss: false,
              color: on ? CceColors.jblOrange : CceColors.neoTextSub,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wordmark JBL abajo del control (réplica del `.wordmark` del dashboard): logo
/// en jbl-orange (currentColor) con un drop-shadow suave que lo "moldea".
class _JblWordmark extends StatelessWidget {
  const _JblWordmark();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0xCC05060A), // sombra de contacto (moldea el logo)
              offset: Offset(0.8, 1.2),
              blurRadius: 1,
            ),
          ],
        ),
        child: CceIcon(
          CceIcons.jbl,
          size: 44,
          emboss: false,
          color: CceColors.jblOrange,
        ),
      ),
    );
  }
}

// ── Volumen (dial circular) ─────────────────────────────────────────────────

const double _kVolStart = 135 * math.pi / 180; // 135° (arranca abajo-izquierda)
const double _kVolSweep = 270 * math.pi / 180; // 270° de barrido (gap abajo)

/// Card del volumen (PROTAGONISTA, RAISED almohada): dial circular como WELL
/// hundido profundo con arco de progreso (violeta→azul + glow + knob-joya),
/// número central grande grabado, botones − / + (raised→inset) y una píldora de
/// mute neumórfica (RAISED→INSET, INSET danger permanente cuando muted). Tocar
/// el dial fija el volumen; − / + lo ajustan de a 1 (rango 0–[kJblVolMax]). Si
/// la barra no expone volumen (UPnP caído) se atenúa y muestra "—".
class _VolumeDialCard extends StatelessWidget {
  const _VolumeDialCard({required this.service});

  final JblService service;

  void _setFromLocal(Offset local, double dim) {
    final center = Offset(dim / 2, dim / 2);
    final v = local - center;
    var delta = math.atan2(v.dy, v.dx) - _kVolStart; // canvas (y hacia abajo)
    while (delta < 0) delta += 2 * math.pi;
    while (delta >= 2 * math.pi) delta -= 2 * math.pi;
    final double frac;
    if (delta <= _kVolSweep) {
      frac = delta / _kVolSweep;
    } else {
      // Dentro del gap inferior: pegar al extremo más cercano.
      final gap = 2 * math.pi - _kVolSweep;
      frac = (delta - _kVolSweep) > gap / 2 ? 0.0 : 1.0;
    }
    service.setVolume((frac * kJblVolMax).round());
  }

  @override
  Widget build(BuildContext context) {
    final hasVolume = service.hasVolume;
    final muted = service.muted;
    final volume = service.volume;

    // Contenido del volumen (sin card propia: va dentro del panel del control).
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stepper(
                svg: CceIcons.minus,
                tooltip: 'Bajar volumen',
                onTap: hasVolume
                    ? () => _handle(service.nudgeVolume(-1), context)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Dial cuadrado responsivo: nunca desborda (teléfonos
                    // angostos) ni queda enorme en iPad.
                    final dim =
                        constraints.maxWidth.clamp(132.0, 196.0).toDouble();
                    return Center(
                      child: SizedBox(
                        width: dim,
                        height: dim,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: hasVolume
                              ? (d) => _setFromLocal(d.localPosition, dim)
                              : null,
                          // RepaintBoundary: aísla el repintado del dial del
                          // resto del árbol (AnimatedBuilder sobre el service).
                          child: RepaintBoundary(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // PLATO del dial (dashboard `.dial`): SOBRESALE
                                // pero hunde la cara. Gradiente CÓNCAVO (oscuro
                                // arriba-izq → claro abajo-der) + sombras de
                                // PLATO (relieve externo + inset suave). Color
                                // opaco neoBase para que el inset no se aplane.
                                Container(
                                  width: dim,
                                  height: dim,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: CceColors.neoBase,
                                    gradient:
                                        CceGradients.concave(CceColors.neoBase),
                                    boxShadow:
                                        CceShadows.plato(blur: 15, offset: 6),
                                  ),
                                ),
                                // Track inset pintado a mano + arco de valor +
                                // knob-joya (geometría angular intacta).
                                CustomPaint(
                                  size: Size(dim, dim),
                                  painter: _VolumeArcPainter(
                                    value: hasVolume
                                        ? (volume / kJblVolMax).clamp(0.0, 1.0)
                                        : 0.0,
                                    enabled: hasVolume,
                                  ),
                                ),
                                // Centro del dial: el número grande "grabado"
                                // (blanco neoText, SIN embossShadows: el emboss
                                // está calibrado para titleInk gris, no blanco).
                                Text(
                                  hasVolume ? '$volume' : '—',
                                  style: const TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w700,
                                    color: CceColors.neoText,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              _Stepper(
                svg: CceIcons.plus,
                tooltip: 'Subir volumen',
                onTap: hasVolume
                    ? () => _handle(service.nudgeVolume(1), context)
                    : null,
              ),
            ],
          ),
          // Mute como PÍLDORA (dashboard `.mute-pill`): base neoBase PLANA +
          // sombra externa estándar en reposo → al presionar se hunde; muted =
          // INSET permanente con ícono/label danger (NO glow — el dashboard usa
          // inset + color para el mute, distinto de los chips).
          const SizedBox(height: 14),
          Center(
            child: _MutePill(
              muted: muted,
              enabled: hasVolume,
              onTap: hasVolume
                  ? () => _handle(service.toggleMute(), context)
                  : null,
            ),
          ),
        ],
      );
  }
}

/// Stepper +/- del volumen (dashboard `.vol-row .neo-btn.round`): botón redondo
/// 52px CONVEXO (gradiente convexo + sombra externa) que se hunde al apretar.
/// `flex-shrink: 0` ⇒ acá va con tamaño fijo (no se deforma a óvalo en la fila).
class _Stepper extends StatelessWidget {
  const _Stepper({required this.svg, required this.tooltip, required this.onTap});

  final String svg;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final rest = _convexShadow();
    final pressed = _convexInset();

    final button = CceNeoPress(
      onTap: onTap,
      builder: (ctx, t) {
        final box = Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CceColors.neoBase,
            gradient: CceGradients.convex(CceColors.neoBase),
            boxShadow: on
                ? [
                    for (var i = 0; i < rest.length; i++)
                      BoxShadow.lerp(rest[i], pressed[i], t)!,
                  ]
                : const <BoxShadow>[],
          ),
          child: CceIcon(
            svg,
            size: 22,
            emboss: false,
            color: on ? CceColors.neoText : CceColors.neoTextSub,
          ),
        );
        return on ? box : Opacity(opacity: 0.45, child: box);
      },
    );
    return Tooltip(message: tooltip, child: button);
  }
}

/// Píldora de MUTE (dashboard `.mute-pill`): base neoBase PLANA + sombra externa
/// estándar; al presionar se hunde (inset). muted = INSET permanente con
/// ícono/label en danger (NO glow — distinto de los chips convexos).
class _MutePill extends StatelessWidget {
  const _MutePill({
    required this.muted,
    required this.enabled,
    required this.onTap,
  });

  final bool muted;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    final rest = muted ? _convexInset() : _convexShadow();
    final pressed = _convexInset();
    final color = muted ? CceColors.danger : CceColors.neoTextSub;

    final pill = CceNeoPress(
      onTap: on ? onTap : null,
      builder: (ctx, t) {
        final box = Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            // Base PLANA neoBase (sin gradiente convexo: la píldora no sobresale
            // como los chips, es chata como en el dashboard).
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: on
                ? [
                    for (var i = 0; i < rest.length; i++)
                      BoxShadow.lerp(rest[i], pressed[i], t)!,
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CceIcon(
                muted ? CceIcons.volumeX : CceIcons.volume2,
                size: 18,
                emboss: false,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                muted ? 'Silenciado' : 'Silenciar',
                style: CceText.caption.copyWith(color: color),
              ),
            ],
          ),
        );
        return on ? box : Opacity(opacity: 0.45, child: box);
      },
    );
    return pill;
  }
}

/// Pinta el dial: TRACK como canal hundido (well pintado a mano, ya que
/// BlurStyle.inner no sigue un arco) + arco de progreso con gradiente sweep
/// (accent→info) con glow + knob-joya luminoso en la punta. Geometría angular
/// IDÉNTICA a [_setFromLocal] (_kVolStart / _kVolSweep, center=size/2).
class _VolumeArcPainter extends CustomPainter {
  _VolumeArcPainter({required this.value, required this.enabled});

  final double value; // 0..1
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // (1) TRACK como canal hundido: base neoSunken gruesa + sombra interna
    // sup-izq desplazada + highlight inf-der desplazado (lee como hundido sin
    // clips frágiles).
    final trackBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoSunken;
    canvas.drawArc(rect, _kVolStart, _kVolSweep, false, trackBase);

    final trackShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.62
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoDark.withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(
      rect.shift(const Offset(1.5, 1.5)),
      _kVolStart,
      _kVolSweep,
      false,
      trackShadow,
    );

    final trackHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.45
      ..strokeCap = StrokeCap.round
      ..color = CceColors.neoLight.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(
      rect.shift(const Offset(-1.5, -1.5)),
      _kVolStart,
      _kVolSweep,
      false,
      trackHighlight,
    );

    if (!enabled || value <= 0) return;

    final sweep = _kVolSweep * value.clamp(0.0, 1.0);

    // (3) GLOW del arco de valor.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 4
      ..strokeCap = StrokeCap.round
      ..color = CceColors.jblOrange.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, _kVolStart, sweep, false, glow);

    // ARCO de valor (accent→info).
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: _kVolStart,
        endAngle: _kVolStart + _kVolSweep,
        colors: [CceColors.jblOrange, CceColors.warm],
      ).createShader(rect);
    canvas.drawArc(rect, _kVolStart, sweep, false, progress);

    // (4) KNOB de la punta del arco (dashboard `.knob`): disco BLANCO sólido,
    // con un halo accent suave para que "flote" sobre el arco.
    final tipAngle = _kVolStart + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tip,
      stroke * 0.7,
      Paint()..color = CceColors.jblOrange.withValues(alpha: 0.25),
    );
    canvas.drawCircle(tip, stroke / 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_VolumeArcPainter old) =>
      old.value != value || old.enabled != enabled;
}

// ── Fuentes (FUENTES) ────────────────────────────────────────────────────────

/// Fila horizontal de fuentes estilo "chips" (panel RAISED). La fuente activa
/// (best-effort según `service.source`) se resalta como WELL apretado + accent.
class _SourcesRow extends StatelessWidget {
  const _SourcesRow({required this.service});

  final JblService service;

  bool _isActive(String id) {
    final src = service.source?.toLowerCase();
    if (src == null) return false;
    switch (id) {
      case 'radio':
        return src.contains('radio') || src.contains('network');
      case JblRemoteKeys.bluetooth:
        return src.contains('bt') || src.contains('blue');
      case JblRemoteKeys.hdmi:
        return src.contains('hdmi') || src.contains('arc');
      case JblRemoteKeys.tv:
        return src.contains('tv') || src.contains('optic');
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Orden pedido: TV, Radio, Bluetooth, HDMI.
    final items = <Widget>[
      _SourceChip(
        svg: CceIcons.tv,
        label: 'TV',
        active: _isActive(JblRemoteKeys.tv),
        onTap: () => _handle(service.sendRemoteKey(JblRemoteKeys.tv), context),
      ),
      // Radio: la fuente "RADIO-NETWORK". No es una tecla del remote; se
      // dispara reproduciendo la radio favorita (playRadio sin nombre), que
      // además despierta la barra y la pone en la fuente de red.
      _SourceChip(
        svg: CceIcons.radio,
        label: 'Radio',
        active: _isActive('radio'),
        onTap: () => _handle(service.playRadio(), context),
      ),
      _SourceChip(
        svg: CceIcons.bluetooth,
        label: 'Bluetooth',
        active: _isActive(JblRemoteKeys.bluetooth),
        onTap: () =>
            _handle(service.sendRemoteKey(JblRemoteKeys.bluetooth), context),
      ),
      _SourceChip(
        svg: CceIcons.hdmi,
        label: 'HDMI',
        active: _isActive(JblRemoteKeys.hdmi),
        onTap: () => _handle(service.sendRemoteKey(JblRemoteKeys.hdmi), context),
      ),
    ];
    // Sin contenedor: los chips neumórficos flotan directo sobre el fondo.
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: items[i]),
          if (i != items.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

/// Chip de fuente: botón neumórfico (RAISED en reposo → INSET al presionar) vía
/// [_NeoPressable]. ACTIVO (fuente actual) = WELL hundido permanente + ícono /
/// label tinte accent (la fuente "queda apretada"). El haptic lo centraliza
/// [_NeoPressable] (no duplicar en el call-site).
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.svg,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String svg;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NeoPressable(
      onTap: onTap,
      active: active,
      activeColor: CceColors.jblOrange,
      radius: CceRadii.control,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Activo = "luz interna" encendida (glow accent), no borde.
          _GlowIcon(
            svg: svg,
            on: active,
            color: CceColors.jblOrange,
            offColor: CceColors.neoText,
            size: 22,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CceText.caption.copyWith(
              color: active ? CceColors.jblOrange : CceColors.neoTextSub,
              shadows: active ? _glowTextShadows(CceColors.jblOrange) : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Accesos rápidos (ACCESOS RÁPIDOS) ────────────────────────────────────────

/// Grid de accesos rápidos (panel RAISED). El 1er ítem es Favoritos → abre el
/// bottom sheet de sintonización (NO _handle). Power se movió al header.
class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      // Favorites: abre el sheet de radios. Botón común (sin estado activo ni
      // tinte rojo) — es una acción, no un toggle de estado.
      _QuickButton(
        svg: CceIcons.heart,
        label: 'Favorites',
        onTap: () => _openRadioSheet(context, service),
      ),
      // TV vive en FUENTES (no se duplica acá).
      _QuickButton(
        svg: CceIcons.play,
        label: 'Play',
        onTap: () =>
            _handle(service.sendRemoteKey(JblRemoteKeys.playpause), context),
      ),
      // Atmos es un modo de sonido (no una fuente): vive en accesos rápidos.
      _QuickButton(
        svg: CceIcons.atmos,
        label: 'Atmos',
        onTap: () =>
            _handle(service.sendRemoteKey(JblRemoteKeys.atmos), context),
      ),
      _QuickButton(
        svg: CceIcons.bass,
        label: 'Bass',
        onTap: () => _handle(service.sendRemoteKey(JblRemoteKeys.bass), context),
      ),
      _QuickButton(
        svg: CceIcons.calibrate,
        label: 'Calibr',
        onTap: () =>
            _handle(service.sendRemoteKey(JblRemoteKeys.calibrate), context),
      ),
      _QuickButton(
        svg: CceIcons.surround,
        label: 'Surr',
        onTap: () =>
            _handle(service.sendRemoteKey(JblRemoteKeys.surround), context),
      ),
      // Night listening (Personal Listening Mode): toggle de estado real (NO un
      // press momentáneo). Se enciende (info/azul) cuando está activo.
      _QuickButton(
        svg: CceIcons.moon,
        label: 'Night',
        active: service.nightMode,
        activeColor: CceColors.info,
        onTap: () => _handle(service.toggleNightMode(), context),
      ),
    ];
    // Sin contenedor: los botones neumórficos flotan directo sobre el fondo.
    // 7 ítems (TV vive en FUENTES), 4 por fila → 2 filas.
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.92,
      children: items,
    );
  }
}

/// Botón compacto de acceso rápido (ícono + label). Neumórfico (RAISED →
/// INSET al presionar) vía [_NeoPressable]. ACTIVO (Favori) = WELL hundido
/// permanente con ícono / label tinte activeColor (corazón danger "hundido
/// encendido"). El haptic lo centraliza [_NeoPressable].
class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.svg,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final String svg;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? CceColors.jblOrange;
    return _NeoPressable(
      onTap: onTap,
      active: active,
      activeColor: accent,
      radius: CceRadii.control,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Activo (p.ej. Night) = "luz interna" encendida (glow accent), no borde.
          _GlowIcon(
            svg: svg,
            on: active,
            color: accent,
            offColor: CceColors.neoText,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CceText.caption.copyWith(
              color: active ? accent : CceColors.neoTextSub,
              shadows: active ? _glowTextShadows(accent) : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de sección chico (FUENTES / ACCESOS RÁPIDOS). Presentacional.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: CceText.caption.copyWith(
          color: CceColors.neoTextSub,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Sintonización (bottom sheet de radios) ──────────────────────────────────
// El acceso al sheet ahora es el botón Favoritos de ACCESOS RÁPIDOS
// (`_openRadioSheet`); ya no existe un botón "Sintonización" aparte.

/// Bottom sheet neumórfico (fondo neoBase) con las radios guardadas: tocar
/// reproduce, mantener presionado borra (con confirmación). Funciona online y
/// offline (las radios son server-side) — NO se gatea por online. El handle es
/// un WELL hundido fino; "Guardar" es un pill neo (CceNeoActionButton).
Future<void> _openRadioSheet(BuildContext context, JblService service) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: CceColors.neoBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (sheetCtx) {
      // El sheet escucha al service para reflejar guardar/borrar radios.
      return AnimatedBuilder(
        animation: service,
        builder: (context, _) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: CceColors.neoSunken,
                      borderRadius: BorderRadius.circular(CceRadii.pill),
                      boxShadow: CceShadows.neoInset(blur: 4, offset: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Sintonización', style: CceText.title),
                    ),
                    CceNeoActionButton(
                      label: 'Guardar',
                      onPressed: () =>
                          _handle(service.saveCurrentRadio(), context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(child: _RadioList(service: service, sheet: true)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── Radios ──────────────────────────────────────────────────────────────────

/// Lista de radios guardadas. Cada item reproduce al tocar y se borra con
/// long-press (con confirmación). Funciona aún con la barra offline
/// (server-side); el 502 se reporta vía SnackBar.
class _RadioList extends StatelessWidget {
  const _RadioList({required this.service, this.sheet = false});

  final JblService service;

  /// Cuando se monta dentro del bottom sheet: lista scrolleable y al tocar una
  /// radio se cierra el sheet.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final radios = service.radios;
    if (radios.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Sin radios guardadas', style: CceText.caption),
      );
    }
    // [CRÍTICA-13] capturar en local antes de comparar con cada item.
    final src = service.source;

    final tiles = <Widget>[
      for (final r in radios) ...[
        _RadioTile(
          radio: r,
          playing: src != null && src == r.name,
          onTap: () {
            _handle(service.playRadio(r.name), context);
            if (sheet) Navigator.of(context).maybePop();
          },
          onLongPress: () => _confirmDelete(context, r),
        ),
        const SizedBox(height: 12),
      ],
    ];

    if (sheet) {
      return ListView(shrinkWrap: true, children: tiles);
    }
    return Column(children: tiles);
  }

  Future<void> _confirmDelete(BuildContext context, JblRadio r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar radio'),
        content: Text('¿Eliminar "${r.name}" de las radios guardadas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _handle(service.deleteRadio(r.name), context);
    }
  }
}

/// Tile de radio: almohada RAISED (CceCard neo:true) con onTap (reproduce) /
/// onLongPress (borra). Cuando suena: ícono ok + StatusDot pulsante.
class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.radio,
    required this.playing,
    required this.onTap,
    required this.onLongPress,
  });

  final JblRadio radio;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      neo: true,
      radius: CceRadii.tile,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          CceIcon(
            CceIcons.radio,
            size: 22,
            color: playing ? CceColors.ok : CceColors.textSecondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              radio.name,
              style: CceText.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (playing) ...[
            const SizedBox(width: 8),
            const StatusDot(
              CceColors.ok,
              pulse: true,
              semanticLabel: 'Reproduciendo',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Estados de error / offline ──────────────────────────────────────────────

/// [CRÍTICA-10] Fallo real de red/servidor: el API CCE no respondió. NO se
/// muestran radios ni IP (no hay backend). CONTENIDO PURO (sin card propia): va
/// DENTRO del panel unificado del control, fusionado al mismo material; el
/// relieve lo aportan los wells internos (ícono en WELL danger) + pill neo.
class _ServerErrorPanel extends StatelessWidget {
  const _ServerErrorPanel({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NeoWell(
          size: 56,
          radius: CceRadii.control,
          child: CceIcon(CceIcons.jbl, size: 32, color: CceColors.danger),
        ),
        const SizedBox(height: 12),
        const Text('No se pudo conectar al servidor', style: CceText.title),
        const SizedBox(height: 8),
        Text('Revisá la conexión con el API de CCE.', style: CceText.caption),
        const SizedBox(height: 16),
        // [CONTRATO] referencia directa a service.refresh (sin _handle).
        CceNeoActionButton(
          label: 'Reintentar',
          onPressed: service.refresh,
        ),
      ],
    );
  }
}

/// [CRÍTICA-10] La barra respondió pero está en standby/inalcanzable a nivel
/// UPnP. Distinto de un fallo de servidor: las fuentes/accesos SÍ se muestran
/// abajo. CONTENIDO PURO (sin card propia): va DENTRO del panel unificado,
/// fusionado al mismo material; el relieve lo aportan el WELL neutro del ícono +
/// los pills neo.
class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel({required this.service, required this.onConfigureIp});

  final JblService service;
  final VoidCallback onConfigureIp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NeoWell(
          size: 56,
          radius: CceRadii.control,
          child: CceIcon(
            CceIcons.jbl,
            size: 32,
            color: CceColors.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        const Text('Soundbar fuera de línea', style: CceText.title),
        const SizedBox(height: 8),
        Text(
          'No se encontró el JBL en la red. Verificá que esté encendido '
          'o configurá su IP.',
          style: CceText.caption,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CceNeoActionButton(
              label: 'Reintentar',
              onPressed: service.refresh,
            ),
            const SizedBox(width: 8),
            CceNeoActionButton(
              label: 'Configurar IP',
              onPressed: onConfigureIp,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Diálogo de configuración de IP ──────────────────────────────────────────

/// [CRÍTICA E3] La config de IP del JBL vive en la pantalla de Soundbar.
/// Prellenado capturando la IP actual en local [CRÍTICA-13].
Future<void> showIpDialog(BuildContext context, JblService service) async {
  final currentIp = service.status?.ip;
  final controller = TextEditingController(text: currentIp ?? '');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('IP del soundbar'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Dirección IP',
          hintText: '192.168.1.103',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          onPressed: () {
            final ip = controller.text.trim();
            Navigator.of(ctx).pop();
            _handle(service.setIp(ip), context);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
