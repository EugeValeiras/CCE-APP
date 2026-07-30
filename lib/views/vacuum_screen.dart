import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/app_messenger.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_neo_press.dart';
import '../theme/components/cce_segmented.dart';
import '../theme/components/status_dot.dart';
import '../utils/vacuum_modes.dart';
import '../utils/vacuum_state.dart';
import '../widgets/vacuum_tile.dart';

/// Control neumórfico del robot aspiradora (Roborock Qrevo vía Matter RVC +
/// sidecar). Mismo canon que el remote de TV / panel JBL: carcasa flotante
/// neoBase radius 40 sobre fondo [CceColors.bg], sin AppBar (volver = swipe).
///
/// Secciones: estado grande (disco + glow por color de estado) · métricas
/// (batería/modo) · transporte contextual (Limpiar/Pausar/Reanudar/A la base)
/// · modo de limpieza (matriz potencia×función si los cleanModes la forman,
/// lista cruda si no) · habitaciones y potencia de succión (solo cuando el
/// sidecar los publica en el estado).
class VacuumScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;

  const VacuumScreen({super.key, required this.device, required this.service});

  @override
  State<VacuumScreen> createState() => _VacuumScreenState();
}

class _VacuumScreenState extends State<VacuumScreen> {
  /// Selección local de habitaciones (segmentIds) para cleanRooms.
  final Set<int> _selectedRooms = <int>{};
  bool _sendingRooms = false;

