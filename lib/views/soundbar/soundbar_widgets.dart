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

/// Superficie accionable con feedback de presión (RAISED en reposo → INSET al
/// presionar) + estado ACTIVO (INSET permanente). Centraliza el
/// `HapticFeedback.selectionClick` del tap. El color de fondo (neoBase /
/// neoSunken) es OPACO SIEMPRE: requisito de `BlurStyle.inner` del inner-shadow
/// — un color con alpha rompe el well silenciosamente (se ve plano).
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
  final bool active; // estado seleccionado (well permanente)
  final Color? activeColor; // tinte del borde sutil cuando active
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool haptic;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    final br = BorderRadius.circular(radius);
    // Reposo: inset si está activo (well permanente), si no extruido. Al apretar
    // interpola raised→inset por `t` y la ESCALA la aporta CceNeoPress (feedback
    // animado y consistente con el resto de la app, en vez del cambio de golpe).
    final rest = active
        ? CceShadows.neoInset(blur: 7, offset: 3)
        : CceShadows.neo(blur: 8, offset: 3);
    final pressed = CceShadows.neoInset(blur: 7, offset: 3);
    final restBg = active ? CceColors.neoSunken : CceColors.neoBase;
    final Color? borderColor = active ? activeColor : null;

    Widget surface(double t) {
      final shadow = !on
          ? const <BoxShadow>[]
          : [
              for (var i = 0; i < rest.length; i++)
                BoxShadow.lerp(rest[i], pressed[i], t)!,
            ];
      // Fondo opaco SIEMPRE (BlurStyle.inner del inset lo exige): interpola al
      // pozo (neoSunken) a medida que se hunde.
      final bg = Color.lerp(restBg, CceColors.neoSunken, on ? t : 0.0)!;
      final box = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: br,
          boxShadow: shadow,
          border: borderColor != null
              ? Border.all(
                  color: borderColor.withValues(alpha: 0.55),
                  width: 1.2,
                )
              : null,
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

// ── Header ──────────────────────────────────────────────────────────────────

/// Etiqueta amigable para la fuente actual. La barra reporta ids crudos
/// (p.ej. "RADIO-NETWORK"); acá los acortamos para mostrarlos en la UI.
String _sourceLabel(String src) {
  final s = src.toLowerCase();
  if (s.contains('radio') || s.contains('network')) return 'RADIO';
  return src;
}

/// Card de cabecera (RAISED almohada): avatar del parlante en WELL hundido,
/// nombre, estado de encendido y la fuente actual (si la hay), con el power al
/// costado (raised→inset al presionar via CceNeoSvgIconButton).
class _SoundbarHeaderCard extends StatelessWidget {
  const _SoundbarHeaderCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final String powerLabel;
    final Color dotColor;
    switch (service.status?.power) {
      case 'on':
        powerLabel = 'Encendido';
        dotColor = CceColors.ok;
        break;
      case 'off':
        powerLabel = 'En espera';
        dotColor = CceColors.textTertiary;
        break;
      default:
        powerLabel = 'Desconocido';
        dotColor = CceColors.textTertiary;
    }
    // [CRÍTICA-13] capturar en local: null-promotion no aplica a getters.
    final src = service.source;

    return CceCard(
      neoInset: true,
      child: Row(
        children: [
          // Avatar del speaker: WELL hundido (neoSunken + neoInset opaco). El
          // ícono pasa a accent cuando isOn / neoTextSub cuando no.
          _NeoWell(
            size: 54,
            radius: CceRadii.control,
            child: CceIcon(
              CceIcons.jbl,
              size: 28,
              color: service.isOn ? CceColors.jblOrange : CceColors.neoTextSub,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.displayName,
                  style: CceText.title,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusDot(
                      dotColor,
                      pulse: service.isOn,
                      semanticLabel: powerLabel,
                    ),
                    const SizedBox(width: 8),
                    Text(powerLabel, style: CceText.caption),
                    if (src != null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: StatusPill(label: _sourceLabel(src))),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Power al header: raised→inset al presionar (lo da el componente),
          // accent cuando ON. tooltip dinámico.
          CceNeoSvgIconButton(
            svg: CceIcons.power,
            tooltip: service.isOn ? 'Apagar' : 'Encender',
            iconColor: service.isOn ? CceColors.jblOrange : CceColors.neoTextSub,
            size: 48,
            onPressed: () => _handle(service.togglePower(), context),
          ),
        ],
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

    return CceCard(
      neoInset: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CceNeoSvgIconButton(
                svg: CceIcons.minus,
                tooltip: 'Bajar volumen',
                size: 56,
                onPressed: hasVolume
                    ? () => _handle(service.nudgeVolume(-1), context)
                    : null,
              ),
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
                                // WELL físico del dial: hueco circular hundido
                                // (color OPACO neoSunken para BlurStyle.inner).
                                Container(
                                  width: dim,
                                  height: dim,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: CceColors.neoSunken,
                                    boxShadow:
                                        CceShadows.neoInset(blur: 12, offset: 5),
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
              CceNeoSvgIconButton(
                svg: CceIcons.plus,
                tooltip: 'Subir volumen',
                size: 56,
                onPressed: hasVolume
                    ? () => _handle(service.nudgeVolume(1), context)
                    : null,
              ),
            ],
          ),
          // Mute como píldora neumórfica con press: RAISED en reposo → INSET al
          // presionar; muted = INSET permanente con contenido/borde danger.
          const SizedBox(height: 12),
          Center(
            child: _NeoPressable(
              enabled: hasVolume,
              active: muted,
              activeColor: CceColors.danger,
              radius: CceRadii.control,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: hasVolume
                  ? () => _handle(service.toggleMute(), context)
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CceIcon(
                    muted ? CceIcons.volumeX : CceIcons.volume2,
                    size: 18,
                    color: muted ? CceColors.danger : CceColors.neoTextSub,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    muted ? 'Silenciado' : 'Silenciar',
                    style: CceText.caption.copyWith(
                      color: muted ? CceColors.danger : CceColors.neoTextSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

    // (4) KNOB-joya en la punta del arco: halo accent + disco blanco + punto
    // interior info.
    final tipAngle = _kVolStart + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tip,
      stroke * 0.9,
      Paint()..color = CceColors.jblOrange.withValues(alpha: 0.30),
    );
    canvas.drawCircle(tip, stroke / 2 + 2, Paint()..color = Colors.white);
    canvas.drawCircle(tip, stroke / 2 - 2, Paint()..color = CceColors.info);
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
    final fg = active ? CceColors.jblOrange : CceColors.neoText;
    return _NeoPressable(
      onTap: onTap,
      active: active,
      activeColor: CceColors.jblOrange,
      radius: CceRadii.control,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(svg, size: 22, color: fg),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CceText.caption.copyWith(
              color: active ? CceColors.jblOrange : CceColors.neoTextSub,
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
    final fg = active ? accent : CceColors.neoText;
    return _NeoPressable(
      onTap: onTap,
      active: active,
      activeColor: accent,
      radius: CceRadii.control,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CceIcon(svg, size: 24, color: fg),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CceText.caption.copyWith(
              color: active ? accent : CceColors.neoTextSub,
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
/// muestran radios ni IP (no hay backend). Card RAISED con acento danger:
/// ícono en WELL danger + botón "Reintentar" pill neo.
class _ServerErrorCard extends StatelessWidget {
  const _ServerErrorCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      neo: true,
      child: Column(
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
      ),
    );
  }
}

/// [CRÍTICA-10] La barra respondió pero está en standby/inalcanzable a nivel
/// UPnP. Distinto de un fallo de servidor: las radios SÍ se muestran abajo.
/// Card RAISED tono neutro: ícono en WELL neutro + dos pills neo.
class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.service, required this.onConfigureIp});

  final JblService service;
  final VoidCallback onConfigureIp;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      neo: true,
      child: Column(
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
      ),
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
