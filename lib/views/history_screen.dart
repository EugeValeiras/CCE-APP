import 'dart:async';
import 'package:flutter/material.dart';
import '../models/automation.dart';
import '../models/event_record.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/section_header.dart';
import '../theme/components/status_dot.dart';
import '../utils/time_format.dart';
import 'automations/automation_wizard_page.dart';
import 'history/actor_labels.dart';
import 'history/cause_grouping.dart';
import 'history/event_grouping.dart';
import 'history/event_presenter.dart';
import 'history/phone_events.dart';

enum HistoryFilter { all, lights, sensors, automations, alarm, telefono }

/// Pública (no `_`) para que el filtro se pueda testear sin montar la
/// pantalla: `accepts` es un switch compartido y un caso nuevo puede romper
/// los demás sin que nadie lo vea.
extension HistoryFilterX on HistoryFilter {
  String get label {
    switch (this) {
      case HistoryFilter.all: return 'Todos';
      case HistoryFilter.lights: return 'Luces';
      case HistoryFilter.sensors: return 'Sensores';
      case HistoryFilter.automations: return 'Automatizaciones';
      case HistoryFilter.alarm: return 'Alarma';
      case HistoryFilter.telefono: return 'Teléfono';
    }
  }

  /// Matches an event to a filter by eventName/payload.
  ///
  /// Se evalúa sobre la lista YA depurada por [isCallLogNoise]: el ciclo de
  /// una llamada (`{on: true, callState: 'dialing'}` de `dev_phone`) no llega
  /// hasta acá, así que "Luces" no vuelve a listar "Teléfono: encendido".
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
      case HistoryFilter.telefono:
        // `phone:*` (llamadas hoy, SMS con el #23) y `dev_phone`.
        return isPhoneEvent(e);
    }
  }
}

/// Entrada de la lista renderizada: header de día o HECHO (uno o más cambios
/// que comparten causa).
class _Entry {
  _Entry.header(this.headerLabel) : group = null;
  _Entry.group(this.group) : headerLabel = null;

  final String? headerLabel;
  final CauseGroup? group;
}

/// Historial de la casa: filas de [EventRow.kHeight] con riel de hora en
/// cifras tabulares, ícono coloreado por semántica, frase y un metadato a la
/// derecha, separadas por hairline. Sin card por evento: en una pantalla
/// entran 13 eventos en vez de 8.
class HistoryScreen extends StatefulWidget {
  final ServerConfig config;
  final DevicesService devices;

  /// Conservado por compatibilidad con los call-sites (phone/tablet); el
  /// render es el mismo en ambos.
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
    // Ticker de 30 s: re-renderiza los headers de día al cruzar medianoche.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _items.isNotEmpty) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _liveSub?.cancel();
    _autos?.dispose();
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
      // DUP-5: cada cambio se persiste 2× (internal binding-level +
      // websocket canónico). Filtramos channel=websocket para deduplicar: es el
      // canal durable donde emitAndRecord graba device:state-changed,
      // automation:executed y alarm:* (shape ya soportado por _RunKey/accepts).
      // Sin esto la apertura de una puerta aparece 2 veces.
      // NOTA (DUP-5): device-discovered se graba SOLO en channel='internal' (no
      // tiene emitAndRecord websocket), así que con este filtro NO aparece en el
      // historial. Es intencional; si se quisiera conservar habría que emitirlo
      // también por websocket o dedupar por (eventName+globalId+ventana).
      final page = await _api.getEvents(limit: 150, channel: 'websocket');
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
      // Mismo canal que _refresh (DUP-5): dedup internal+websocket.
      final page =
          await _api.getEvents(limit: 150, cursor: _cursor, channel: 'websocket');
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

