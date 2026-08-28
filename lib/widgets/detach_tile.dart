import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_switch.dart';

/// Interruptor del MODO DETACH de un relé (CCE#39).
///
/// Con el detach puesto, la tecla de la pared deja de cortar la luz y pasa a
/// ser un pulsador para automatizaciones. Es configuración que se escribe en el
/// hardware de la casa, no un estado efímero, así que el texto dice qué cambia
/// ANTES de tocarlo y no después.
///
/// Se dibuja sólo si el device declara `detach_relay`: [Device.supportsDetach].
/// En cualquier otro device devuelve un SizedBox vacío, así el llamador puede
/// meterlo en la columna sin preguntarse nada.
///
/// Toggle OPTIMISTA con revert y aviso si falla, como el disparo de alarma de
/// sensor_detail_screen. El estado real vuelve por WS y pisa el optimista en
/// cuanto llega.
class DetachTile extends StatefulWidget {
  const DetachTile({super.key, required this.device, required this.service});

  final Device device;
  final DevicesService service;

  @override
  State<DetachTile> createState() => _DetachTileState();
}

class _DetachTileState extends State<DetachTile> {
  /// Valor optimista mientras el PUT está en vuelo. null = manda el backend.
  bool? _pending;
  bool _saving = false;

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  Future<void> _toggle(bool next) async {
    if (_saving) return;
    setState(() {
      _pending = next;
      _saving = true;
    });
    try {
      await widget.service.invokeCapability(_device, 'setDetach', {
        'detached': next,
      });
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pending = null; // revert: vuelve a mandar lo que dice el backend
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pude cambiar el modo de la tecla'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _device;
    if (!d.supportsDetach) return const SizedBox.shrink();

    final backend = d.state.detached;
    // El optimista se descarta apenas el backend confirma el mismo valor: si no,
    // un revert del device (que ignoró el comando) quedaría tapado por la UI.
    final value = (_pending != null && _pending != backend)
        ? _pending!
        : (backend ?? false);

    return Container(
      padding: EdgeInsets.all(CceSpace.md),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Tecla como botón', style: CceText.body),
              ),
              SizedBox(width: CceSpace.sm),
              CceSwitch(
                value: value,
                // Deshabilitado mientras no se sabe de qué estado parte: mejor
                // eso que un interruptor que arranca en una posición inventada.
                onChanged: backend == null || _saving ? null : _toggle,
              ),
            ],
          ),
          SizedBox(height: CceSpace.xs),
          Text(
            value
                ? 'La tecla de la pared no corta la luz: es un botón para automatizaciones.'
                : 'La tecla de la pared corta la luz, como un interruptor común.',
            style: CceText.caption,
          ),
        ],
      ),
    );
  }
}
