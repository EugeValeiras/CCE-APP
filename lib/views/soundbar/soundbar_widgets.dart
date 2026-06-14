// Parte de la librería de soundbar_screen.dart: así los sub-widgets privados
// (`_SoundbarHeaderCard`, etc.) y los helpers (`_handle`, `showIpDialog`)
// quedan visibles para la pantalla sin exportarse al resto de la app.
part of 'soundbar_screen.dart';

/// Sub-widgets del panel de Soundbar (PAQUETE C2). Privados al paquete: los
/// usa solo soundbar_screen.dart. Todos reciben el [JblService] y/o callbacks.
///
/// Todos los comandos pasan por [_handle] para reportar 502/fallos vía
/// SnackBar sin asumir éxito (los comandos del service devuelven bool).

/// Ejecuta un comando y muestra un SnackBar si devolvió false (falló/ignorado).
Future<void> _handle(Future<bool> action, BuildContext context) async {
  final ok = await action;
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo completar la acción')),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// Card de cabecera: ícono del parlante, nombre, estado de encendido y la
/// fuente actual (si la hay).
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
      neo: true,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: service.isOn
                  ? CceColors.accent.withValues(alpha: 0.18)
                  : CceColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: CceIcon(
              CceIcons.speaker,
              size: 28,
              color: service.isOn ? CceColors.accent : CceColors.textSecondary,
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
                      Flexible(child: StatusPill(label: src)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Power al header (movido desde Accesos rápidos): accent cuando ON.
          CceNeoSvgIconButton(
            svg: CceIcons.power,
            tooltip: service.isOn ? 'Apagar' : 'Encender',
            iconColor: service.isOn ? CceColors.accent : CceColors.neoTextSub,
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

/// Card del volumen: dial circular neumórfico con arco de progreso (violeta→
/// azul), número central grande y botones − / +. Debajo, un pill de mute
/// (Silenciar/Silenciado). Tocar el dial fija el volumen; − / + lo ajustan de
/// a 1 (rango 0–[kJblVolMax]). Si la barra no expone volumen (UPnP caído) se
/// atenúa y muestra "—".
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
      neo: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VOLUMEN',
            style: CceText.caption.copyWith(
              color: CceColors.neoTextSub,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
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
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: Size(dim, dim),
                                painter: _VolumeArcPainter(
                                  value: hasVolume
                                      ? (volume / kJblVolMax).clamp(0.0, 1.0)
                                      : 0.0,
                                  enabled: hasVolume,
                                ),
                              ),
                              // Centro del dial: solo el número grande.
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
          // Mute claro debajo de la fila [− , dial , +]: pill tappeable.
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasVolume
                  ? () => _handle(service.toggleMute(), context)
                  : null,
              child: Opacity(
                opacity: hasVolume ? 1 : 0.4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: CceColors.neoBase,
                    borderRadius: BorderRadius.circular(CceRadii.control),
                    border: Border.all(
                      color: muted ? CceColors.danger : CceColors.stroke,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CceIcon(
                        muted ? CceIcons.volumeX : CceIcons.volume2,
                        size: 18,
                        color: muted
                            ? CceColors.danger
                            : CceColors.neoTextSub,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        muted ? 'Silenciado' : 'Silenciar',
                        style: CceText.caption.copyWith(
                          color: muted
                              ? CceColors.danger
                              : CceColors.neoTextSub,
                        ),
                      ),
                    ],
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

/// Pinta el dial: carril hundido + arco de progreso con gradiente sweep
/// (accent→info) y un punto luminoso en la punta.
class _VolumeArcPainter extends CustomPainter {
  _VolumeArcPainter({required this.value, required this.enabled});

  final double value; // 0..1
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF12141A);
    canvas.drawArc(rect, _kVolStart, _kVolSweep, false, track);

    if (!enabled || value <= 0) return;

    final sweep = _kVolSweep * value.clamp(0.0, 1.0);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: _kVolStart,
        endAngle: _kVolStart + _kVolSweep,
        colors: [CceColors.accent, CceColors.info],
      ).createShader(rect);
    canvas.drawArc(rect, _kVolStart, sweep, false, progress);

    // Punto luminoso en la punta del arco.
    final tipAngle = _kVolStart + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tip,
      stroke,
      Paint()..color = CceColors.info.withValues(alpha: 0.28),
    );
    canvas.drawCircle(tip, stroke / 2 + 1, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_VolumeArcPainter old) =>
      old.value != value || old.enabled != enabled;
}

// ── Fuentes (FUENTES) ────────────────────────────────────────────────────────

/// Fila horizontal de fuentes estilo "chips". La fuente activa (best-effort
/// según `service.source`) se resalta con accent.
class _SourcesRow extends StatelessWidget {
  const _SourcesRow({required this.service});

  final JblService service;

  bool _isActive(String id) {
    final src = service.source?.toLowerCase();
    if (src == null) return false;
    switch (id) {
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
    final items = <Widget>[
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
      _SourceChip(
        svg: CceIcons.tv,
        label: 'TV',
        active: _isActive(JblRemoteKeys.tv),
        onTap: () => _handle(service.sendRemoteKey(JblRemoteKeys.tv), context),
      ),
    ];
    // Panel neumórfico con los chips repartidos (Expanded).
    return CceCard(
      neo: true,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(child: items[i]),
            if (i != items.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// Chip de fuente: plano dentro del panel. Activo = borde accent + contenido
/// accent (look del mockup); inactivo = borde tenue [CceColors.stroke].
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
    final fg = active ? CceColors.accent : CceColors.neoText;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: Border.all(
            color: active ? CceColors.accent : CceColors.stroke,
            width: active ? 1.6 : 1,
          ),
        ),
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
                color: active ? CceColors.accent : CceColors.neoTextSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Accesos rápidos (ACCESOS RÁPIDOS) ────────────────────────────────────────

/// Fila compacta de accesos rápidos (panel neumórfico). El 1er ítem es
/// Favoritos → abre el bottom sheet de sintonización (reemplaza al botón
/// "Sintonización", que ya no existe). Power se movió al header.
class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _QuickButton(
        svg: CceIcons.heart,
        label: 'Favori',
        active: true,
        activeColor: CceColors.danger,
        onTap: () => _openRadioSheet(context, service),
      ),
      _QuickButton(
        svg: CceIcons.tv,
        label: 'TV',
        onTap: () => _handle(service.sendRemoteKey(JblRemoteKeys.tv), context),
      ),
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
    ];
    // Cajas grandes (como las FUENTES), 4 por fila → 2 filas para los 7.
    return CceCard(
      neo: true,
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
        children: items,
      ),
    );
  }
}

/// Botón compacto de acceso rápido (ícono + label chico). Plano dentro del
/// panel; el estado activo tiñe el ícono (mute / favorito). Press = atenúa.
class _QuickButton extends StatefulWidget {
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
  State<_QuickButton> createState() => _QuickButtonState();
}

class _QuickButtonState extends State<_QuickButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.activeColor ?? CceColors.accent;
    final fg = widget.active ? accent : CceColors.neoText;
    // Caja grande con borde, igual estilo que los chips de FUENTES.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Opacity(
        opacity: _pressed ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.control),
            border: Border.all(
              color: widget.active ? accent : CceColors.stroke,
              width: widget.active ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CceIcon(widget.svg, size: 24, color: fg),
              const SizedBox(height: 8),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CceText.caption.copyWith(
                  color: widget.active ? accent : CceColors.neoTextSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encabezado de sección chico (FUENTES / ACCESOS RÁPIDOS).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
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
/// offline (las radios son server-side) — NO se gatea por online.
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
                    height: 4,
                    decoration: BoxDecoration(
                      color: CceColors.neoTextSub,
                      borderRadius: BorderRadius.circular(CceRadii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Sintonización', style: CceText.title),
                    ),
                    TextButton(
                      onPressed: () =>
                          _handle(service.saveCurrentRadio(), context),
                      child: const Text('Guardar la actual'),
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
/// muestran radios ni IP (no hay backend).
class _ServerErrorCard extends StatelessWidget {
  const _ServerErrorCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CceIcon(CceIcons.speaker, size: 32, color: CceColors.danger),
          const SizedBox(height: 12),
          const Text('No se pudo conectar al servidor', style: CceText.title),
          const SizedBox(height: 8),
          Text('Revisá la conexión con el API de CCE.', style: CceText.caption),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: service.refresh,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

/// [CRÍTICA-10] La barra respondió pero está en standby/inalcanzable a nivel
/// UPnP. Distinto de un fallo de servidor: las radios SÍ se muestran abajo.
class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.service, required this.onConfigureIp});

  final JblService service;
  final VoidCallback onConfigureIp;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CceIcon(CceIcons.speaker, size: 32, color: CceColors.textTertiary),
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
              FilledButton.tonal(
                onPressed: service.refresh,
                child: const Text('Reintentar'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onConfigureIp,
                child: const Text('Configurar IP'),
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
