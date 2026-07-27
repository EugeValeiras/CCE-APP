import 'package:flutter/material.dart';

import '../models/automation.dart';
import '../models/device.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../views/automations/automation_editor_page.dart';
import '../views/automations/automation_phrases.dart';

/// Automatizaciones que dispara ESTE dispositivo, con acceso a crear una nueva
/// ya apuntada a él.
///
/// Vive en un solo lugar porque lo abren las cuatro pantallas de detalle
/// (movimiento, apertura, botones y cerradura): sin esto, para saber qué hace
/// un sensor había que ir a la lista general de automatizaciones y leer los
/// triggers uno por uno.
class DeviceAutomationsSheet extends StatefulWidget {
  const DeviceAutomationsSheet({
    super.key,
    required this.device,
    required this.devices,
    required this.automations,
  });

  final Device device;
  final DevicesService devices;
  final AutomationsService automations;

  /// Abre la hoja. Devuelve cuando el usuario la cierra.
  static Future<void> show(
    BuildContext context, {
    required Device device,
    required DevicesService devices,
    required AutomationsService automations,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CceRadii.sheet),
        ),
      ),
      builder: (_) => DeviceAutomationsSheet(
        device: device,
        devices: devices,
        automations: automations,
      ),
    );
  }

  @override
  State<DeviceAutomationsSheet> createState() => _DeviceAutomationsSheetState();
}

class _DeviceAutomationsSheetState extends State<DeviceAutomationsSheet> {
  /// Las que tienen a este device como DISPARADOR.
  ///
  /// Se busca por `sensorTriggers[].sensorId` y también por el id de binding:
  /// las automatizaciones viejas guardaron el binding (`ewelink_123`) antes de
  /// que existieran los ids canónicos, y siguen siendo válidas.
  List<Automation> _forDevice() {
    final ids = <String>{widget.device.id, ...widget.device.bindingIds};
    return widget.automations.automations
        .where(
          (a) => a.trigger.sensorTriggers.any((t) => ids.contains(t.sensorId)),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _abrir(Automation a) async {
    await Navigator.of(context).push(
      MaterialPageRoute<Object?>(
        builder: (_) => AutomationEditorPage(
          service: widget.automations,
          devices: widget.devices,
          draft: a,
          isNew: false,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Crea una automatización YA apuntada a este dispositivo: el sentido de
  /// entrar por acá es no tener que volver a elegirlo en el wizard.
  Future<void> _crear() async {
    // Se parte de Automation.blank() y NO de un mapa a mano: ese factory pone
    // los defaults que el editor y el server dan por sentados (id client-side,
    // icon, mode). Armarlo a mano con id vacío abría el editor en gris.
    final base = Automation.blank().toJson();
    final draft = Automation.fromJson({
      ...base,
      'trigger': {
        ...(base['trigger'] as Map? ?? const {}),
        'type': 'sensor',
        'sensorTriggers': [
          {
            'sensorId': widget.device.id,
            'sensorField': _campoPorDefecto(),
            'sensorValue': true,
          },
        ],
      },
    });
    await Navigator.of(context).push(
      MaterialPageRoute<Object?>(
        builder: (_) => AutomationEditorPage(
          service: widget.automations,
          devices: widget.devices,
          draft: draft,
          isNew: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// El campo que este device dispara naturalmente, para que el editor abra ya
  /// en el caso típico en vez de en blanco.
  String _campoPorDefecto() {
    final d = widget.device;
    if (d.isContactSensor) return 'contact';
    if (d.isMotionSensor) return 'motion';
    if (d.isLock) return 'lockEventAt';
    if (d.isSwitch) return 'lastKey';
    return 'motion';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.automations,
      builder: (context, _) {
        final list = _forDevice();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CceColors.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Automatizaciones', style: CceText.title),
                const SizedBox(height: 4),
                Text(
                  list.isEmpty
                      ? 'Este dispositivo todavía no dispara ninguna'
                      : '${list.length} ${list.length == 1 ? "usa" : "usan"} este dispositivo',
                  style: CceText.caption,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return _AutomationRow(
                        automation: a,
                        devices: widget.devices,
                        onTap: () => _abrir(a),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _crear,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear automatización'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
    required this.automation,
    required this.devices,
    required this.onTap,
  });

  final Automation automation;
  final DevicesService devices;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final apagada = !automation.enabled;
    return Material(
      color: CceColors.cardOff,
      borderRadius: BorderRadius.circular(CceRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CceRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      automation.name.isEmpty ? 'Sin nombre' : automation.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(
                        fontSize: 15,
                        color: apagada
                            ? CceColors.textTertiary
                            : CceColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // La misma frase legible que usa la lista general, para
                      // que una automatización se lea igual en los dos lados.
                      triggerPhrase(automation, devices),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption,
                    ),
                  ],
                ),
              ),
              if (apagada)
                Text(
                  'OFF',
                  style: CceText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CceColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
