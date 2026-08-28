import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_switch.dart';
import '../theme/components/section_header.dart';
import '../utils/alarm_triggers.dart';
import 'alarm_view.dart' show protectedSensors;

/// Qué sensores pueden hacer sonar la alarma, con un switch por sensor.
///
/// Es la pantalla del engranaje de la alarma. Lista TODOS los sensores de
/// apertura y movimiento de la casa (sin filtrar por el flag: acá se elige),
/// mientras que "qué protege" muestra sólo los marcados.
///
/// El mapa de disparos se lee UNA vez al abrir y alimenta toda la lista: una
/// lectura por fila serían quince GET idénticos para el mismo mapa. Mientras
/// no se sabe el estado de partida los switches están deshabilitados — un
/// switch en "no" que en realidad no se leyó es una mentira sobre la alarma.
class AlarmSensorsScreen extends StatefulWidget {
  const AlarmSensorsScreen({super.key, required this.devices, this.api});

  final DevicesService devices;

  /// Inyectable para tests; en producción sale de la config del inventario.
  final ApiService? api;

  @override
  State<AlarmSensorsScreen> createState() => _AlarmSensorsScreenState();
}

class _AlarmSensorsScreenState extends State<AlarmSensorsScreen> {
  late final ApiService _api = widget.api ?? ApiService(widget.devices.config);

  /// null = todavía no se sabe (cargando o falló la lectura).
  Map<String, bool>? _triggers;
  bool _failed = false;

  /// Ids canónicos con un PUT en vuelo: su switch no acepta otro toque.
  final Set<String> _saving = {};

  static const double kRowHeight = 52;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final triggers = await _api.getSensorAlarmTriggers();
      if (!mounted) return;
      setState(() => _triggers = triggers);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _toggle(Device device, bool fires) async {
    final current = _triggers;
    if (current == null || _saving.contains(device.id)) return;

    // Optimista: el switch salta ya y se revierte si el PUT falla.
    final optimistic = Map<String, bool>.from(current);
    if (fires) {
      optimistic[device.id] = true;
    } else {
      for (final key in firingKeys(device, current)) {
        optimistic.remove(key);
      }
      optimistic.remove(device.id);
    }
    setState(() {
      _triggers = optimistic;
      _saving.add(device.id);
    });

    try {
      final saved = await writeFiresAlarm(_api, device, current, fires: fires);
      if (!mounted) return;
      setState(() => _triggers = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _triggers = current); // revert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pude cambiar «${widget.devices.displayName(device)}»',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(device.id));
    }
  }

  /// Orden ESTABLE (alfabético dentro de cada grupo), no el de "qué protege":
  /// ahí las aperturas abiertas suben porque son lo urgente, pero acá una
  /// puerta que se abre mientras configurás te movería el switch bajo el dedo.
  List<Device> _group(bool contact) {
    final list = protectedSensors(widget.devices.all)
        .where((d) => d.isContactSensor == contact)
        .toList();
    list.sort((a, b) => widget.devices
        .displayName(a)
        .toLowerCase()
        .compareTo(widget.devices.displayName(b).toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        backgroundColor: CceColors.bg,
        // Sin flecha de atrás: se vuelve con el swipe nativo de iOS (mismo
        // canon que el detalle de habitación y el de sensor).
        automaticallyImplyLeading: false,
        titleSpacing: CceSpace.lg,
        title: const Text('Sensores de la alarma', style: CceText.title),
      ),
      body: ListenableBuilder(
        listenable: widget.devices,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final contacts = _group(true);
    final motions = _group(false);

    if (contacts.isEmpty && motions.isEmpty) {
      return _Centered(
        child: Text(
          'La casa no tiene sensores de apertura ni de movimiento.',
          textAlign: TextAlign.center,
          style: CceText.body.copyWith(color: CceColors.textTertiary),
        ),
      );
    }

    if (_failed) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No pude leer qué sensores disparan la alarma.',
              textAlign: TextAlign.center,
              style: CceText.body.copyWith(color: CceColors.textTertiary),
            ),
            SizedBox(height: CceSpace.lg),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          CceSpace.lg, CceSpace.sm, CceSpace.lg, CceSpace.xxl),
      children: [
        Text(
          'Con la alarma armada, sólo estos sensores hacen sonar la sirena.',
          style: CceText.caption,
        ),
        if (contacts.isNotEmpty) ..._section('Aperturas', contacts),
        if (motions.isNotEmpty) ..._section('Movimiento', motions),
      ],
    );
  }

  List<Widget> _section(String title, List<Device> sensors) {
    final triggers = _triggers;
    final on = triggers == null
        ? 0
        : sensors.where((d) => firesAlarm(d, triggers)).length;
    return [
      SectionHeader(
        title: title,
        counter: triggers == null ? null : '$on de ${sensors.length}',
      ),
      for (final d in sensors) _row(d, triggers),
    ];
  }

  Widget _row(Device device, Map<String, bool>? triggers) {
    final isContact = device.isContactSensor;
    final active = isContact
        ? device.sensor?.contact == true
        : device.sensor?.motion == true;
    final String svg;
    final Color activeColor;
    if (isContact) {
      svg = active ? CceIcons.doorOpen : CceIcons.doorClosed;
      activeColor = CceColors.contact;
    } else {
      svg = active ? CceIcons.personStanding : CceIcons.footprints;
      activeColor = CceColors.motion;
    }
    final fires = triggers != null && firesAlarm(device, triggers);

    return Container(
      height: kRowHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CceColors.strokeSoft)),
      ),
      child: Row(
        children: [
          CceIcon(
            svg,
            size: 20,
            color: active ? activeColor : CceColors.textTertiary,
            emboss: false,
          ),
          SizedBox(width: CceSpace.md),
          Expanded(
            child: Text(
              widget.devices.displayName(device),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.body,
            ),
          ),
          SizedBox(width: CceSpace.sm),
          CceSwitch(
            value: fires,
            accent: CceColors.danger,
            // Deshabilitado mientras no se sabe de qué estado parte, y
            // mientras su propio PUT está en vuelo.
            onChanged: triggers == null || _saving.contains(device.id)
                ? null
                : (v) => _toggle(device, v),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: CceSpace.xxl),
          child: child,
        ),
      );
}
