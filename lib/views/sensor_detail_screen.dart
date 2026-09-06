import 'package:flutter/material.dart';
import 'sensor_event_row.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/event_record.dart';
import '../services/api_service.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_switch.dart';
import '../utils/alarm_triggers.dart';
import '../utils/time_format.dart';
import '../widgets/device_automations_sheet.dart';

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
      if (mounted) {
        _loadEvents();
        _loadAlarmTrigger();
      }
    });
  }

  /// ¿Este sensor dispara la alarma? null = todavía no se sabe (el recuadro
  /// muestra un guion en vez de mentir con un "No" que quizá no es cierto).
  bool? _firesAlarm;
  bool _alarmSaving = false;

  /// El mapa entero, no sólo el booleano: apagar necesita saber bajo QUÉ
  /// clave está marcado este sensor (ver [writeFiresAlarm]).
  Map<String, bool> _triggers = const {};

  Future<void> _loadAlarmTrigger() async {
    try {
      final all = await _api.getSensorAlarmTriggers();
      if (!mounted) return;
      // Canónico + bindings, resuelto por el helper que comparten esta
      // pantalla y la lista "qué protege" de la alarma.
      setState(() {
        _triggers = all;
        _firesAlarm = firesAlarm(_device, all);
      });
    } catch (_) {
      // Sin dato el recuadro queda en '—' y el toggle deshabilitado: mejor eso
      // que ofrecer un switch que no sabe de qué estado parte.
    }
  }

  Future<void> _toggleAlarmTrigger() async {
    final actual = _firesAlarm;
    if (actual == null || _alarmSaving) return;
    final previous = _triggers;
    setState(() {
      _firesAlarm = !actual;
      _alarmSaving = true;
    });
    try {
      final saved =
          await writeFiresAlarm(_api, _device, previous, fires: !actual);
      if (mounted) setState(() => _triggers = saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _firesAlarm = actual; // revert
          _triggers = previous;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pude cambiar el disparo de alarma')),
        );
      }
    } finally {
      if (mounted) setState(() => _alarmSaving = false);
    }
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

  /// Se crea acá y no se recibe por constructor para no cambiar la firma de
  /// esta pantalla ni la de sus cinco call sites; toma lo mismo que ya tiene.
  AutomationsService? _autos;
  AutomationsService get autos => _autos ??= AutomationsService(
    config: widget.service.config,
    devices: widget.service,
  );

  /// Cuántas automatizaciones dispara este sensor (se muestra en el recuadro).
  int get _autoCount {
    final ids = <String>{_device.id, ..._device.bindingIds};
    return autos.automations
        .where(
          (a) => a.trigger.sensorTriggers.any((t) => ids.contains(t.sensorId)),
        )
        .length;
  }

  void _openAutomations() {
    DeviceAutomationsSheet.show(
      context,
      device: _device,
      devices: widget.service,
      automations: autos,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
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
                if (_device.isHueMotionArea) ...[
                  const SizedBox(height: 22),
                  _buildMotionAware(),
                ],
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
      // El Stack tiene que ocupar TODO el ancho: por defecto se encoge al hijo
      // más ancho (el texto de estado) y lo alinea arriba-izquierda, y así el
      // disco y los textos quedaban pegados al borde en vez de centrados. El
      // ancho completo también hace que el ícono de sin-señal caiga en la
      // esquina real de la card y no al lado del texto.
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          const SizedBox(width: double.infinity),
          // Sin señal: ícono en la esquina, SÓLO cuando pasa. Antes esto era un
          // recuadro fijo que decía "En línea" el 99% del tiempo y gastaba un
          // cuarto de la fila de métricas para no informar nada.
          if (!_device.state.reachable)
            Positioned(
              top: 0,
              right: 0,
              child: Tooltip(
                message: 'Sin señal',
                child: SizedBox.square(
                  dimension: 20,
                  child: CceIcon(
                    CceIcons.sensors,
                    size: 20,
                    color: CceColors.danger,
                    emboss: false,
                  ),
                ),
              ),
            ),
          Column(
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
                              blurRadius: 12,
                            ),
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
        ],
      ),
    );
  }

  // ── Métricas: batería · ambiente · último evento · automatizaciones ───────

  // ── MotionAware (EugeValeiras/CCE#96): el área se prende y apaga ─────────
  //
  // Es el único sensor con switch: `on` es el `enabled` del área en el bridge,
  // no una luz. El toggle va por el mismo camino que cualquier switch
  // (PUT /devices/:id/state { on }) y el rótulo dice lo que hace. Vive acá y no
  // sólo en la Vista unificada porque ESTA es la pantalla a la que llega el tap
  // sobre un sensor de movimiento.
  Widget _buildMotionAware() {
    final d = _device;
    final on = d.state.on;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(20),
        boxShadow: CceShadows.neo(blur: 12, offset: 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MotionAware',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CceColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  on
                      ? 'Prendido: el área detecta movimiento con las luces Hue.'
                      : 'Apagado: el área no detecta movimiento.',
                  style: CceText.caption.copyWith(color: CceColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CceSwitch(
            value: on,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              widget.service.applyCapabilityState(
                  d, d.state.copyWith(on: v), {'on': v});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final sensor = _device.sensor;
    final battery = sensor?.battery;
    final brightness = sensor?.brightness;
    final lux = sensor?.lux;

    final metrics = <Widget>[
      _Metric(
        svg: CceIcons.batteryFull,
        iconColor: _batteryColor(battery),
        value: battery != null ? '$battery%' : '—',
        label: 'BATERÍA',
      ),
      // CCE#112 — con el número cuando el sensor lo mide (SNZB-03PR2): el valor
      // es el lux y el rótulo dice si eso es oscuro o con luz. El 03P viejo
      // sigue mostrando sólo el binario.
      if (lux != null)
        _Metric(
          svg: CceIcons.sunMedium,
          // El color sale del mismo umbral que el backend (50 lx): sin el
          // binario, un sol gris sobre 800 lx mentía.
          iconColor: (sensor?.isBright ?? false)
              ? CceColors.warm
              : CceColors.textSecondary,
          value: '$lux lx',
          // Sin el binario no se afirma «oscuro» sobre 800 lx: el rótulo
          // queda neutro y el número habla solo.
          label: brightness == null
              ? 'LUZ'
              : (brightness == 'brighter' ? 'CON LUZ' : 'OSCURO'),
        )
      else if (brightness != null)
        _Metric(
          svg: CceIcons.sunMedium,
          iconColor: brightness == 'brighter'
              ? CceColors.warm
              : CceColors.textSecondary,
          value: brightness == 'brighter' ? 'Con luz' : 'Oscuro',
          label: 'AMBIENTE',
        ),
      _Metric(
        svg: CceIcons.automations,
        iconColor: CceColors.textSecondary,
        value: '$_autoCount',
        label: 'AUTOMATIZ.',
        onTap: _openAutomations,
      ),
      // Disparo de alarma: el recuadro ES el switch. Estaba sólo en el
      // dashboard, así que desde el teléfono no había forma de sacar un sensor
      // de la alarma — justo lo que uno quiere hacer rápido y en el momento.
      _Metric(
        svg: CceIcons.alarmShield,
        iconColor: _firesAlarm == true
            ? CceColors.danger
            : CceColors.textSecondary,
        value: switch (_firesAlarm) {
          true => 'Sí',
          false => 'No',
          null => '—',
        },
        label: 'ALARMA',
        onTap: _firesAlarm == null ? null : _toggleAlarmTrigger,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final gap = c.maxWidth < 360 ? 8.0 : 12.0;
        // Hasta 4 por fila entran bien en un teléfono; de ahí para arriba el
        // valor se corta, así que se parte en filas PAREJAS —3+2 antes que
        // 4+1— para que no quede una huérfana estirada. Hoy el máximo real es
        // 4 (batería, ambiente, automatizaciones, alarma); el reparto existe
        // para la próxima métrica que se sume.
        const maxPorFila = 4;
        final filas = <List<Widget>>[];
        if (metrics.length <= maxPorFila) {
          filas.add(metrics);
        } else {
          final porFila = (metrics.length / 2).ceil();
          for (var i = 0; i < metrics.length; i += porFila) {
            filas.add(
              metrics.sublist(i, (i + porFila).clamp(0, metrics.length)),
            );
          }
        }

        Widget fila(List<Widget> items) {
          final children = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            if (i > 0) children.add(SizedBox(width: gap));
            children.add(Expanded(child: items[i]));
          }
          // Sin CrossAxisAlignment.stretch: Row dentro de scroll ilimitado.
          return Row(children: children);
        }

        if (filas.length == 1) return fila(filas.first);
        return Column(
          children: [
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              fila(filas[i]),
            ],
          ],
        );
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
                        child: CceIcon(
                          CceIcons.refreshCw,
                          size: 16,
                          color: CceColors.textSecondary,
                          emboss: false,
                        ),
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
                  color: CceColors.textTertiary,
                  fontSize: 13,
                ),
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

  Widget _buildEventRow(EventRecord ev, {required bool last}) {
    final spec = _spec;
    // La lógica de la fila es pura y está testeada aparte (sensor_event_row.dart).
    final row = sensorEventRow(
      ev,
      isContact: _isContact,
      spec: SensorEventRowSpec(
        activeLabel: spec.activeLabel,
        idleLabel: spec.idleLabel,
        activeGlyph: spec.activeGlyph,
        idleGlyph: spec.idleGlyph,
        activeColor: spec.activeColor,
      ),
    );
    final active = row.active;
    final label = row.label;
    final color = row.color;
    final glyph = row.glyph;
    final ts = ev.timestamp;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: CceColors.neoDark.withValues(alpha: 0.55),
                ),
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
                    color: color.withValues(alpha: 0.40),
                    blurRadius: 8,
                  ),
              ],
            ),
            child: SizedBox.square(
              dimension: 18,
              child: CceIcon(glyph, size: 18, color: color, emboss: false),
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
                    fontSize: 13.5,
                    color: CceColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${TimeFormat.dayLabel(ts)} · ${TimeFormat.hm(ts)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: CceColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            TimeFormat.relative(ts),
            style: const TextStyle(
              fontSize: 11.5,
              color: CceColors.textTertiary,
            ),
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
    this.onTap,
  });

  final String svg;
  final Color iconColor;
  final String value;
  final String label;

  /// Si se provee, el recuadro deja de ser un dato y pasa a ser un BOTÓN.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }

  Widget _card(BuildContext context) {
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
            Shadow(
              color: Color(0x80FFFFFF),
              offset: Offset(-1, -1.2),
              blurRadius: 1.5,
            ),
            Shadow(
              color: Color(0xD907080C),
              offset: Offset(1.4, 2),
              blurRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}
