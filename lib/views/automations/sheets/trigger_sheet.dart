import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/automation.dart';
import '../../../models/device.dart';
import '../../../services/devices_service.dart';
import '../../../services/socket_service.dart';
import '../../../services/ui_settings_service.dart';
import '../../../theme/cce_icons.dart';
import '../../../theme/cce_tokens.dart';
import '../../../theme/components/cce_segmented.dart';
import '../../../widgets/lock_tile.dart';
import '../../../widgets/sensor_tile.dart';
import '../../../widgets/vacuum_tile.dart';

/// Sheet CUÁNDO: tipo de trigger (Sensor / Horario / Manual) y su
/// configuración. Muta `draft.trigger` directamente — el draft completo es
/// una copia que el editor descarta con Cancelar.
Future<bool> showTriggerSheet(
  BuildContext context, {
  required Automation draft,
  required DevicesService devices,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TriggerSheet(draft: draft, devices: devices),
  );
  return result == true;
}

class _TriggerSheet extends StatefulWidget {
  const _TriggerSheet({required this.draft, required this.devices});

  final Automation draft;
  final DevicesService devices;

  @override
  State<_TriggerSheet> createState() => _TriggerSheetState();
}

class _TriggerSheetState extends State<_TriggerSheet> {
  AutomationTrigger get trigger => widget.draft.trigger;

  StreamSubscription<DeviceStateEvent>? _captureSub;
  String? _capturingDeviceId;
  final Set<String> _captured = {};

  /// Personas conocidas de la cerradura (para "Entra <persona>"). Se cargan
  /// una vez al abrir el sheet; [] = ocultar la opción de persona.
  List<String> _actors = const [];

  /// Métodos de apertura de la cerradura (sensor.lockOpenWay del push). El
  /// value '' = cualquiera (sin condición). Espejo del Dashboard.
  static const _openWays = [
    ('', 'Cualquiera'),
    ('fingerprint', 'Huella'),
    ('password', 'Clave'),
    ('card', 'Tarjeta'),
    ('remote', 'Remoto'),
    ('face', 'Cara'),
  ];

  @override
  void initState() {
    super.initState();
    // Horario fijo sin hora (automatizacion legacy): el picker mostraba 19:30
    // pero trigger.time seguia null y "Guardar" quedaba bloqueado sin motivo
    // visible. Se siembra el valor que el picker ya esta mostrando.
    if (trigger.type == 'schedule' &&
        trigger.scheduleMode != 'interval' &&
        trigger.time == null) {
      final t = _initialTime();
      trigger.time =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    widget.devices.ezvizActors().then((a) {
      if (mounted) setState(() => _actors = a);
    });
  }

  /// lastKey → nombre real de la pulsación (contrato del backend).
  static const _pressKinds = {0: 'Click', 1: 'Doble click', 2: 'Mantener'};

  String _pressLabel(dynamic v) =>
      _pressKinds[(v as num?)?.toInt()] ?? 'Pulsación ${v ?? '?'}';

  static const _delaySteps = [0, 15, 30, 60, 120, 300, 600];
  static const _delayLabels = [
    'No',
    '15 s',
    '30 s',
    '1 m',
    '2 m',
    '5 m',
    '10 m',
  ];

  @override
  void dispose() {
    // Cinturón: si el usuario cambió el tipo de trigger o deseleccionó la
    // cerradura por cualquier camino, ninguna lockOpenWay debe quedar colgada.
    if (trigger.type != 'sensor') {
      trigger.conditions.removeWhere(
        (c) => c.type == 'sensor' && c.field == 'lockOpenWay',
      );
    } else {
      _pruneOrphanLockConditions();
    }
    _captureSub?.cancel();
    super.dispose();
  }

  bool _isButtonDevice(Device d) => isButtonDevice(d);

  List<Device> _selectableSensors() {
    final seen = <String>{};
    final out = <Device>[];
    for (final d in widget.devices.all) {
      if (!d.isSensorDevice && !_isButtonDevice(d) && !d.isLock && !d.isVacuum)
        continue;
      if (seen.add(d.id)) out.add(d);
    }
    return out;
  }

  SensorTrigger _defaultTriggerFor(Device d) => defaultTriggerFor(d);

  void _toggleSensor(Device d) {
    setState(() {
      final idx = trigger.sensorTriggers.indexWhere((t) => t.sensorId == d.id);
      if (idx >= 0) {
        trigger.sensorTriggers.removeAt(idx);
        _pruneOrphanLockConditions();
        if (_capturingDeviceId == d.id) {
          _captureSub?.cancel();
          _capturingDeviceId = null;
        }
        _captured.remove(d.id);
      } else {
        trigger.sensorTriggers.add(_defaultTriggerFor(d));
        if (_isButtonDevice(d)) _startCapture(d);
      }
    });
  }

  /// Captura en vivo del botón: escucha device:state-changed del device
  /// hasta que llegue un lastKey.
  void _startCapture(Device d) {
    _captureSub?.cancel();
    _capturingDeviceId = d.id;
    _captureSub = widget.devices.socket.onDeviceChanged.listen((ev) {
      final matches = ev.deviceId == d.id || d.bindingIds.contains(ev.deviceId);
      if (!matches) return;
      final sensor = ev.sensor;
      if (sensor == null || !sensor.containsKey('lastKey')) return;
      if (!mounted) return;
      setState(() {
        final entries = trigger.sensorTriggers
            .where((e) => e.sensorId == d.id)
            .toList();
        for (final entry in entries) {
          entry.sensorValue = (sensor['lastKey'] as num?)?.toInt() ?? 0;
          final outlet = (sensor['outlet'] as num?)?.toInt();
          entry.sensorOutlet = outlet;
        }
        _captured.add(d.id);
        _capturingDeviceId = null;
      });
      _captureSub?.cancel();
      _captureSub = null;
    });
  }

  // === Builders =============================================================

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(text.toUpperCase(), style: CceText.section),
  );

