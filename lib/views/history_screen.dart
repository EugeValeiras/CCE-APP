import 'dart:async';
import 'package:flutter/material.dart';
import '../models/event_record.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_segmented.dart';
import '../theme/components/section_header.dart';
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
  const HistoryScreen({super.key, required this.config, required this.devices});

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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: CceSegmented<HistoryFilter>(
              value: _filter,
              segments: HistoryFilter.values
                  .map((f) => CceSegment(value: f, label: f.label))
                  .toList(),
              onChanged: (f) => setState(() => _filter = f),
            ),
          );
        }
        // Fallback angosto (phone): chips scrolleables.
        return SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: HistoryFilter.values.map((f) {
              final selected = f == _filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f),
                  shape: const StadiumBorder(),
                  backgroundColor: CceColors.surfaceHigh,
                  selectedColor: CceColors.accent.withValues(alpha: 0.24),
                  labelStyle: TextStyle(
                    color: selected
                        ? CceColors.textPrimary
                        : CceColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: selected ? CceColors.accent : CceColors.stroke,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
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
                strokeWidth: 2, color: CceColors.textTertiary),
          ),
        ),
      );
    }
    if (!_eventsEnabled && _items.isEmpty) {
      return _EmptyState(
        icon: const CceIcon(CceIcons.history,
            size: 48, color: CceColors.textTertiary),
        title: 'El historial está desactivado en el servidor',
        caption: 'Activá la página de eventos en la configuración del '
            'servidor para ver la actividad de la casa.',
      );
    }
    if (_items.isEmpty) {
      return _EmptyState(
        icon: const CceIcon(CceIcons.history,
            size: 48, color: CceColors.textTertiary),
        title: 'Sin actividad todavía',
        caption: 'Los eventos de luces, sensores, automatizaciones y alarma '
            'van a aparecer acá.',
      );
    }
    // Hay eventos pero el filtro no matchea ninguno.
    return _EmptyState(
      icon: const CceIcon(CceIcons.history,
          size: 48, color: CceColors.textTertiary),
      title: 'Sin eventos de ${_filter.label.toLowerCase()} hoy',
      action: TextButton(
        onPressed: () => setState(() => _filter = HistoryFilter.all),
        child: const Text('Ver todos'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Historial'),
            if (_liveMode) ...[
              const SizedBox(width: 10),
              const _LivePulse(),
            ],
          ],
        ),
        actions: [
          _LiveToggleButton(enabled: _liveMode, onTap: _toggleLive),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined,
                color: CceColors.textSecondary),
            tooltip: 'Limpiar',
            onPressed: _items.isEmpty ? null : _clearItems,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: CceColors.textSecondary),
            tooltip: 'Recargar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: CceColors.textPrimary,
              backgroundColor: CceColors.surfaceHigh,
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
                      separatorBuilder: (_, idx) => const SizedBox(height: 8),
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
                                    color: CceColors.textTertiary),
                              ),
                            ),
                          );
                        }
                        final entry = entries[i];
                        final header = entry.headerLabel;
                        if (header != null) {
                          return SectionHeader(
                            title: header,
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                          );
                        }
                        final g = entry.group!;
                        return _GroupRow(
                          group: g,
                          devices: widget.devices,
                          expanded: _expanded.contains(g.latest.id),
                          onToggleExpand: () => _toggleExpanded(g),
                        );
                      },
                    ),
            ),
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

  const _GroupRow({
    required this.group,
    required this.devices,
    required this.expanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final r = presentGroup(group, devices);
    final isAlarm = group.latest.eventName == 'alarm:triggered';
    final isLive = group.latest.id.startsWith('live-');
    final grouped = group.count > 1;

    return CceCard(
      radius: CceRadii.tile,
      padding: const EdgeInsets.all(14),
      border: true,
      onTap: grouped ? onToggleExpand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r.color.withValues(alpha: 0.18),
                  border: Border.all(
                    color: isAlarm
                        ? CceColors.danger.withValues(alpha: 0.40)
                        : r.color.withValues(alpha: 0.30),
                  ),
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(color: r.color, size: 22),
                    child: r.icon,
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
                                color: CceColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        if (grouped) ...[
                          const SizedBox(width: 6),
                          _CountPill(count: group.count, color: r.color),
                        ],
                      ],
                    ),
                    if (r.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        r.subtitle!,
                        style: const TextStyle(
                            color: CceColors.textTertiary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLive) ...[
                const StatusDot(CceColors.ok,
                    size: 6, pulse: true, semanticLabel: 'En vivo'),
                const SizedBox(width: 6),
              ],
              Text(
                TimeFormat.relative(group.latest.timestamp),
                style: const TextStyle(
                    color: CceColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              if (grouped) ...[
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const CceIcon(CceIcons.chevronDown,
                      size: 16, color: CceColors.textTertiary),
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
                            color: CceColors.textSecondary, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TimeFormat.hms(e.timestamp),
                      style: const TextStyle(
                          color: CceColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
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
              style: const TextStyle(
                color: CceColors.textSecondary,
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
                      color: CceColors.textTertiary, fontSize: 13),
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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: enabled
                  ? CceColors.danger.withValues(alpha: 0.22)
                  : CceColors.surfaceHigh,
              borderRadius: BorderRadius.circular(CceRadii.pill),
              border: Border.all(
                color: enabled ? CceColors.danger : CceColors.stroke,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabled ? Icons.fiber_manual_record : Icons.play_circle_outline,
                  color: enabled ? CceColors.danger : CceColors.textSecondary,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: enabled
                        ? CceColors.textPrimary
                        : CceColors.textSecondary,
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
            color: Color.lerp(CceColors.danger, const Color(0xFFFF8A80), v),
            boxShadow: [
              BoxShadow(
                color: CceColors.danger.withValues(alpha: 0.4 + v * 0.4),
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