  Device get _device =>
      widget.service.byId(widget.device.id) ?? widget.device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) {
            final d = _device;
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _shell(d),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Carcasa canónica (misma receta que soundbar/tv/termostato).
  Widget _shell(Device d) {
    final sections = <Widget>[
      if (!d.state.reachable) ...[
        const _OfflineBanner(),
        const SizedBox(height: 22),
      ],
      _StateBlock(device: d, service: widget.service),
      const SizedBox(height: 22),
      _metrics(d),
      const SizedBox(height: 22),
      _transport(d),
      ..._modeSection(d),
      ..._roomsSection(d),
      ..._fanSection(d),
      const SizedBox(height: 22),
      const _Wordmark('ROBOROCK QREVO'),
    ];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(10, 10)),
          BoxShadow(color: Color(0x402A2D37), blurRadius: 20, offset: Offset(-6, -6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      ),
    );
  }

  // ── Métricas: wells hundidos (batería / modo) ─────────────────────────────

  Widget _metrics(Device d) {
    final matrix = VacuumModeMatrix.tryBuild(d.state.cleanModes);
    final parts = matrix?.split(d.state.cleanMode);
    final metrics = <Widget>[
      _Metric(
        svg: CceIcons.batteryMedium,
        value: d.state.battery != null ? '${d.state.battery}%' : '—',
        label: 'BATERÍA',
      ),
      _Metric(
        svg: CceIcons.gauge,
        // Sin matriz o sin modo conocido no se inventa nada: '—' (el modo
        // compuesto entero es ilegible en un well de 1/3 de ancho).
        value: parts != null ? vacuumPowerLabel(parts.power) : '—',
        label: 'POTENCIA',
      ),
      _Metric(
        svg: CceIcons.robotVacuum,
        value: parts != null ? vacuumFunctionLabel(parts.function) : '—',
        label: 'FUNCIÓN',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final gap = c.maxWidth < 360 ? 8.0 : 12.0;
        final children = <Widget>[];
        for (var i = 0; i < metrics.length; i++) {
          if (i > 0) children.add(SizedBox(width: gap));
          children.add(Expanded(child: metrics[i]));
        }
        // OJO: sin CrossAxisAlignment.stretch (Row dentro de scroll ilimitado).
        return Row(children: children);
      },
    );
  }

  // ── Transporte contextual ────────────────────────────────────────────────

  Widget _transport(Device d) {
    final s = d.state.vacuumState;
    final canClean = s != 'cleaning' && s != 'returning';
    final canPause = s == 'cleaning' || s == 'returning';
    final canResume = s == 'paused';
    final canDock = s != 'docked' && s != 'returning';

    Widget key(String svg, String label, bool enabled, String verb) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceNeoSvgIconButton(
            svg: svg,
            size: 56,
            onPressed: enabled
                ? () => widget.service.vacuumCommand(d, verb)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: enabled ? CceColors.textSecondary : CceColors.textTertiary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('CONTROLES'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            key(CceIcons.play, 'Limpiar', canClean, 'clean'),
            key(CceIcons.pause, 'Pausar', canPause, 'pause'),
            key(CceIcons.stepForward, 'Reanudar', canResume, 'resume'),
            key(CceIcons.allHouse, 'A la base', canDock, 'dock'),
          ],
        ),
      ],
    );
  }

  // ── Modo de limpieza: matriz potencia×función o lista cruda ──────────────

  List<Widget> _modeSection(Device d) {
    final modes = d.state.cleanModes;
    if (modes == null || modes.isEmpty) return const [];
    final matrix = VacuumModeMatrix.tryBuild(modes);

    if (matrix == null) {
      // Modos que no forman matriz: selector crudo vía bottom sheet (labels
      // REALES del robot, mismo criterio que el Dashboard).
      return [
        const SizedBox(height: 22),
        const _SectionLabel('MODO DE LIMPIEZA'),
        const SizedBox(height: 12),
        _ModePickerRow(
          current: d.state.cleanMode ?? modes.first,
          onTap: () => _showRawModeSheet(d, modes),
        ),
      ];
    }

    final parts = matrix.split(d.state.cleanMode);
    if (parts == null) {
      // cleanMode aún desconocido (estado parcial temprano) o fuera de la
      // matriz: los segmented fingirían una selección y un tap compondría con
      // esa mitad fantasma. Se ofrece el picker crudo, que no inventa nada.
      return [
        const SizedBox(height: 22),
        const _SectionLabel('MODO DE LIMPIEZA'),
        const SizedBox(height: 12),
        _ModePickerRow(
          current: d.state.cleanMode ?? '—',
          onTap: () => _showRawModeSheet(d, modes),
        ),
      ];
    }
    final power = parts.power;
    final function = parts.function;

    return [
      const SizedBox(height: 22),
      const _SectionLabel('MODO DE LIMPIEZA'),
      const SizedBox(height: 12),
      CceSegmented<String>(
        neo: true,
        value: power,
        segments: [
          for (final p in matrix.powers)
            CceSegment(value: p, label: vacuumPowerLabel(p)),
        ],
        onChanged: (p) => widget.service
            .setVacuumCleanMode(d, matrix.compose(p, function)),
      ),
      const SizedBox(height: 10),
      CceSegmented<String>(
        neo: true,
        value: function,
        segments: [
          for (final f in matrix.functions)
            CceSegment(value: f, label: vacuumFunctionLabel(f)),
        ],
        onChanged: (f) =>
            widget.service.setVacuumCleanMode(d, matrix.compose(power, f)),
      ),
    ];
  }

  void _showRawModeSheet(Device device, List<String> fallbackModes) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CceColors.neoBase,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      // Reactivo: re-resuelve el device por id en cada notify para no mostrar
      // un cleanMode/lista stale si el estado cambia con el sheet abierto.
      builder: (sheetCtx) => AnimatedBuilder(
        animation: widget.service,
        builder: (context, _) {
          final d = widget.service.byId(device.id) ?? device;
          final modes = d.state.cleanModes ?? fallbackModes;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Center(child: Text('Modo de limpieza', style: CceText.title)),
                const SizedBox(height: 10),
                for (final m in modes)
                  ListTile(
                    title: Text(
                      m,
                      style: TextStyle(
                        color: m == d.state.cleanMode
                            ? CceColors.info
                            : CceColors.textPrimary,
                        fontWeight: m == d.state.cleanMode
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: m == d.state.cleanMode
                        ? const Icon(Icons.check, color: CceColors.info, size: 20)
                        : null,
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      widget.service.setVacuumCleanMode(d, m);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Habitaciones (sidecar): chips multi-select + limpiar seleccionadas ───

  List<Widget> _roomsSection(Device d) {
    final rooms = d.state.rooms;
    if (rooms == null || rooms.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      const _SectionLabel('LIMPIAR HABITACIONES'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in rooms)
            _VacChip(
              label: r.name,
              selected: _selectedRooms.contains(r.segmentId),
              onTap: () => setState(() {
                if (!_selectedRooms.remove(r.segmentId)) {
                  _selectedRooms.add(r.segmentId);
                }
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      CceNeoActionButton(
        label: _sendingRooms ? 'Enviando…' : 'Limpiar seleccionadas',
        onPressed: _selectedRooms.isEmpty || _sendingRooms
            ? null
            : () => _cleanSelectedRooms(d),
      ),
    ];
  }

  Future<void> _cleanSelectedRooms(Device d) async {
    setState(() => _sendingRooms = true);
    final ok = await widget.service
        .cleanVacuumRooms(d, _selectedRooms.toList()..sort());
    if (!mounted) return;
    setState(() {
      _sendingRooms = false;
      if (ok) _selectedRooms.clear();
    });
    if (!ok) showAppError('No se pudo limpiar las habitaciones');
  }

  // ── Potencia de succión (sidecar): chips single-select ───────────────────

  List<Widget> _fanSection(Device d) {
    final speeds = d.state.fanSpeeds;
    if (speeds == null || speeds.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      const _SectionLabel('POTENCIA DE SUCCIÓN'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in speeds)
            _VacChip(
              label: s,
              selected: s == d.state.fanSpeed,
              onTap: () => widget.service.setVacuumFanSpeed(d, s),
            ),
        ],
      ),
    ];
  }
}

// ── Label de sección (patrón 'FUENTES' del soundbar) ──────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: CceText.section);
  }
}

// ── Estado grande: disco cóncavo + glow del color de estado ────────────────

class _StateBlock extends StatelessWidget {
  final Device device;
  final DevicesService service;

  const _StateBlock({required this.device, required this.service});

  @override
  Widget build(BuildContext context) {
    final color = VacuumTile.stateColor(device);
    final label = vacuumStateLabel(device) ?? 'Sin estado';
    final active = VacuumTile.statePulse(device);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(28),
        boxShadow: CceShadows.neo(blur: 16, offset: 6),
      ),
      child: Column(
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.concave(CceColors.neoBase),
              boxShadow: [
                ...CceShadows.plato(blur: 15, offset: 6),
                ...CceShadows.glowDot(color),
              ],
            ),
            child: Center(
              child: CceIcon(
                CceIcons.robotVacuum,
                size: 56,
                color: color,
                emboss: false,
              ),
            ),
          ),
          const SizedBox(height: 18),
          // FittedBox anti-wrap (canon lock_screen): 'Volviendo a la base' con
          // textScale grande en un teléfono angosto no debe partirse en dos.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: color,
                  shadows: [
                    Shadow(color: color.withValues(alpha: 0.65), blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusDot(color, pulse: active, semanticLabel: label),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    service.displayName(device),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CceColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Well de métrica (mismo patrón que lock_screen._Metric) ────────────────

class _Metric extends StatelessWidget {
  final String svg;
  final String value;
  final String label;

  const _Metric({required this.svg, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(16),
        boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(svg, size: 22, color: CceColors.textSecondary, emboss: false),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CceColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: CceColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chip seleccionable (habitaciones / potencia) ──────────────────────────

class _VacChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VacChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CceNeoPress(
      onTap: onTap,
      builder: (context, t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          gradient: selected ? null : CceGradients.convex(CceColors.neoBase),
          borderRadius: BorderRadius.circular(CceRadii.pill),
          // Seleccionado = hundido (inset); libre = convexo raised.
          boxShadow: selected
              ? CceShadows.neoInset(blur: 6, offset: 2)
              : CceShadows.neo(blur: 8, offset: 3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? CceColors.info : CceColors.textSecondary,
            shadows: selected
                ? [
                    Shadow(
                      color: CceColors.info.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

// ── Fila de modo crudo (fallback sin matriz) ───────────────────────────────

class _ModePickerRow extends StatelessWidget {
  final String current;
  final VoidCallback onTap;

  const _ModePickerRow({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CceNeoPress(
      onTap: onTap,
      builder: (context, t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.control),
          boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CceColors.textPrimary,
                ),
              ),
            ),
            CceIcon(
              CceIcons.chevronDown,
              size: 18,
              color: CceColors.textTertiary,
              emboss: false,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Banner sin conexión (patrón _OfflineBanner del TV) ─────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(CceRadii.control),
        boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
      ),
      child: const Row(
        children: [
          StatusDot(CceColors.textTertiary, semanticLabel: 'Sin conexión'),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sin conexión',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CceColors.textSecondary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'El robot está inalcanzable. Los comandos pueden fallar '
                  'hasta que vuelva a estar en línea.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: CceColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Wordmark de pie (patrón lock/tv) ──────────────────────────────────────

class _Wordmark extends StatelessWidget {
  final String text;

  const _Wordmark(this.text);

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
            Shadow(color: Color(0x80FFFFFF), offset: Offset(-1, -1.2), blurRadius: 1.5),
            Shadow(color: Color(0xD907080C), offset: Offset(1.4, 2), blurRadius: 3),
          ],
        ),
      ),
    );
  }
}
