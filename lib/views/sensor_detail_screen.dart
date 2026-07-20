import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/event_record.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../utils/time_format.dart';

/// Pantalla de detalle de los sensores PASIVOS: movimiento y contacto
/// (aberturas). Eran los únicos devices de la casa sin pantalla propia — el
/// tile no abría nada.
///
/// Mismo canon que [LockScreen] (pantalla solo-estado): panel neoBase
/// full-bleed sin AppBar (se vuelve con el swipe de iOS), disco cóncavo con
/// glow del color de estado, wells hundidos de métricas e historial real del
/// backend en un well con hairlines.
///
/// Un solo widget para ambos tipos porque son estructuralmente idénticos
/// (booleano + batería + luz ambiente + trigTime + historial); lo que cambia
/// —ícono, labels y acento— viaja en [_SensorKindSpec].
class SensorDetailScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;

  const SensorDetailScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

/// Vocabulario visual por tipo de sensor.
class _SensorKindSpec {
  final String activeLabel;
  final String idleLabel;
  final String activeGlyph;
  final String idleGlyph;
  final Color activeColor;
  final String wordmark;

  const _SensorKindSpec({
    required this.activeLabel,
    required this.idleLabel,
    required this.activeGlyph,
    required this.idleGlyph,
    required this.activeColor,
    required this.wordmark,
  });

  static const motion = _SensorKindSpec(
    activeLabel: 'Movimiento',
    idleLabel: 'Sin movimiento',
    activeGlyph: CceIcons.personStanding,
    idleGlyph: CceIcons.footprints,
    activeColor: CceColors.motion, // azul #5A8BFA
    wordmark: 'CCE MOTION',
  );

  static const contact = _SensorKindSpec(
    activeLabel: 'Abierta',
    idleLabel: 'Cerrada',
    activeGlyph: CceIcons.doorOpen,
    idleGlyph: CceIcons.doorClosed,
    activeColor: CceColors.contact, // naranja #FF9F43
    wordmark: 'CCE CONTACT',
  );
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  late final ApiService _api;