  Widget _sensorGrid() {
    final sensors = _selectableSensors();
    if (sensors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No hay sensores disponibles', style: CceText.caption),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: TileSize.small.maxTileExtent,
        mainAxisExtent: TileSize.small.sensorTileHeight,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: sensors.length,
      itemBuilder: (context, i) {
        final d = sensors[i];
        final selected = trigger.sensorTriggers.any((t) => t.sensorId == d.id);
        // SensorTile no tiene onTap ni estado selected: la celda lo envuelve
        // en GestureDetector y dibuja el overlay de selección propio.
        return GestureDetector(
          onTap: () => _toggleSensor(d),
          child: Stack(
            children: [
              Positioned.fill(
                child: d.isLock
                    ? AbsorbPointer(
                        child: LockTile(
                          device: d,
                          service: widget.devices,
                          size: TileSize.small,
                        ),
                      )
                    : d.isVacuum
                    ? AbsorbPointer(
                        child: VacuumTile(
                          device: d,
                          service: widget.devices,
                          size: TileSize.small,
                        ),
                      )
                    : SensorTile(
                        device: d,
                        service: widget.devices,
                        size: TileSize.small,
                        interactive: false,
                      ),
              ),
              if (selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(CceRadii.hueCard),
                        border: Border.all(color: CceColors.accent, width: 2),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: CceColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const CceIcon(
                      CceIcons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Método de apertura activo para la cerradura [sensorId] ('' = cualquiera),
  /// leído de la condición lockOpenWay del trigger (misma semántica que el
  /// Dashboard: el método viaja como condición, el engine ya la evalúa).
  /// Scoped por sensorId (sensorId null en la condición = legacy, matchea).
  bool _isOpenWayCond(AutomationCondition c, String sensorId) =>
      c.type == 'sensor' &&
      c.field == 'lockOpenWay' &&
      (c.sensorId == null || c.sensorId == sensorId);

  String _lockOpenWayOf(String sensorId) {
    for (final c in trigger.conditions) {
      if (_isOpenWayCond(c, sensorId)) return (c.value as String?) ?? '';
    }
    return '';
  }

  void _setLockOpenWay(String sensorId, String way) {
    trigger.conditions.removeWhere((c) => _isOpenWayCond(c, sensorId));
    if (way.isNotEmpty) {
      trigger.conditions.add(
        AutomationCondition.sensor(
          sensorId: sensorId,
          field: 'lockOpenWay',
          value: way,
        ),
      );
    }
  }

  /// Purga condiciones lockOpenWay HUÉRFANAS (sin trigger de cerradura activo
  /// para su sensorId). Sin esto, deseleccionar la cerradura o cambiar el tipo
  /// de trigger dejaba una condición invisible que mataba la automatización en
  /// silencio (el engine la evalúa contra undefined → nunca dispara).
  void _pruneOrphanLockConditions() {
    final lockIds = trigger.sensorTriggers
        .where(
          (t) =>
              t.sensorField == 'lockEventKind' || t.sensorField == 'lockActor',
        )
        .map((t) => t.sensorId)
        .toSet();
    trigger.conditions.removeWhere(
      (c) =>
          c.type == 'sensor' &&
          c.field == 'lockOpenWay' &&
          !lockIds.contains(c.sensorId),
    );
  }

  Widget _triggerConfig(SensorTrigger t) {
    final d = widget.devices.byId(t.sensorId);
    final name = d != null ? widget.devices.displayName(d) : t.sensorId;

    Widget controls;
    switch (t.sensorField) {
      // ── Cerradura: evento (destraba/timbre/entra persona) + método ──
      case 'lockEventKind':
      case 'lockActor':
        final isActor = t.sensorField == 'lockActor';
        final eventKey = isActor
            ? 'actor'
            : (t.sensorValue == 'doorbell' ? 'doorbell' : 'unlock');
        final showWay = eventKey != 'doorbell';
        controls = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alguien destraba'),
                  selected: eventKey == 'unlock',
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    t.sensorField = 'lockEventKind';
                    t.sensorValue = 'unlock';
                  }),
                ),
                ChoiceChip(
                  label: const Text('Tocan el timbre'),
                  selected: eventKey == 'doorbell',
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    t.sensorField = 'lockEventKind';
                    t.sensorValue = 'doorbell';
                    _setLockOpenWay(t.sensorId, ''); // timbre: sin método
                  }),
                ),
                // El actor guardado SIEMPRE se muestra aunque la lista no
                // haya cargado (API caída) o ya no figure — sin esto, editar
                // un "Entra X" existente mostraba todo deseleccionado.
                for (final actor in [
                  if (isActor &&
                      t.sensorValue is String &&
                      !_actors.contains(t.sensorValue))
                    t.sensorValue as String,
                  ..._actors,
                ])
                  ChoiceChip(
                    label: Text('Entra $actor'),
                    selected: isActor && t.sensorValue == actor,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      t.sensorField = 'lockActor';
                      t.sensorValue = actor;
                    }),
                  ),
              ],
            ),
            if (showWay) ...[
              const SizedBox(height: 12),
              Text('CON', style: CceText.section),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (way, label) in _openWays)
                    ChoiceChip(
                      label: Text(label),
                      selected: _lockOpenWayOf(t.sensorId) == way,
                      showCheckmark: false,
                      onSelected: (_) =>
                          setState(() => _setLockOpenWay(t.sensorId, way)),
                    ),
                ],
              ),
            ],
          ],
        );
      // ── Robot aspiradora: estado que dispara ──
      case 'vacuumState':
        controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, label) in const [
              ('cleaning', 'Empieza a limpiar'),
              ('docked', 'Vuelve a la base'),
              ('error', 'Error / atascada'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: t.sensorValue == v,
                showCheckmark: false,
                onSelected: (_) => setState(() => t.sensorValue = v),
              ),
          ],
        );
      case 'motion':
        controls = CceSegmented<bool>(
          value: t.sensorValue == true,
          segments: const [
            CceSegment(value: true, label: 'Detecta'),
            CceSegment(value: false, label: 'Deja de detectar'),
          ],
          onChanged: (v) => setState(() => t.sensorValue = v),
        );
      case 'contact':
        controls = CceSegmented<bool>(
          value: t.sensorValue == true,
          segments: const [
            CceSegment(value: true, label: 'Se abre'),
            CceSegment(value: false, label: 'Se cierra'),
          ],
          onChanged: (v) => setState(() => t.sensorValue = v),
        );
      case 'lastKey':
        final capturing = _capturingDeviceId == t.sensorId;
        controls = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (capturing)
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CceColors.accent,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Tocá el botón ahora para capturarlo…',
                    style: CceText.caption,
                  ),
                ],
              )
            else if (_captured.contains(t.sensorId))
              Text(
                '${_pressLabel(t.sensorValue)} capturado ✓',
                style: CceText.caption.copyWith(color: CceColors.ok),
              )
            else
              Text(_pressLabel(t.sensorValue), style: CceText.caption),
            const SizedBox(height: 8),
            // Los valores de lastKey tienen nombre real (0=click, 1=doble,
            // 2=mantener); "Botón 0/1/2" se confundia con el NUMERO de tecla
            // de un dial de 4 botones (eso es sensorOutlet, abajo).
            Wrap(
              spacing: 8,
              children: [
                for (final k in _pressKinds.keys)
                  ChoiceChip(
                    label: Text(_pressKinds[k]!),
                    selected: t.sensorValue == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      t.sensorValue = k;
                      _captured.remove(t.sensorId);
                    }),
                  ),
                if (!capturing && d != null)
                  ActionChip(
                    avatar: const CceIcon(
                      CceIcons.handTap,
                      size: 14,
                      color: CceColors.accent,
                    ),
                    label: const Text('Capturar en vivo'),
                    onPressed: () => setState(() => _startCapture(d)),
                  ),
              ],
            ),
            // Dial/remote multi-tecla: QUÉ botón físico (sensorOutlet). Antes
            // no se podia elegir desde la app (solo capturando en vivo).
            if ((d?.outletCount ?? 1) > 1) ...[
              const SizedBox(height: 12),
              Text('QUÉ BOTÓN', style: CceText.section),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Cualquiera'),
                    selected: t.sensorOutlet == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => t.sensorOutlet = null),
                  ),
                  for (var o = 0; o < d!.outletCount; o++)
                    ChoiceChip(
                      label: Text('Botón ${o + 1}'),
                      selected: t.sensorOutlet == o,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        t.sensorOutlet = o;
                        _captured.remove(t.sensorId);
                      }),
                    ),
                ],
              ),
            ],
          ],
        );
      case 'temperature':
      case 'humidity':
        final isTemp = t.sensorField == 'temperature';
        final unit = isTemp ? '°' : '%';
        final step = isTemp ? 0.5 : 5.0;
        final value = (t.sensorValue as num?)?.toDouble() ?? 0;
        controls = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CceSegmented<String>(
              value: (t.sensorOperator == 'lt' || t.sensorOperator == 'lte')
                  ? 'lt'
                  : 'gt',
              segments: const [
                CceSegment(value: 'gt', label: 'Sube de'),
                CceSegment(value: 'lt', label: 'Baja de'),
              ],
              onChanged: (v) => setState(() => t.sensorOperator = v),
            ),
            const SizedBox(height: 10),
            _Stepper(
              valueText:
                  '${value == value.roundToDouble() ? value.round() : value}$unit',
              onMinus: () => setState(() => t.sensorValue = value - step),
              onPlus: () => setState(() => t.sensorValue = value + step),
            ),
            const SizedBox(height: 6),
            const Text(
              'Dispara al cruzar el umbral, no mientras se mantiene',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 12),
            ),
          ],
        );
      default:
        controls = Text(
          '${t.sensorField} = ${t.sensorValue}',
          style: CceText.caption,
        );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          controls,
        ],
      ),
    );
  }

  Widget _sensorSection() {
    return ListenableBuilder(
      listenable: widget.devices,
      builder: (context, _) {
        final delayIdx = _delaySteps.indexOf(trigger.sensorDelay);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Sensores (tocá para elegir)'),
            _sensorGrid(),
            for (final t in trigger.sensorTriggers) _triggerConfig(t),
            if (trigger.sensorTriggers.length > 1) ...[
              _sectionLabel('Disparar con'),
              CceSegmented<String>(
                value: trigger.sensorTriggersMode == 'all' ? 'all' : 'any',
                segments: const [
                  CceSegment(value: 'any', label: 'Cualquiera'),
                  CceSegment(value: 'all', label: 'Todos'),
                ],
                onChanged: (v) =>
                    setState(() => trigger.sensorTriggersMode = v),
              ),
            ],
            _sectionLabel('Esperar antes de ejecutar'),
            _Stepper(
              valueText: delayIdx >= 0
                  ? _delayLabels[delayIdx]
                  : '${trigger.sensorDelay} s',
              onMinus: () => setState(() {
                final i = delayIdx <= 0 ? 0 : delayIdx - 1;
                trigger.sensorDelay = _delaySteps[i];
              }),
              onPlus: () => setState(() {
                final i = delayIdx < 0
                    ? 0
                    : (delayIdx >= _delaySteps.length - 1
                          ? _delaySteps.length - 1
                          : delayIdx + 1);
                trigger.sensorDelay = _delaySteps[i];
              }),
            ),
            const SizedBox(height: 6),
            const Text(
              'Se cancela si la condición deja de cumplirse antes',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  DateTime _initialTime() {
    final t = trigger.time;
    if (t != null && RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
      final h = int.tryParse(t.substring(0, 2)) ?? 19;
      final m = int.tryParse(t.substring(3)) ?? 30;
      return DateTime(2024, 1, 1, h.clamp(0, 23), m.clamp(0, 59));
    }
    return DateTime(2024, 1, 1, 19, 30);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickWindow(bool from) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        trigger.fromTime = _fmt(picked);
      } else {
        trigger.toTime = _fmt(picked);
      }
    });
  }

  Widget _scheduleSection() {
    const dayLetters = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
    final crossesMidnight =
        trigger.fromTime != null &&
        trigger.toTime != null &&
        trigger.fromTime!.compareTo(trigger.toTime!) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Modo'),
        CceSegmented<String>(
          value: trigger.scheduleMode == 'interval' ? 'interval' : 'fixed',
          segments: const [
            CceSegment(value: 'fixed', label: 'Hora fija'),
            CceSegment(value: 'interval', label: 'Cada X min'),
          ],
          onChanged: (v) => setState(() {
            trigger.scheduleMode = v;
            if (v == 'fixed' && trigger.time == null) trigger.time = '19:30';
          }),
        ),
        if (trigger.scheduleMode != 'interval') ...[
          _sectionLabel('Hora'),
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: CceColors.surfaceHigh,
              borderRadius: BorderRadius.circular(CceRadii.control),
            ),
            child: CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.dark),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: _initialTime(),
                onDateTimeChanged: (dt) {
                  trigger.time =
                      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                },
              ),
            ),
          ),
        ] else ...[
          _sectionLabel('Intervalo'),
          _Stepper(
            valueText: 'Cada ${trigger.interval} min',
            onMinus: () => setState(() {
              final v = trigger.interval;
              trigger.interval = v <= 5 ? 1 : v - 5;
            }),
            onPlus: () => setState(() {
              final v = trigger.interval;
              trigger.interval = (v < 5 ? 5 : v + 5).clamp(1, 1440);
            }),
          ),
          _sectionLabel('Ventana horaria (opcional)'),
          Row(
            children: [
              _TimePill(
                label: trigger.fromTime == null
                    ? 'Desde…'
                    : 'Desde ${trigger.fromTime}',
                onTap: () => _pickWindow(true),
              ),
              const SizedBox(width: 8),
              _TimePill(
                label: trigger.toTime == null
                    ? 'Hasta…'
                    : 'Hasta ${trigger.toTime}',
                onTap: () => _pickWindow(false),
              ),
              if (trigger.fromTime != null || trigger.toTime != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Quitar ventana',
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: CceColors.textTertiary,
                  ),
                  onPressed: () => setState(() {
                    trigger.fromTime = null;
                    trigger.toTime = null;
                  }),
                ),
              ],
            ],
          ),
          if (crossesMidnight)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CceColors.info.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(CceRadii.pill),
                ),
                child: const Text(
                  'La ventana cruza la medianoche',
                  style: TextStyle(
                    color: CceColors.info,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
        // Días: visible en ambos modos — el server honra days también en
        // modo intervalo (daysPart del cron), así que ocultarlos acá hacía
        // invisible (y borrable) la restricción existente.
        _sectionLabel('Días'),
        Row(
          children: [
            for (var day = 0; day < 7; day++) ...[
              _DayToggle(
                label: dayLetters[day],
                selected: trigger.days.contains(day),
                onTap: () => setState(() {
                  final current = trigger.days.toList();
                  if (current.contains(day)) {
                    current.remove(day);
                  } else {
                    current.add(day);
                  }
                  current.sort();
                  trigger.days = current;
                }),
              ),
              if (day < 6) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Sin días seleccionados = todos los días',
          style: TextStyle(color: CceColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: CceColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(CceRadii.sheet),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CceColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Cuándo', style: CceText.title)),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Listo'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              CceSegmented<String>(
                value: trigger.type,
                segments: const [
                  CceSegment(
                    value: 'sensor',
                    label: 'Sensor',
                    icon: CceIcon(
                      CceIcons.sensors,
                      color: CceColors.triggerSensor,
                    ),
                  ),
                  CceSegment(
                    value: 'schedule',
                    label: 'Horario',
                    icon: CceIcon(
                      CceIcons.clock,
                      color: CceColors.triggerSchedule,
                    ),
                  ),
                  CceSegment(
                    value: 'manual',
                    label: 'Manual',
                    icon: CceIcon(
                      CceIcons.handTap,
                      color: CceColors.triggerManual,
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  trigger.type = v;
                  if (v == 'schedule' &&
                      trigger.scheduleMode != 'interval' &&
                      trigger.time == null) {
                    trigger.time = '19:30';
                  }
                }),
              ),
              if (trigger.type == 'sensor') _sensorSection(),
              if (trigger.type == 'schedule') _scheduleSection(),
              if (trigger.type == 'manual')
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Sin disparador automático: la ejecutás vos desde la '
                    'lista, el editor o el agente.',
                    style: CceText.caption,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
  });

  final String valueText;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(icon: Icons.remove, onTap: onMinus),
        Container(
          constraints: const BoxConstraints(minWidth: 110),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            valueText,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _RoundIconButton(icon: Icons.add, onTap: onPlus),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CceRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: CceColors.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: CceColors.textPrimary),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CceRadii.pill),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? CceColors.accent.withValues(alpha: 0.24)
              : CceColors.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? CceColors.accent : CceColors.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? CceColors.textPrimary : CceColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CceRadii.pill),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          border: Border.all(color: CceColors.stroke),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: CceColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// ¿Es un control de botones (pulsador, remote, dial)?
bool isButtonDevice(Device d) {
  final t = d.type.toLowerCase();
  return t.contains('button') ||
      t.contains('switch') ||
      t.contains('remote') ||
      t.contains('dial');
}

/// Trigger por defecto para un dispositivo, con el CAMPO y el VALOR que le
/// corresponden.
///
/// Vive fuera del sheet porque no es sólo suyo: la hoja de automatizaciones del
/// device también necesita armar un trigger inicial, y la primera versión lo
/// reimplementó a ojo — con `sensorValue: true` para un `lastKey`, que espera un
/// número (0 click / 1 doble / 2 mantenido). Eso dejaba el tab Sensor en gris.
SensorTrigger defaultTriggerFor(Device d) {
  if (d.isLock) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'lockEventKind',
      sensorValue: 'unlock',
    );
  }
  if (d.isVacuum) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'vacuumState',
      sensorValue: 'cleaning',
    );
  }
  if (isButtonDevice(d)) {
    // OJO: para lastKey el valor es el TIPO de pulsación (0/1/2), NO un bool.
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'lastKey',
      sensorValue: 0,
    );
  }
  if (d.isContactSensor) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'contact',
      sensorValue: true,
    );
  }
  if (d.isMotionSensor) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'motion',
      sensorValue: true,
    );
  }
  if (d.sensor?.temperature != null) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'temperature',
      sensorValue: d.sensor!.temperature!.roundToDouble(),
      sensorOperator: 'gt',
    );
  }
  if (d.sensor?.humidity != null) {
    return SensorTrigger(
      sensorId: d.id,
      sensorField: 'humidity',
      sensorValue: 60,
      sensorOperator: 'gt',
    );
  }
  return SensorTrigger(
    sensorId: d.id,
    sensorField: 'motion',
    sensorValue: true,
  );
}
