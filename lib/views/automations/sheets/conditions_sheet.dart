import 'package:flutter/material.dart';

import '../../../models/automation.dart';
import '../../../models/device.dart';
import '../../../services/devices_service.dart';
import '../../../theme/cce_icons.dart';
import '../../../theme/cce_tokens.dart';
import '../../../theme/components/cce_segmented.dart';
import '../automation_phrases.dart';

/// Sheet SOLO SI: condiciones adicionales (AND) + condición de alarma.
/// Muta `draft.trigger` directamente (el draft es una copia descartable).
Future<bool> showConditionsSheet(
  BuildContext context, {
  required Automation draft,
  required DevicesService devices,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ConditionsSheet(draft: draft, devices: devices),
  );
  return result == true;
}

class _ConditionsSheet extends StatefulWidget {
  const _ConditionsSheet({required this.draft, required this.devices});

  final Automation draft;
  final DevicesService devices;

  @override
  State<_ConditionsSheet> createState() => _ConditionsSheetState();
}

class _ConditionsSheetState extends State<_ConditionsSheet> {
  AutomationTrigger get trigger => widget.draft.trigger;

  /// Sensores candidatos para "Está oscuro" (reportan brightness o motion —
  /// los Hue de movimiento traen lectura de luz ambiente— o miden lux).
  List<Device> _brightnessSensors() {
    return widget.devices.sensors
        .where((d) =>
            d.sensor?.brightness != null ||
            d.isMotionSensor ||
            _measuresLux(d))
        .toList();
  }

  /// CCE#112 — ¿mide lux? Por capability (o por lectura, para un device que
  /// todavía no declara). Un sensor de sólo iluminancia no reporta jamás el
  /// binario `brightness` en el evento: su condición tiene que ser numérica.
  bool _measuresLux(Device d) =>
      d.hasCapability('illuminance') || d.sensor?.lux != null;