  List<EventRecord> _events = const [];
  bool _eventsLoading = false;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.service.config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadEvents();
    });
  }

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  bool get _isContact => _device.isContactSensor;

  _SensorKindSpec get _spec =>
      _isContact ? _SensorKindSpec.contact : _SensorKindSpec.motion;

  /// Estado activo: movimiento detectado / abertura abierta.
  bool get _active => _isContact
      ? (_device.sensor?.contact ?? false)
      : (_device.sensor?.motion ?? false);

  /// El historial del backend se indexa por el bindingId del provider
  /// (ewelink_xxx), no por el dev_* canónico.
  String? get _historyId =>
      _device.bindingIds.isNotEmpty ? _device.bindingIds.first : _device.id;

  Future<void> _loadEvents() async {
    final id = _historyId;
    if (id == null) return;
    setState(() => _eventsLoading = true);
    try {
      final page = await _api.getEvents(globalId: id, limit: 25);
      if (!mounted) return;
      setState(() {
        // Un cambio de estado por fila: el canal interno ya viene deduplicado
        // por device; websocket duplicaría cada evento.
        _events = page.items
            .where((e) => e.channel == 'internal')
            .toList(growable: false);
        _eventsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _eventsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.neoBase,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildState(),
                const SizedBox(height: 22),
                _buildMetrics(),
                const SizedBox(height: 22),
                _buildEventsSection(),
                const SizedBox(height: 18),
                _Wordmark(_spec.wordmark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Estado grande: disco cóncavo con glow del acento ──────────────────────

  Widget _buildState() {
    final spec = _spec;
    final active = _active;
    // En reposo el disco queda apagado (gris): el color SOLO comunica el
    // evento activo, igual que el lock.
    final accent = active ? spec.activeColor : CceColors.textTertiary;
    final glyph = active ? spec.activeGlyph : spec.idleGlyph;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
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
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.concave(CceColors.neoBase),
              // Glow SOLO por BoxShadow (regla dura: nada de ImageFiltered).
              boxShadow: [
                ...CceShadows.plato(blur: 15, offset: 6),
                if (active) ...CceShadows.glowDot(accent),
              ],
            ),
            child: SizedBox.square(
              dimension: 56,
              child: CceIcon(glyph, size: 56, color: accent, emboss: false),
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              active ? spec.activeLabel : spec.idleLabel,
              maxLines: 1,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: accent,
                shadows: active
                    ? [
                        Shadow(
                            color: accent.withValues(alpha: 0.65),
                            blurRadius: 12),
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.service.displayName(_device),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CceText.caption,
          ),
        ],
      ),
    );
  }

  // ── Métricas: batería · luz ambiente · último evento ──────────────────────

  Widget _buildMetrics() {
    final sensor = _device.sensor;
    final battery = sensor?.battery;
    final brightness = sensor?.brightness;
    final trig = sensor?.trigTime;

    final metrics = <Widget>[
      _Metric(
        svg: CceIcons.batteryFull,
        iconColor: _batteryColor(battery),
        value: battery != null ? '$battery%' : '—',
        label: 'BATERÍA',
      ),
      if (brightness != null)
        _Metric(
          svg: CceIcons.sunMedium,
          iconColor: brightness == 'brighter'
              ? CceColors.warm
              : CceColors.textSecondary,
          value: brightness == 'brighter' ? 'Con luz' : 'Oscuro',
          label: 'AMBIENTE',
        ),
      _Metric(
        svg: CceIcons.clock,
        iconColor: CceColors.textSecondary,
        value: trig != null
            ? TimeFormat.relative(
                DateTime.fromMillisecondsSinceEpoch(trig))
            : '—',
        label: 'ÚLTIMO',
      ),
      _Metric(
        svg: CceIcons.sensors,
        iconColor: _device.state.reachable
            ? CceColors.ok
            : CceColors.textTertiary,
        value: _device.state.reachable ? 'En línea' : 'Sin señal',
        label: 'ESTADO',
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
        // Sin CrossAxisAlignment.stretch: Row dentro de scroll ilimitado.
        return Row(children: children);
      },
    );
  }

  Color _batteryColor(String? raw) {
    final pct = int.tryParse(raw ?? '');
    if (pct == null) return CceColors.textSecondary;
    if (pct <= 15) return CceColors.danger;
    if (pct <= 35) return CceColors.warm;
    return CceColors.ok;
  }

  // ── Historial real del backend ────────────────────────────────────────────

  Widget _buildEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HISTORIAL', style: CceText.section),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _eventsLoading ? null : _loadEvents,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CceColors.neoBase,
                  boxShadow: CceShadows.neo(blur: 6, offset: 2),
                ),
                child: _eventsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CceColors.textSecondary,
                        ),
                      )
                    : SizedBox.square(
                        dimension: 16,
                        child: CceIcon(CceIcons.refreshCw,
                            size: 16,
                            color: CceColors.textSecondary,
                            emboss: false),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                _eventsLoading
                    ? 'Cargando eventos…'
                    : 'Sin eventos registrados',
                style: const TextStyle(
                    color: CceColors.textTertiary, fontSize: 13),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: BorderRadius.circular(18),
              boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _events.length; i++)
                  _buildEventRow(_events[i], last: i == _events.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  /// Lee el estado del sensor DEL EVENTO (no del device): cada fila cuenta
  /// qué pasó en ese instante.
  bool? _activeOf(EventRecord ev) {
    final sensor = ev.payload?['sensor'];
    if (sensor is! Map) return null;
    final v = _isContact ? sensor['contact'] : sensor['motion'];
    return v is bool ? v : null;
  }

  Widget _buildEventRow(EventRecord ev, {required bool last}) {
    final spec = _spec;
    final active = _activeOf(ev);
    final label = active == null
        ? 'Actualización'
        : (active ? spec.activeLabel : spec.idleLabel);
    final color =
        active == true ? spec.activeColor : CceColors.textTertiary;
    final glyph = active == true ? spec.activeGlyph : spec.idleGlyph;
    final ts = ev.timestamp;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                    color: CceColors.neoDark.withValues(alpha: 0.55)),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              gradient: CceGradients.convex(CceColors.neoBase),
              boxShadow: [
                ...CceShadows.neo(blur: 8, offset: 3),
                if (active == true)
                  BoxShadow(
                      color: color.withValues(alpha: 0.40), blurRadius: 8),
              ],
            ),
            child: SizedBox.square(
              dimension: 18,
              child:
                  CceIcon(glyph, size: 18, color: color, emboss: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, color: CceColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${TimeFormat.dayLabel(ts)} · ${TimeFormat.hm(ts)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: CceColors.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            TimeFormat.relative(ts),
            style: const TextStyle(
                fontSize: 11.5, color: CceColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Well de métrica (espejo de lock_screen._Metric) ───────────────────────

class _Metric extends StatelessWidget {
  const _Metric({
    required this.svg,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final String svg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(16),
        boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 22,
            child: CceIcon(svg, size: 22, color: iconColor, emboss: false),
          ),
          const SizedBox(height: 6),
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

class _Wordmark extends StatelessWidget {
  const _Wordmark(this.text);
  final String text;

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
