import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/app_messenger.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
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

  /// Línea entre el mapa y los controles. Tres cosas, por prioridad:
  ///  1. Si hay una cola en curso: en qué habitación va y cuántas faltan.
  ///  2. Si elegiste habitaciones: cuáles.
  ///  3. Si no: qué se puede hacer.
  ///
  /// El progreso de la cola (`roomQueue`) y la habitación en curso
  /// (`vacuumRoomName`) los publicaba el backend desde siempre y la app nunca
  /// los mostró: mientras el robot limpiaba por habitaciones, la pantalla se
  /// veía igual que en reposo.
  Widget _selectionLine(Device d) {
    final rooms = d.state.rooms ?? const <VacuumRoom>[];
    if (rooms.isEmpty) return const SizedBox.shrink();

    final q = d.state.roomQueue;
    final live = d.state.vacuumRoomName;

    String text;
    Color color;
    if (q != null) {
      final total = q.segments.length;
      final idx = (q.current + 1).clamp(1, total);
      final name = q.currentSegment != null
          ? rooms
              .where((r) => r.segmentId == q.currentSegment)
              .map((r) => r.name)
              .firstOrNull
          : null;
      text = name != null
          ? 'Limpiando $name · $idx de $total'
          : 'Limpiando · $idx de $total';
      color = CceColors.accent;
    } else if (live != null && live.isNotEmpty) {
      text = 'Limpiando $live';
      color = CceColors.accent;
    } else if (_selectedRooms.isNotEmpty) {
      text = [
        for (final r in rooms)
          if (_selectedRooms.contains(r.segmentId)) r.name,
      ].join(' · ');
      color = CceColors.accent;
    } else {
      text = 'Tocá una habitación en el plano';
      color = CceColors.textTertiary;
    }

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.caption.copyWith(color: color),
            ),
          ),
          // Mantenimiento: sólo aparece cuando algo está por debajo del 20%.
          // No es un panel permanente — es un aviso que sale cuando sirve.
          if (_lowestConsumable(d) != null)
            GestureDetector(
              onTap: () => _showMaintenance(d),
              child: Row(
                children: [
                  const Icon(Icons.build_outlined,
                      size: 13, color: CceColors.contact),
                  SizedBox(width: CceSpace.xs),
                  Text(
                    'Mantenimiento',
                    style: CceText.caption.copyWith(color: CceColors.contact),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Consumible más gastado, si alguno bajó del 20%.
  MapEntry<String, int>? _lowestConsumable(Device d) {
    final c = d.state.consumables;
    if (c == null || c.isEmpty) return null;
    MapEntry<String, int>? worst;
    for (final e in c.entries) {
      if (worst == null || e.value < worst.value) worst = e;
    }
    return (worst != null && worst.value <= 20) ? worst : null;
  }

  static const _consumableNames = {
    'mainBrush': 'Cepillo principal',
    'sideBrush': 'Cepillo lateral',
    'filter': 'Filtro',
    'sensor': 'Sensores',
  };

  void _showMaintenance(Device device) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CceColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (_) => AnimatedBuilder(
        animation: widget.service,
        builder: (context, __) {
          final d = widget.service.byId(device.id) ?? device;
          final c = d.state.consumables ?? const <String, int>{};
          final total = d.state.cleanSummary?['count'];
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                CceSpace.lg,
                0,
                CceSpace.lg,
                CceSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mantenimiento', style: CceText.title),
                  if (total != null) ...[
                    SizedBox(height: CceSpace.xs),
                    Text('${total.round()} limpiezas completadas',
                        style: CceText.caption),
                  ],
                  SizedBox(height: CceSpace.lg),
                  for (final e in c.entries) ...[
                    _ConsumableRow(
                      label: _consumableNames[e.key] ?? e.key,
                      pct: e.value,
                      onReset: () => widget.service.resetVacuumConsumable(d, e.key),
                    ),
                    SizedBox(height: CceSpace.md),
                  ],
                ],
              ),
            ),
          );
        },
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
        _IconPicker(
          value: parts.power,
          options: [
            for (final p in matrix.powers)
              _PickerOption(
                value: p,
                label: vacuumPowerLabel(p),
                svg: _powerIcon(vacuumPowerLabel(p)),
              ),
          ],
          onChanged: (p) => widget.service
              .setVacuumCleanMode(d, matrix.compose(p, parts.function)),
        ),
        SizedBox(height: CceSpace.sm),
        _IconPicker(
          value: parts.function,
          options: [
            for (final f in matrix.functions)
              _PickerOption(
                value: f,
                label: vacuumFunctionLabel(f),
                svg: _functionIcon(vacuumFunctionLabel(f)),
              ),
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

    final queue = d.state.roomQueue;

    final String primaryLabel;
    final VoidCallback? primaryTap;
    if (_sending) {
      primaryLabel = 'Enviando…';
      primaryTap = null;
    } else if (queue != null) {
      // Con una cola en curso lo que hace falta es poder frenarla: el backend
      // ya tenía el verbo y la app no lo usaba, así que una vez lanzadas seis
      // habitaciones no había forma de cancelar sin mandarlo a la base.
      primaryLabel = 'Cancelar limpieza';
      primaryTap =
          enabled ? () => widget.service.cancelVacuumRoomQueue(d) : null;
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

/// Ícono por nivel de potencia. Sigue la convención de la app de Roborock:
/// luna para el modo silencioso, y de ahí para arriba más "energía".
String _powerIcon(String label) {
  switch (label) {
    case 'Silencioso':
      return CceIcons.moon;
    case 'Profundo':
      return CceIcons.sun;
    default:
      return CceIcons.gauge;
  }
}

/// Ícono por función: aspira, trapea, o las dos cosas.
String _functionIcon(String label) {
  switch (label) {
    case 'Trapear':
      return CceIcons.droplet;
    case 'Ambos':
      return CceIcons.scenes;
    default:
      return CceIcons.robotVacuum;
  }
}

// ── Piezas ─────────────────────────────────────────────────────────────────

class _PickerOption {
  final String value;
  final String label;
  final String svg;
  const _PickerOption({
    required this.value,
    required this.label,
    required this.svg,
  });
}

/// Selector de opciones con ÍCONO + etiqueta.
///
/// Reemplaza al segmented de texto plano, donde las tres opciones eran tres
/// palabras del mismo peso y había que leerlas para saber cuál era cuál. Con
/// un glyph por opción se reconocen de un vistazo —que es como se usa esto:
/// mirando de reojo mientras el robot ya está andando— y además se parece a lo
/// que la app de Roborock enseñó a leer.
class _IconPicker extends StatelessWidget {
  final String value;
  final List<_PickerOption> options;
  final ValueChanged<String> onChanged;

  const _IconPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: CceSpace.sm),
          Expanded(child: _tile(options[i])),
        ],
      ],
    );
  }

  Widget _tile(_PickerOption o) {
    final selected = o.value == value;
    return Material(
      color: selected ? CceColors.accentWash : CceColors.surface,
      borderRadius: BorderRadius.circular(CceRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged(o.value);
              },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: CceSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CceRadii.control),
            border: Border.all(
              color: selected ? CceColors.accent : CceColors.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CceIcon(
                o.svg,
                size: 22,
                color: selected ? CceColors.accent : CceColors.textTertiary,
                emboss: false,
              ),
              SizedBox(height: CceSpace.xs),
              Text(
                o.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CceText.label.copyWith(
                  color: selected ? CceColors.accent : CceColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Una pieza consumible con su vida útil y el botón para reiniciarla.
///
/// El color de la barra es el semántico del sistema: ámbar de "algo pasa" por
/// debajo del 20%, rojo por debajo del 10%.
class _ConsumableRow extends StatelessWidget {
  final String label;
  final int pct;
  final VoidCallback onReset;

  const _ConsumableRow({
    required this.label,
    required this.pct,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = (pct / 100).clamp(0.0, 1.0);
    final color = pct <= 10
        ? CceColors.danger
        : (pct <= 20 ? CceColors.contact : CceColors.accent);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: CceText.label)),
                  Text('$pct%',
                      style: CceText.data.copyWith(fontSize: 13, color: color)),
                ],
              ),
              SizedBox(height: CceSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(CceRadii.pill),
                child: LinearProgressIndicator(
                  value: t,
                  minHeight: 6,
                  backgroundColor: CceColors.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: CceSpace.md),
        TextButton(
          onPressed: onReset,
          child: Text('Reiniciar',
              style: CceText.label.copyWith(color: CceColors.accent)),
        ),
      ],
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
