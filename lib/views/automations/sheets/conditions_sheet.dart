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
  /// los Hue de movimiento traen lectura de luz ambiente).
  List<Device> _brightnessSensors() {
    return widget.devices.sensors
        .where((d) => d.sensor?.brightness != null || d.isMotionSensor)
        .toList();
  }

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
      // sensorBrightness).
      trigger.conditions.add(AutomationCondition.sensor(
        sensorId: chosen!.id,
        field: 'brightness',
        value: 'darker',
      ));
    });
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addTimeWindow() async {
    final from = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 20, minute: 0),
      helpText: 'Desde',
    );
    if (from == null || !mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Hasta',
    );
    if (to == null) return;
    setState(() {
      trigger.conditions.add(AutomationCondition.timeWindow(
        fromTime: _fmt(from),
        toTime: _fmt(to),
      ));
    });
  }

  Widget _conditionRow(AutomationCondition c, int index) {
    final isTime = c.type == 'timeWindow';
    return Container(
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
            width: 40,
            height: 40,
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
