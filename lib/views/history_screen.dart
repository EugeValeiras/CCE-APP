import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../models/event_record.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../utils/time_format.dart';
import 'history/event_grouping.dart';
import 'history/event_presenter.dart';

enum HistoryFilter { all, lights, sensors, automations, alarm }

extension _HistoryFilterX on HistoryFilter {
  String get label {
    switch (this) {
      case HistoryFilter.all: return 'Todos';
      case HistoryFilter.lights: return 'Luces';
      case HistoryFilter.sensors: return 'Sensores';
      case HistoryFilter.automations: return 'Automatizaciones';
      case HistoryFilter.alarm: return 'Alarma';
    }
  }

  /// Matches an event to a filter by eventName/payload.
  bool accepts(EventRecord e) {
    switch (this) {
      case HistoryFilter.all: return true;
      case HistoryFilter.lights:
        // Any state change with light-relevant fields — lights may co-emit an
        // empty sensor object so we don't filter on sensor presence.
        final state = e.payload?['state'];
        return (e.eventName == 'device:state-changed' || e.eventName == 'light:changed') &&
            state is Map &&
            (state.containsKey('on') ||
                state.containsKey('bri') ||
                state.containsKey('hue') ||
                state.containsKey('sat') ||
                state.containsKey('ct'));
      case HistoryFilter.sensors:
        final s = e.payload?['sensor'];
        return (e.eventName == 'device:state-changed' || e.eventName == 'light:changed') &&
            s is Map &&
            s.isNotEmpty;
      case HistoryFilter.automations:
        return e.eventName.startsWith('automation:');
      case HistoryFilter.alarm:
        return e.eventName.startsWith('alarm:');
    }
  }
}

/// Entrada de la lista renderizada: header de día o grupo de eventos.
class _Entry {
  _Entry.header(this.headerLabel) : group = null;
  _Entry.group(this.group) : headerLabel = null;

  final String? headerLabel;
  final EventGroup? group;
}