  /// Pipeline: items → sin el log del teléfono → sin la telemetría repetida
  /// del robot → filtro → runs adyacentes → HECHOS (por causa) → headers de día.
  ///
  /// UNA llamada = UNA entrada (CCE#24): de los cinco o seis eventos que deja
  /// una llamada sobrevive sólo el `phone:call-state` de fin, que es el que
  /// trae el veredicto; el resto lo saca [isCallLogNoise] ANTES del filtro,
  /// para que "Todos" y "Teléfono" cuenten la misma historia. Lo mismo con el
  /// latido del robot ([stripRepeatedTelemetry]): queda el cambio, no el eco.
  ///
  /// UN comando = UNA entrada (CCE#75): [groupByCause] junta los cambios que
  /// el backend marcó como eco del mismo comando (y, sin esa marca, los del
  /// mismo aparato en una ventana corta). Prender el Hall pasa de doce filas a
  /// una, con quién lo pidió.
  List<_Entry> _buildEntries() {
    final filtered = stripRepeatedTelemetry(
      _items.where((e) => !isCallLogNoise(e)).toList(),
      widget.devices,
    ).where(_filter.accepts).toList();
    final groups =
        groupByCause(groupEvents(filtered, widget.devices), widget.devices);
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

  void _toggleExpanded(CauseGroup g) {
    setState(() {
      if (!_expanded.remove(g.key)) _expanded.add(g.key);
    });
  }

  /// Se crea acá y no se recibe por constructor (mismo patrón que
  /// sensor_detail_screen) para no cambiar la firma de la pantalla ni la de
  /// sus call sites: toma lo mismo que ya tiene.
  AutomationsService? _autos;
  AutomationsService get _automations => _autos ??=
      AutomationsService(config: widget.config, devices: widget.devices);

  /// De «por qué pasó esto» a «qué automatización lo hizo», en un toque.
  Future<void> _openAutomation(String id) async {
    final svc = _automations;
    var found = _findAutomation(svc, id);
    if (found == null) {
      // Recién creado el service la lista puede estar vacía todavía.
      await svc.refresh();
      found = _findAutomation(svc, id);
    }
    if (!mounted) return;
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esa automatización ya no existe')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<Object?>(
        builder: (_) => AutomationWizardPage(
          service: svc,
          devices: widget.devices,
          // Copia descartable, como desde la lista: el wizard muta el draft al
          // abrirlo y Cancelar no puede dejar tocado el item de la lista.
          draft: found!.copyForEdit(),
          isNew: false,
        ),
      ),
    );
  }

  Automation? _findAutomation(AutomationsService svc, String id) {
    for (final a in svc.automations) {
      if (a.id == id) return a;
    }
    return null;
  }

  Widget _buildFilters() {
    // Chips scrolleables (phone y tablet). Los bordes se DESVANECEN en vez de
    // cortar el chip que queda a medias contra el margen.
    return SizedBox(
      height: 56,
      child: _FadeEdges(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
              horizontal: CceSpace.lg, vertical: CceSpace.md),
          children: HistoryFilter.values.map((f) {
            final selected = f == _filter;
            return Padding(
              padding: EdgeInsets.only(right: CceSpace.sm),
              // Filtro seleccionado = fill de acento + borde de acento: el
              // estado activo de un filtro tiene que leerse de un vistazo.
              child: ChoiceChip(
                label: Text(f.label),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f),
                shape: const StadiumBorder(),
                backgroundColor: CceColors.surface,
                selectedColor: CceColors.accentWash,
                labelStyle: CceText.label.copyWith(
                  color: selected ? CceColors.accent : CceColors.textSecondary,
                ),
                side: BorderSide(
                  color: selected ? CceColors.accent : CceColors.stroke,
                  width: 1,
                ),
              ),
            );
          }).toList(),
        ),
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
                strokeWidth: 2, color: CceColors.textTertiary),
          ),
        ),
      );
    }
    if (!_eventsEnabled && _items.isEmpty) {
      return const _EmptyState(
        title: 'El historial está desactivado en el servidor',
        caption: 'Activá la página de eventos en la configuración del '
            'servidor para ver la actividad de la casa.',
      );
    }
    if (_items.isEmpty) {
      return const _EmptyState(
        title: 'Sin actividad todavía',
        caption: 'Los eventos de luces, sensores, automatizaciones, alarma y '
            'llamadas van a aparecer acá.',
      );
    }
    // Hay eventos pero el filtro no matchea ninguno.
    return _EmptyState(
      title: 'Sin eventos de ${_filter.label.toLowerCase()} hoy',
      action: TextButton(
        style: TextButton.styleFrom(foregroundColor: CceColors.accent),
        onPressed: () => setState(() => _filter = HistoryFilter.all),
        child: const Text('Ver todos'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: CceSpace.lg,
        title: const Text('Historial', style: CceText.title),
        actions: [
          _LivePill(enabled: _liveMode, onTap: _toggleLive),
          SizedBox(width: CceSpace.xs),
          IconButton(
            tooltip: 'Limpiar',
            onPressed: _items.isEmpty ? null : _clearItems,
            icon: CceIcon(
              CceIcons.trash,
              size: 20,
              color: _items.isEmpty
                  ? CceColors.textMuted
                  : CceColors.textSecondary,
              emboss: false,
            ),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _refresh,
            icon: const CceIcon(CceIcons.refreshCw,
                size: 20, color: CceColors.textSecondary, emboss: false),
          ),
          SizedBox(width: CceSpace.sm),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: CceColors.textSecondary,
              backgroundColor: CceColors.surfaceHigh,
              child: entries.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_buildEmpty()],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                          CceSpace.lg, 0, CceSpace.lg, CceSpace.xl),
                      itemCount: entries.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= entries.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: CceSpace.lg),
                            child: const Center(
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
                          // El primer header pega arriba (los chips ya
                          // respiran); los siguientes separan el día.
                          return SectionHeader(
                            title: header,
                            padding: i == 0
                                ? EdgeInsets.fromLTRB(
                                    CceSpace.xs, 0, CceSpace.xs, CceSpace.xs)
                                : EdgeInsets.fromLTRB(CceSpace.xs, CceSpace.xl,
                                    CceSpace.xs, CceSpace.xs),
                          );
                        }
                        final g = entry.group!;
                        return EventRow(
                          group: g,
                          devices: widget.devices,
                          expanded: _expanded.contains(g.key),
                          onToggleExpand: () => _toggleExpanded(g),
                          onOpenAutomation: _openAutomation,
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

/// Fila de un HECHO: riel de hora + ícono semántico + frase + metadato, con
/// pill (×N o «4 luces») y chevron cuando abarca varios eventos, y —cuando el
/// backend dijo quién lo causó— una segunda línea con el actor.
/// Pública para poder testear el layout (una fila = [kHeight]).
class EventRow extends StatelessWidget {
  final CauseGroup group;
  final DevicesService devices;
  final bool expanded;
  final VoidCallback onToggleExpand;

  /// Abre la automatización que causó el hecho. Opcional: sin esto la línea
  /// del actor se muestra igual, sólo que no enlaza.
  final void Function(String automationId)? onOpenAutomation;

  const EventRow({
    super.key,
    required this.group,
    required this.devices,
    required this.expanded,
    required this.onToggleExpand,
    this.onOpenAutomation,
  });

  /// Alto de la fila (sin expandir): antes ~82 con card; ahora 52.
  static const double kHeight = 52;

  /// Ancho del riel de hora ("12:06" en cifras tabulares) + su separación.
  static const double _rail = 44;
  static const double _icon = 20;

  @override
  Widget build(BuildContext context) {
    final r = presentCause(group, devices);
    final isLive = group.latest.id.startsWith('live-');
    final grouped = group.expandable;
    final quien = actorLabel(group.actor, devices);
    final autoId = automationIdOfActor(group.actor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: grouped ? onToggleExpand : null,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CceColors.strokeSoft)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: kHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _rail,
                      child: Text(
                        TimeFormat.hm(group.latest.timestamp),
                        style: CceText.dataCaption,
                      ),
                    ),
                    // r.icon no fija color propio: el tinte semántico se
                    // inyecta vía IconTheme.
                    IconTheme.merge(
                      data: IconThemeData(color: r.color, size: _icon),
                      child: r.icon,
                    ),
                    SizedBox(width: CceSpace.md),
                    Expanded(
                      child: Text(
                        r.title,
                        style: CceText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r.subtitle != null) ...[
                      SizedBox(width: CceSpace.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          r.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: CceText.caption
                              .copyWith(color: CceColors.textTertiary),
                        ),
                      ),
                    ],
                    if (grouped) ...[
                      SizedBox(width: CceSpace.sm),
                      _CountPill(label: _countLabel(group, devices)),
                      SizedBox(width: CceSpace.xs),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: const CceIcon(CceIcons.chevronDown,
                            size: 16,
                            color: CceColors.textTertiary,
                            emboss: false),
                      ),
                    ],
                    if (isLive) ...[
                      SizedBox(width: CceSpace.sm),
                      const StatusDot(CceColors.ok,
                          size: 6, pulse: true, semanticLabel: 'En vivo'),
                    ],
                  ],
                ),
              ),
              // QUIÉN lo hizo. Sólo aparece si el backend lo informó: un
              // cambio sin causa pasó solo, y decir «desde la app» ahí sería
              // inventar. Enlaza cuando la causa es una automatización.
              if (quien != null)
                Padding(
                  padding: EdgeInsets.only(
                    left: _rail + _icon + CceSpace.md,
                    bottom: CceSpace.sm,
                  ),
                  child: _ActorLine(
                    label: quien,
                    onTap: autoId != null && onOpenAutomation != null
                        ? () => onOpenAutomation!(autoId)
                        : null,
                  ),
                ),
              if (grouped && expanded)
                Padding(
                  padding: EdgeInsets.only(
                    left: _rail + _icon + CceSpace.md,
                    bottom: CceSpace.sm,
                  ),
                  child: Column(
                    children: [
                      for (final e in group.events)
                        Padding(
                          padding: EdgeInsets.only(bottom: CceSpace.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  presentEvent(e, devices).title,
                                  style: CceText.caption,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: CceSpace.sm),
                              Text(
                                TimeFormat.hms(e.timestamp),
                                style: CceText.dataCaption,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qué dice el pill de un hecho: cuántos APARATOS cambiaron cuando son varios
/// («4 luces», que es la información del issue), y cuántas veces se repitió
/// cuando es uno solo («×3»).
String _countLabel(CauseGroup g, DevicesService devices) {
  // Cuando el título nombra al conjunto («Hall se encendió») el pill dice
  // cuántos son; cuando el título YA los contó («5 luces se apagaron»), decirlo
  // de nuevo no agrega nada y el pill pasa a contar los cambios que hay
  // adentro, que es lo que se despliega al tocar.
  if (g.deviceCount > 1 && !causeSubject(g, devices).plural) {
    return causeCountLabel(g, devices);
  }
  return '×${g.eventCount}';
}

/// Pill: cuántos aparatos abarca el hecho, o cuántas veces se repitió.
///
/// NEUTRO a propósito. Antes heredaba el color semántico del evento (azul de
/// movimiento, rojo de alerta…), así que la cantidad se pintaba con el mismo
/// código de color que el tipo de evento — dos significados en un color. El
/// ícono de la fila ya dice de qué se trata; esto sólo dice cuántos.
class _CountPill extends StatelessWidget {
  final String label;
  const _CountPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: EdgeInsets.symmetric(horizontal: CceSpace.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        border: Border.all(color: CceColors.stroke),
        borderRadius: BorderRadius.circular(CceRadii.pill),
      ),
      child: Text(
        label,
        style: CceText.section.copyWith(
          color: CceColors.textSecondary,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Segunda línea de la fila: quién causó el hecho. Cuando la causa es una
/// automatización se puede tocar para ir a verla — de «por qué pasó esto» a
/// «qué automatización lo hizo» sin buscarla a mano.
class _ActorLine extends StatelessWidget {
  const _ActorLine({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enlazada = onTap != null;
    final texto = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CceText.caption.copyWith(
              color:
                  enlazada ? CceColors.accent : CceColors.textTertiary,
            ),
          ),
        ),
        if (enlazada) ...[
          SizedBox(width: CceSpace.xs),
          const CceIcon(CceIcons.chevronRight,
              size: 12, color: CceColors.accent, emboss: false),
        ],
      ],
    );
    if (!enlazada) return Align(alignment: Alignment.centerLeft, child: texto);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: CceSpace.xs, vertical: 2),
            child: texto,
          ),
        ),
      ),
    );
  }
}

