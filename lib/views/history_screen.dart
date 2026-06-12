import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/event_record.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';

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
  String? _cursor;
  HistoryFilter _filter = HistoryFilter.all;
  bool _liveMode = false;
  StreamSubscription<LiveEvent>? _liveSub;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.config);
    _scroll.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
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
    debugPrint('[HistoryLive] ${ev.eventName} payload=${ev.payload}');
    final rec = EventRecord(
      time: ev.time.toIso8601String(),
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
      _cursor = null;
      _hasMore = false;
    });
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _items.clear();
      _cursor = null;
      _hasMore = true;
    });
    try {
      final page = await _api.getEvents(limit: 150);
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
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  List<EventRecord> get _filtered => _items.where(_filter.accepts).toList();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
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
          // Filter chips row
          SizedBox(
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
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: CceColors.textPrimary,
              backgroundColor: CceColors.surfaceHigh,
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 400,
                          child: Center(
                            child: Text(
                              _loading ? '' : 'Sin eventos',
                              style: const TextStyle(
                                  color: CceColors.textTertiary),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, idx) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i >= filtered.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: CceColors.textTertiary),
                              ),
                            ),
                          );
                        }
                        return _EventRow(event: filtered[i], devices: widget.devices);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final EventRecord event;
  final DevicesService devices;
  const _EventRow({required this.event, required this.devices});

  ({IconData icon, Color color, String title, String? subtitle}) _render() {
    final p = event.payload ?? {};

    if (event.eventName == 'alarm:triggered') {
      final name = (p['automationName'] ?? 'Alarma').toString();
      final msg = (p['message'] ?? '').toString();
      return (icon: MdiIcons.alarmLight, color: CceColors.danger, title: 'Alarma: $name', subtitle: msg.isEmpty ? null : msg);
    }
    if (event.eventName == 'alarm:armed-changed') {
      final armed = p['armed'] == true;
      return (
        icon: armed ? MdiIcons.shield : MdiIcons.shieldOutline,
        color: armed ? CceColors.danger : CceColors.ok,
        title: armed ? 'Alarma ACTIVADA' : 'Alarma DESACTIVADA',
        subtitle: null,
      );
    }
    if (event.eventName.startsWith('automation:')) {
      final rawName = (p['name'] ?? p['automationName']) as String?;
      final autoId = (p['automationId'] ?? '').toString();
      final name = (rawName != null && rawName.isNotEmpty) ? rawName : devices.automationName(autoId);
      final trigger = p['trigger']?.toString();
      return (
        icon: MdiIcons.lightningBolt,
        color: CceColors.warm,
        title: 'Automatización: $name',
        subtitle: trigger != null && trigger.isNotEmpty ? 'Trigger: $trigger' : null,
      );
    }

    // device:state-changed / light:changed
    final deviceId = (p['deviceId'] ?? p['lightId'] ?? event.globalId ?? '').toString();
    var device = devices.byId(deviceId);
    if (device == null) {
      for (final d in devices.all) {
        if (d.bindingIds.contains(deviceId)) {
          device = d;
          break;
        }
      }
    }
    final deviceName = device == null
        ? (deviceId.isEmpty ? 'Dispositivo' : deviceId)
        : devices.displayName(device);

    final state = p['state'];
    final sensor = p['sensor'];

    if (sensor is Map) {
      if (sensor['contact'] != null) {
        final open = sensor['contact'] == true;
        return (
          icon: open ? MdiIcons.doorOpen : MdiIcons.doorClosed,
          color: open ? CceColors.contact : CceColors.textSecondary,
          title: '$deviceName → ${open ? 'Abierta' : 'Cerrada'}',
          subtitle: null,
        );
      }
      if (sensor['motion'] != null) {
        final motion = sensor['motion'] == true;
        return (
          icon: motion ? MdiIcons.motionSensor : MdiIcons.motionSensorOff,
          color: motion ? CceColors.motion : CceColors.textSecondary,
          title: '$deviceName → ${motion ? 'Movimiento' : 'Sin movimiento'}',
          subtitle: null,
        );
      }
      if (sensor['temperature'] != null) {
        final t = (sensor['temperature'] as num).toDouble();
        return (
          icon: MdiIcons.thermometer,
          color: const Color(0xFFFF8A5C),
          title: '$deviceName → ${t.toStringAsFixed(1)}°',
          subtitle: null,
        );
      }
      if (sensor['humidity'] != null) {
        final h = (sensor['humidity'] as num).toDouble();
        return (
          icon: MdiIcons.waterPercent,
          color: CceColors.info,
          title: '$deviceName → ${h.toStringAsFixed(0)}%',
          subtitle: null,
        );
      }
      if (sensor['lastKey'] != null) {
        final key = sensor['lastKey'];
        final outlet = sensor['outlet'];
        return (
          icon: MdiIcons.gestureTap,
          color: const Color(0xFF9575CD),
          title: '$deviceName → botón',
          subtitle: outlet != null ? 'outlet $outlet (key $key)' : 'key $key',
        );
      }
    }

    if (state is Map) {
      final on = state['on'];
      final bri = state['bri'];
      if (on != null) {
        final label = on == true ? 'encendida' : 'apagada';
        return (
          icon: on == true ? MdiIcons.lightbulbOn : MdiIcons.lightbulbOutline,
          color: on == true ? CceColors.warm : CceColors.textTertiary,
          title: '$deviceName $label',
          subtitle: bri != null && on == true ? 'Brillo ${((bri as num) / 254 * 100).round()}%' : null,
        );
      }
      if (bri != null) {
        return (
          icon: MdiIcons.brightness6,
          color: CceColors.warm,
          title: '$deviceName → ${((bri as num) / 254 * 100).round()}%',
          subtitle: null,
        );
      }
    }

    return (
      icon: MdiIcons.information,
      color: CceColors.textTertiary,
      title: deviceName.isEmpty ? event.eventName : '$deviceName (${event.eventName})',
      subtitle: null,
    );
  }

  String _relativeTime(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    return '$d/$m';
  }

  @override
  Widget build(BuildContext context) {
    final r = _render();
    return CceCard(
      radius: CceRadii.tile,
      padding: const EdgeInsets.all(14),
      border: true,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: r.color.withValues(alpha: 0.18),
            ),
            child: Icon(r.icon, color: r.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                      color: CceColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
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
          Text(
            _relativeTime(event.timestamp),
            style: const TextStyle(
                color: CceColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ],
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