  Future<void> _addDarkCondition() async {
    final candidates = _brightnessSensors();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay sensores con lectura de luz ambiente')),
      );
      return;
    }
    Device? chosen;
    if (candidates.length == 1) {
      chosen = candidates.first;
    } else {
      chosen = await showModalBottomSheet<Device>(
        context: context,
        backgroundColor: CceColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
        ),
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('¿Qué sensor mide la luz?', style: CceText.title),
              ),
              for (final d in candidates)
                ListTile(
                  leading: const CceIcon(CceIcons.moon,
                      color: CceColors.textSecondary),
                  title: Text(widget.devices.displayName(d),
                      style: CceText.body),
                  onTap: () => Navigator.of(sheetContext).pop(d),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen == null) return;
    setState(() {
      // Condiciones nuevas SIEMPRE a conditions[] (nunca al legacy
      // sensorBrightness). Un sensor que mide lux escribe el umbral real
      // («luz < 30 lx», el del pasillo); el binario queda para los que sólo
      // tienen brightness (CCE#112).
      trigger.conditions.add(
        _measuresLux(chosen!)
            ? AutomationCondition.sensor(
                sensorId: chosen.id,
                field: 'lux',
                value: 30,
                operator: 'lt',
              )
            : AutomationCondition.sensor(
                sensorId: chosen.id,
                field: 'brightness',
                value: 'darker',
              ),
      );
    });
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parse(String? hhmm, TimeOfDay fallback) {
    if (hhmm == null || !RegExp(r'^\d{2}:\d{2}$').hasMatch(hhmm)) {
      return fallback;
    }
    return TimeOfDay(
      hour: int.tryParse(hhmm.substring(0, 2))?.clamp(0, 23) ?? fallback.hour,
      minute: int.tryParse(hhmm.substring(3))?.clamp(0, 59) ?? fallback.minute,
    );
  }

  /// Agrega (index null) o EDITA una ventana horaria. Antes las condiciones
  /// solo se podian crear y borrar: para corregir una hora habia que borrarla
  /// y rehacerla.
  Future<void> _editTimeWindow({int? index}) async {
    final existing = index == null ? null : trigger.conditions[index];
    final from = await showTimePicker(
      context: context,
      initialTime:
          _parse(existing?.fromTime, const TimeOfDay(hour: 20, minute: 0)),
      helpText: 'Desde',
    );
    if (from == null || !mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime:
          _parse(existing?.toTime, const TimeOfDay(hour: 7, minute: 0)),
      helpText: 'Hasta',
    );
    if (to == null) return;
    setState(() {
      final cond = AutomationCondition.timeWindow(
        fromTime: _fmt(from),
        toTime: _fmt(to),
      );
      if (index == null) {
        trigger.conditions.add(cond);
      } else {
        trigger.conditions[index] = cond;
      }
    });
  }

  Future<void> _addTimeWindow() => _editTimeWindow();

  Widget _conditionRow(AutomationCondition c, int index) {
    // La condición lockOpenWay (método de apertura) se edita en el selector
    // "CON" del trigger de cerradura — acá se muestra informativa, sin trash
    // (quitar el método = elegir "Cualquiera" en CUÁNDO).
    if (c.type == 'sensor' && c.field == 'lockOpenWay') {
      return Container(
        height: 52,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: CceColors.surfaceHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(CceRadii.control),
        ),
        child: Row(
          children: [
            const Icon(Icons.fingerprint,
                size: 18, color: CceColors.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${conditionPhrase(c, widget.devices)} — se edita en CUÁNDO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CceText.caption,
              ),
            ),
          ],
        ),
      );
    }
    final isTime = c.type == 'timeWindow';
    final isBrightness = c.type == 'sensor' && c.field == 'brightness';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isTime
          ? () => _editTimeWindow(index: index)
          : isBrightness
              // Luz ambiente: alterna oscuro ↔ con luz (los dos unicos valores).
              ? () => setState(() {
                    final next = c.value == 'darker' ? 'brighter' : 'darker';
                    trigger.conditions[index] = AutomationCondition.sensor(
                      sensorId: c.sensorId ?? '',
                      field: 'brightness',
                      value: next,
                    );
                  })
              : null,
      child: Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.control),
      ),
      child: Row(
        children: [
          CceIcon(
            isTime ? CceIcons.clock : CceIcons.moon,
            size: 18,
            color: CceColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              conditionPhrase(c, widget.devices),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.body,
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Quitar condición',
              icon: const CceIcon(CceIcons.trash,
                  size: 18, color: CceColors.textTertiary),
              onPressed: () =>
                  setState(() => trigger.conditions.removeAt(index)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: CceColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
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
                  const Expanded(child: Text('Solo si', style: CceText.title)),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Listo'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('ALARMA', style: CceText.section),
              const SizedBox(height: 10),
              CceSegmented<String>(
                value: trigger.alarmCondition,
                segments: const [
                  CceSegment(value: 'any', label: 'Cualquiera'),
                  CceSegment(value: 'armed', label: 'Armada'),
                  CceSegment(value: 'disarmed', label: 'Desarmada'),
                ],
                onChanged: (v) => setState(() => trigger.alarmCondition = v),
              ),
              const SizedBox(height: 24),
              Text('CONDICIONES', style: CceText.section),
              const SizedBox(height: 10),
              if (trigger.conditions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Sin condiciones: la automatización se dispara siempre '
                    'que ocurra el CUÁNDO.',
                    style: CceText.caption,
                  ),
                ),
              for (var i = 0; i < trigger.conditions.length; i++)
                _conditionRow(trigger.conditions[i], i),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ActionChip(
                    avatar: const CceIcon(CceIcons.moon,
                        size: 16, color: CceColors.accent),
                    label: const Text('Está oscuro'),
                    onPressed: _addDarkCondition,
                  ),
                  ActionChip(
                    avatar: const CceIcon(CceIcons.clock,
                        size: 16, color: CceColors.accent),
                    label: const Text('Franja horaria'),
                    onPressed: _addTimeWindow,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