class HistoryScreen extends StatefulWidget {
  final ServerConfig config;
  final DevicesService devices;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ el
  /// historial del tablet queda idéntico.
  final bool neo;
  const HistoryScreen({
    super.key,
    required this.config,
    required this.devices,
    this.neo = false,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ApiService _api;
  final List<EventRecord> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _eventsEnabled = true;
  String? _cursor;
  HistoryFilter _filter = HistoryFilter.all;
  bool _liveMode = false;
  StreamSubscription<LiveEvent>? _liveSub;
  Timer? _ticker;
  final _scroll = ScrollController();

  /// IDs (del evento más reciente del grupo) expandidos inline.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.config);
    _scroll.addListener(_onScroll);
    // Ticker de 30 s: re-renderiza los tiempos relativos ("hace 5 min").
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _items.isNotEmpty) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _liveSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleLive() {
    setState(() {
      _liveMode = !_liveMode;
    });
    if (_liveMode) {
      _liveSub = widget.devices.socket.onLiveEvent.listen(_onLiveEvent);
    } else {
      _liveSub?.cancel();
      _liveSub = null;
    }
  }

  void _onLiveEvent(LiveEvent ev) {
    if (!mounted) return;
    final rec = EventRecord(
      // ev.time es DateTime.now() LOCAL: sin .toUtc() el ISO sale sin 'Z' y
      // parseEventTime lo reinterpreta como UTC (evento "hace 180 min").
      time: ev.time.toUtc().toIso8601String(),
      id: 'live-${ev.time.microsecondsSinceEpoch}',
      channel: 'websocket',
      eventName: ev.eventName,
      source: null,
      globalId: (ev.payload['deviceId'] ?? ev.payload['lightId']) as String?,
      provider: null,
      payload: ev.payload,
    );
    setState(() {
      _items.insert(0, rec);
      if (_items.length > 800) {
        _items.removeRange(800, _items.length);
      }
    });
  }

  void _clearItems() {
    setState(() {
      _items.clear();
      _expanded.clear();
      _cursor = null;
      _hasMore = false;
    });
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _items.clear();
      _expanded.clear();
      _cursor = null;
      _hasMore = true;
    });
    try {
      final page = await _api.getEvents(limit: 150);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _eventsEnabled = page.enabled;
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _cursor == null) return;
    setState(() => _loading = true);
    try {
      final page = await _api.getEvents(limit: 150, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// Pipeline: items → filtro → grupos adyacentes → headers de día.
  List<_Entry> _buildEntries() {
    final filtered = _items.where(_filter.accepts).toList();
    final groups = groupEvents(filtered, widget.devices);
    final out = <_Entry>[];
    String? currentDay;
    final now = DateTime.now();
    for (final g in groups) {
      final label = TimeFormat.dayLabel(g.latest.timestamp, now: now);
      if (label != currentDay) {
        currentDay = label;
        out.add(_Entry.header(label));
      }
      out.add(_Entry.group(g));
    }
    return out;
  }

  void _toggleExpanded(EventGroup g) {
    setState(() {
      final id = g.latest.id;
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  Widget _buildFilters() {
    // Diseño glass: chips scrolleables SIEMPRE (phone y tablet), con glow en
    // el chip activo. La lista de filtros (incl. 'Alarma') no se altera.
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: HistoryFilter.values.map((f) {
          final selected = f == _filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DecoratedBox(
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: _Glass.accent.withValues(alpha: 0.40),
                          blurRadius: 14,
                        ),
                      ],
                    )
                  : const BoxDecoration(),
              child: ChoiceChip(
                label: Text(f.label),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f),
                shape: const StadiumBorder(),
                backgroundColor: _Glass.glassFill,
                selectedColor: _Glass.accent.withValues(alpha: 0.22),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : _Glass.textMuted,
                  fontWeight: FontWeight.w600,
                ),
                side: selected
                    ? const BorderSide(color: _Glass.accent, width: 1.2)
                    : const BorderSide(color: _Glass.glassBorder),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmpty() {
    if (_loading) {
      return const SizedBox(
        height: 400,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _Glass.accentBright),
          ),
        ),
      );
    }
    if (!_eventsEnabled && _items.isEmpty) {
      return _EmptyState(
        icon: CceIcon(CceIcons.history,
            size: 48, color: _Glass.accent.withValues(alpha: 0.5)),
        title: 'El historial está desactivado en el servidor',
        caption: 'Activá la página de eventos en la configuración del '
            'servidor para ver la actividad de la casa.',
      );
    }
    if (_items.isEmpty) {
      return _EmptyState(
        icon: CceIcon(CceIcons.history,
            size: 48, color: _Glass.accent.withValues(alpha: 0.5)),
        title: 'Sin actividad todavía',
        caption: 'Los eventos de luces, sensores, automatizaciones y alarma '
            'van a aparecer acá.',
      );
    }
    // Hay eventos pero el filtro no matchea ninguno.
    return _EmptyState(
      icon: CceIcon(CceIcons.history,
          size: 48, color: _Glass.accent.withValues(alpha: 0.5)),
      title: 'Sin eventos de ${_filter.label.toLowerCase()} hoy',
      action: TextButton(
        style: TextButton.styleFrom(foregroundColor: _Glass.accentBright),
        onPressed: () => setState(() => _filter = HistoryFilter.all),
        child: const Text('Ver todos'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    final neo = widget.neo;
    return Scaffold(
      backgroundColor: _Glass.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const Text(
              'Historial',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            if (_liveMode) ...[
              const SizedBox(width: 10),
              const _LivePulse(),
            ],
          ],
        ),
        actions: [
          _LiveToggleButton(enabled: _liveMode, onTap: _toggleLive),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _GlassIconButton(
              icon: Icons.delete_sweep_outlined,
              tooltip: 'Limpiar',
              color: _items.isEmpty
                  ? Colors.white.withValues(alpha: 0.20)
                  : _Glass.iconBtn,
              onPressed: _items.isEmpty ? null : _clearItems,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: _GlassIconButton(
              icon: Icons.refresh,
              tooltip: 'Recargar',
              color: _Glass.iconBtn,
              onPressed: _refresh,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.35, -1.1),
                  radius: 1.25,
                  colors: [
                    _Glass.glowColor.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.9, 1.0),
                  radius: 1.0,
                  colors: [
                    _Glass.glowColor2.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              _buildFilters(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: _Glass.accentBright,
                  backgroundColor: const Color(0xFF12161F),
                  child: entries.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [_buildEmpty()],
                        )
                      : ListView.separated(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: entries.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, idx) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i >= entries.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _Glass.accentBright),
                                  ),
                                ),
                              );
                            }
                            final entry = entries[i];
                            final header = entry.headerLabel;
                            if (header != null) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 16, 4, 4),
                                child: Text(
                                  header.toUpperCase(),
                                  style: const TextStyle(
                                    color: _Glass.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              );
                            }
                            final g = entry.group!;
                            return _GroupRow(
                              group: g,
                              devices: widget.devices,
                              expanded: _expanded.contains(g.latest.id),
                              onToggleExpand: () => _toggleExpanded(g),
                              neo: neo,
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila de grupo: presentación humanizada + pill ×N + chevron expandible.
class _GroupRow extends StatelessWidget {
  final EventGroup group;
  final DevicesService devices;
  final bool expanded;
  final VoidCallback onToggleExpand;

  final bool neo;

  const _GroupRow({
    required this.group,
    required this.devices,
    required this.expanded,
    required this.onToggleExpand,
    this.neo = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = presentGroup(group, devices);
    final isLive = group.latest.id.startsWith('live-');
    final grouped = group.count > 1;

    // Color del badge/pill: respeta el color semántico del presenter (danger,
    // ok, warm, info, motion, contact, …) y sólo cae a azul glass cuando el
    // presenter usó un tono neutro/genérico (sin semántica de estado).
    final bool semantic =
        r.color != CceColors.textTertiary && r.color != CceColors.textSecondary;
    final Color c = semantic ? r.color : _Glass.accent;

    // Glass simulado por fila (sin BackdropFilter en lista larga): fondo
    // translúcido + borde acento + sombra. La sombra va FUERA del clip.
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Glass.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: _Glass.cardShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_Glass.cardRadius),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: grouped ? onToggleExpand : null,
            child: Container(
              decoration: BoxDecoration(
                color: _Glass.cardFill,
                border: Border.all(color: _Glass.cardBorder, width: 1.0),
                borderRadius: BorderRadius.circular(_Glass.cardRadius),
              ),
              padding: const EdgeInsets.all(16),
              child: _buildBody(c, r, isLive, grouped),
            ),
          ),
        ),
      ),
    );
    return card;
  }

  Widget _buildBody(
    Color c,
    EventPresentation r,
    bool isLive,
    bool grouped,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.withValues(alpha: 0.16),
                border: Border.all(
                  color: c.withValues(alpha: 0.45),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(color: c, size: 22),
                    child: r.icon,
                  ),
                ),
              ),
            ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        if (grouped) ...[
                          const SizedBox(width: 6),
                          _CountPill(count: group.count, color: c),
                        ],
                      ],
                    ),
                    if (r.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        r.subtitle!,
                        style: const TextStyle(
                            color: _Glass.textMuted, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLive) ...[
                const StatusDot(_Glass.accentBright,
                    size: 6, pulse: true, semanticLabel: 'En vivo'),
                const SizedBox(width: 6),
              ],
              Text(
                TimeFormat.relative(group.latest.timestamp),
                style: const TextStyle(
                    color: _Glass.accentBright,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              if (grouped) ...[
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const CceIcon(CceIcons.chevronDown,
                      size: 16, color: _Glass.textMuted),
                ),
              ],
            ],
          ),
          if (grouped && expanded) ...[
            const SizedBox(height: 8),
            for (final e in group.events)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        presentEvent(e, devices).title,
                        style: const TextStyle(
                            color: _Glass.textMuted, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TimeFormat.hms(e.timestamp),
                      style: const TextStyle(
                          color: _Glass.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
  }
}

/// Pill ×N (20 px, fondo color@0.18, texto 11 px w700).
class _CountPill extends StatelessWidget {
  final int count;
  final Color color;
  const _CountPill({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(CceRadii.pill),
      ),
      child: Text(
        '×$count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? caption;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.caption,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.90),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _Glass.textMuted, fontSize: 13),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveToggleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _LiveToggleButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: enabled ? 'Pausar vivo' : 'Ver en vivo',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _Glass.accent.withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CceRadii.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(CceRadii.pill),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: enabled
                        ? _Glass.accent.withValues(alpha: 0.22)
                        : _Glass.glassFill,
                    borderRadius: BorderRadius.circular(CceRadii.pill),
                    border: Border.all(
                      color: enabled ? _Glass.accent : _Glass.glassBorder,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        enabled
                            ? Icons.fiber_manual_record
                            : Icons.play_circle_outline,
                        color:
                            enabled ? _Glass.accentBright : _Glass.textMuted,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: enabled ? Colors.white : _Glass.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(_Glass.accent, _Glass.accentBright, v),
            boxShadow: [
              BoxShadow(
                color: _Glass.accent.withValues(alpha: 0.4 + v * 0.4),
                blurRadius: 8 + v * 6,
                spreadRadius: 1 + v * 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tokens glass-azul AUTOCONTENIDOS de esta pantalla. No tocan cce_tokens ni
/// afectan otras vistas. Mantener todo privado a history_screen.dart.
class _Glass {
  _Glass._();

  // FONDO
  static const Color bgBase = Color(0xFF080A12);
  static const Color glowColor = Color(0xFF16386B);
  static const Color glowColor2 = Color(0xFF0E2247);

  // ACCENT
  static const Color accent = Color(0xFF3D8BFF);
  static const Color accentBright = Color(0xFF5BA0FF);

  // TEXTO
  static const Color textMuted = Color(0xFF8A93A6); // subtítulos / inactivo
  static const Color iconBtn = Color(0xFFB6BEC8); // íconos botón glass

  // CARD
  static const double cardRadius = 22;
  static const Color cardFill = Color(0x0BFFFFFF); // white @ ~0.045
  static const Color cardBorder = Color(0x293D8BFF); // accent @ ~0.16
  static const Color cardShadow = Color(0x59000000); // black @ ~0.35

  // GLASS NEUTRO (chips / botones / live inactivo)
  static const Color glassFill = Color(0x0DFFFFFF); // white @ 0.05
  static const Color glassBorder = Color(0x1AFFFFFF); // white @ 0.10
  static const Color glassBorderThin = Color(0x14FFFFFF); // white @ 0.08
}

/// Botón circular glass para los actions del AppBar (limpiar / refresh).
/// Usa BackdropFilter real porque son 1-3 instancias únicas (no por fila).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _Glass.glassFill,
            border: Border.all(color: _Glass.glassBorderThin),
          ),
          child: IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: Icon(icon, color: color),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
