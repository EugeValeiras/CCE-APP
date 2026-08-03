import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/app_messenger.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_segmented.dart';
import '../utils/vacuum_modes.dart';
import '../utils/vacuum_state.dart';
import '../widgets/vacuum_map_view.dart';
import '../widgets/vacuum_tile.dart';

/// Pantalla del robot aspiradora (Roborock Qrevo vía Matter RVC + sidecar).
///
/// EL MAPA ES LA PANTALLA. Ocupa todo el espacio que sobra y es además el
/// selector de habitaciones: se tocan las piezas del plano para elegir dónde
/// limpiar. Alrededor hay lo mínimo — una barra de estado arriba y un panel de
/// control abajo — y nada de eso hace scroll.
///
/// La versión anterior era una pila vertical donde el mapa entraba último,
/// después del estado, las métricas, el transporte y los modos: para verlo
/// había que scrollear hasta el fondo, y llegaba recortado. Además duplicaba
/// tres cosas:
///
///  - Las habitaciones estaban en el mapa Y en una lista de chips con los
///    mismos nueve nombres. El plano es el selector natural: dice dónde queda
///    cada ambiente, cosa que una lista de nombres no puede.
///  - La potencia estaba en "MODO DE LIMPIEZA" (matriz traducida) Y en
///    "POTENCIA DE SUCCIÓN" (`fanSpeeds` crudos del robot, en inglés y con
///    "Max+" repetido). Son dos APIs para lo mismo: ahora manda la matriz, y
///    los fanSpeeds sólo aparecen si el robot no publica matriz.
///  - Las métricas de arriba (POTENCIA / FUNCIÓN) repetían el valor que ya
///    mostraban seleccionado los segmented de abajo.
class VacuumScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;

  const VacuumScreen({super.key, required this.device, required this.service});

  @override
  State<VacuumScreen> createState() => _VacuumScreenState();
}