/// Desvanece el contenido contra los bordes laterales (chips que quedan a
/// medias contra el margen), en vez de cortarlos.
class _FadeEdges extends StatelessWidget {
  const _FadeEdges({required this.child});

  final Widget child;
  static const double _fade = 24;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) {
        final f = (_fade / rect.width).clamp(0.0, 0.5);
        return LinearGradient(
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? action;

  const _EmptyState({
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
            const CceIcon(CceIcons.history,
                size: 48, color: CceColors.textMuted, emboss: false),
            SizedBox(height: CceSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: CceText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            if (caption != null) ...[
              SizedBox(height: CceSpace.sm),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: CceSpace.xxl),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: CceText.caption.copyWith(color: CceColors.textTertiary),
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: CceSpace.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Toggle "EN VIVO": pill de acento (dot pulsante) cuando escucha el socket;
/// pill neutra con ▶ cuando no. Un solo control, un solo estado visible.
class _LivePill extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _LivePill({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? 'Pausar vivo' : 'Ver en vivo',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 32,
            padding: EdgeInsets.symmetric(horizontal: CceSpace.md),
            decoration: BoxDecoration(
              color: enabled ? CceColors.accentWash : CceColors.surface,
              borderRadius: BorderRadius.circular(CceRadii.pill),
              border: Border.all(
                color: enabled ? CceColors.accent : CceColors.stroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (enabled)
                  const StatusDot(CceColors.accent, size: 6, pulse: true)
                else
                  const CceIcon(CceIcons.play,
                      size: 12, color: CceColors.textTertiary, emboss: false),
                SizedBox(width: CceSpace.sm),
                Text(
                  'EN VIVO',
                  style: CceText.section.copyWith(
                    color: enabled ? CceColors.accent : CceColors.textTertiary,
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