class _VacuumScreenState extends State<VacuumScreen> {
  /// Selección de habitaciones (segmentIds) para cleanRooms.
  final Set<int> _selectedRooms = <int>{};
  bool _sending = false;

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) {
            final d = _device;
            return Column(
              children: [
                _header(d),
                if (!d.state.reachable) _offlineBanner(),
                // El mapa se queda con TODO el espacio sobrante.
                Expanded(child: _mapArea(d)),
                _controlPanel(d),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header: quién es, cómo está y cuánta batería le queda ────────────────

  Widget _header(Device d) {
    final color = VacuumTile.stateColor(d);
    final label = vacuumStateLabel(d) ?? 'Sin estado';
    final battery = d.state.battery;
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.sm, CceSpace.sm, CceSpace.lg, CceSpace.md),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: CceColors.textSecondary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.service.displayName(d),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.title,
                ),
                SizedBox(height: CceSpace.xs),
                // Estado y batería en UNA línea. Antes el estado era un disco
                // de 132px con glow que se comía un tercio de la pantalla para
                // decir una palabra.
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    SizedBox(width: CceSpace.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CceText.caption,
                      ),
                    ),
                    if (battery != null) ...[
                      Text(' · ', style: CceText.caption),
                      Text('$battery%', style: CceText.data.copyWith(
                        fontSize: 13,
                        color: CceColors.textSecondary,
                      )),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: CceSpace.lg),
      padding: EdgeInsets.symmetric(
        horizontal: CceSpace.md,
        vertical: CceSpace.sm,
      ),
      decoration: BoxDecoration(
        color: CceColors.surface,
        borderRadius: BorderRadius.circular(CceRadii.control),
        border: Border.all(color: CceColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: CceColors.danger),
          SizedBox(width: CceSpace.sm),
          Expanded(
            child: Text('Sin conexión con el robot', style: CceText.caption),
          ),
        ],
      ),
    );
  }

  // ── El mapa ──────────────────────────────────────────────────────────────

  Widget _mapArea(Device d) {
    final hasMap = d.hasCapability('vacuum_map');
    final rooms = d.state.rooms ?? const <VacuumRoom>[];

    if (!hasMap) {
      // Sin mapa el plano no puede ser el selector, así que las habitaciones
      // vuelven a ser una lista. Es el modo degradado, no el principal.
      return _roomListFallback(rooms);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: CceSpace.lg),
      child: Container(
        decoration: BoxDecoration(
          color: CceColors.surfaceSunken,
          borderRadius: BorderRadius.circular(CceRadii.card),
          border: Border.all(color: CceColors.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        // Nada superpuesto: el plano es información, y taparlo con un cartel
        // flotante escondía justo la habitación que estaba debajo. La pista de
        // uso y el conteo de selección viven en el panel de control.
        child: VacuumMapView(
          bare: true,
          device: d,
          service: widget.service,
          selectedSegments: _selectedRooms,
          onSegmentTap: (seg) => setState(() {
            HapticFeedback.selectionClick();
            if (!_selectedRooms.remove(seg)) _selectedRooms.add(seg);
          }),
        ),
      ),
    );
  }

  /// Línea entre el mapa y los controles: dice qué hacer cuando no elegiste
  /// nada, y qué elegiste cuando sí. Ocupa el mismo alto en los dos casos para
  /// que el panel no salte al tocar la primera habitación.
  Widget _selectionLine(Device d) {
    final rooms = d.state.rooms ?? const <VacuumRoom>[];
    if (rooms.isEmpty) return const SizedBox.shrink();
    final n = _selectedRooms.length;
    final names = [
      for (final r in rooms)
        if (_selectedRooms.contains(r.segmentId)) r.name,
    ];
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Expanded(
            child: Text(
              n == 0
                  ? 'Tocá una habitación en el plano'
                  : names.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.caption.copyWith(
                color: n == 0 ? CceColors.textTertiary : CceColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomListFallback(List<VacuumRoom> rooms) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(CceSpace.xl),
          child: Text(
            'El robot todavía no compartió el plano de la casa.',
            textAlign: TextAlign.center,
            style: CceText.caption,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: CceSpace.lg),
      child: Wrap(
        spacing: CceSpace.sm,
        runSpacing: CceSpace.sm,
        children: [
          for (final r in rooms)
            _RoomChip(
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
    );
  }

  // ── Panel de control ─────────────────────────────────────────────────────

  Widget _controlPanel(Device d) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        CceSpace.lg,
        CceSpace.lg,
        CceSpace.lg,
        CceSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _selectionLine(d),
          SizedBox(height: CceSpace.md),
          ..._modeControls(d),
          SizedBox(height: CceSpace.lg),
          _actions(d),
        ],
      ),
    );
  }

  /// Potencia y función. Una sola fuente: la matriz de `cleanModes` si el robot
  /// la publica; si no, los `fanSpeeds` crudos.
  List<Widget> _modeControls(Device d) {
    final modes = d.state.cleanModes;
    final matrix = modes == null || modes.isEmpty
        ? null
        : VacuumModeMatrix.tryBuild(modes);
    final parts = matrix?.split(d.state.cleanMode);

    if (matrix != null && parts != null) {
      return [
        CceSegmented<String>(
          value: parts.power,
          segments: [
            for (final p in matrix.powers)
              CceSegment(value: p, label: vacuumPowerLabel(p)),
          ],
          onChanged: (p) => widget.service
              .setVacuumCleanMode(d, matrix.compose(p, parts.function)),
        ),
        SizedBox(height: CceSpace.sm),
        CceSegmented<String>(
          value: parts.function,
          segments: [
            for (final f in matrix.functions)
              CceSegment(value: f, label: vacuumFunctionLabel(f)),
          ],
          onChanged: (f) => widget.service
              .setVacuumCleanMode(d, matrix.compose(parts.power, f)),
        ),
      ];
    }

    // Fallback: los fanSpeeds del robot. Se DEDUPLICAN — el Qrevo publica
    // "Max+" dos veces y la lista mostraba dos chips idénticos.
    final speeds = d.state.fanSpeeds;
    if (speeds == null || speeds.isEmpty) return const [];
    final unique = <String>[];
    for (final s in speeds) {
      if (!unique.contains(s)) unique.add(s);
    }
    return [
      Wrap(
        spacing: CceSpace.sm,
        runSpacing: CceSpace.sm,
        children: [
          for (final s in unique)
            _RoomChip(
              label: s,
              selected: s == d.state.fanSpeed,
              onTap: () => widget.service.setVacuumFanSpeed(d, s),
            ),
        ],
      ),
    ];
  }

  /// Acción principal + secundarias. El botón grande cambia según lo que
  /// tenga sentido hacer ahora: limpiar todo, limpiar lo seleccionado, o
  /// pausar si ya está limpiando.
  Widget _actions(Device d) {
    final s = d.state.vacuumState;
    final cleaning = s == 'cleaning' || s == 'returning';
    final paused = s == 'paused';
    final n = _selectedRooms.length;
    final enabled = d.state.reachable && !_sending;

    final String primaryLabel;
    final VoidCallback? primaryTap;
    if (_sending) {
      primaryLabel = 'Enviando…';
      primaryTap = null;
    } else if (cleaning) {
      primaryLabel = 'Pausar';
      primaryTap = enabled ? () => _command(d, 'pause') : null;
    } else if (paused) {
      primaryLabel = 'Reanudar';
      primaryTap = enabled ? () => _command(d, 'resume') : null;
    } else if (n > 0) {
      primaryLabel = n == 1 ? 'Limpiar 1 habitación' : 'Limpiar $n habitaciones';
      primaryTap = enabled ? () => _cleanSelected(d) : null;
    } else {
      primaryLabel = 'Limpiar todo';
      primaryTap = enabled ? () => _command(d, 'clean') : null;
    }

    return Row(
      children: [
        Expanded(
          child: _PrimaryButton(label: primaryLabel, onTap: primaryTap),
        ),
        SizedBox(width: CceSpace.sm),
        // "A la base" es secundaria: nunca es lo que venías a hacer, pero
        // tiene que estar a mano.
        _IconAction(
          svg: CceIcons.allHouse,
          tooltip: 'A la base',
          onTap: (enabled && s != 'docked' && s != 'returning')
              ? () => _command(d, 'dock')
              : null,
        ),
        if (n > 0) ...[
          SizedBox(width: CceSpace.sm),
          _IconAction(
            svg: CceIcons.close,
            tooltip: 'Quitar selección',
            onTap: () => setState(_selectedRooms.clear),
          ),
        ],
      ],
    );
  }

  void _command(Device d, String verb) {
    HapticFeedback.selectionClick();
    widget.service.vacuumCommand(d, verb);
  }

  Future<void> _cleanSelected(Device d) async {
    HapticFeedback.selectionClick();
    setState(() => _sending = true);
    final ok = await widget.service
        .cleanVacuumRooms(d, _selectedRooms.toList()..sort());
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _selectedRooms.clear();
    });
    if (!ok) showAppError('No se pudo limpiar las habitaciones');
  }
}

// ── Piezas ─────────────────────────────────────────────────────────────────

/// Acción principal de la pantalla: fill de acento, ancho completo.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? CceColors.accent : CceColors.surfaceHigh,
      borderRadius: BorderRadius.circular(CceRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CceText.headline.copyWith(
              color: enabled ? CceTint.inkOnPastel : CceColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Acción secundaria: cuadrada, del alto del botón principal.
class _IconAction extends StatelessWidget {
  final String svg;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconAction({
    required this.svg,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: CceColors.surface,
        borderRadius: BorderRadius.circular(CceRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CceRadii.control),
              border: Border.all(color: CceColors.stroke),
            ),
            child: CceIcon(
              svg,
              size: 20,
              color: enabled ? CceColors.textSecondary : CceColors.textMuted,
              emboss: false,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip de habitación (modo degradado) y de fanSpeed.
class _RoomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CceColors.accentWash : CceColors.surface,
      borderRadius: BorderRadius.circular(CceRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: CceSpace.md,
            vertical: CceSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CceRadii.pill),
            border: Border.all(
              color: selected ? CceColors.accent : CceColors.stroke,
            ),
          ),
          child: Text(
            label,
            style: CceText.label.copyWith(
              color: selected ? CceColors.accent : CceColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
