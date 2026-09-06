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

  /// Modo prueba (CCE#122). null = todavía no se leyó: el switch espera en vez
  /// de mostrar "apagado", que sería una promesa de que la alarma va a sonar.
  bool? _testMode;
  bool _savingTestMode = false;

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
    // El modo prueba se lee aparte y es best-effort: que un backend viejo no
    // conozca el endpoint no puede dejar sin configurar los sensores.
    _loadTestMode();
    try {
      final triggers = await _api.getSensorAlarmTriggers();
      if (!mounted) return;
      setState(() => _triggers = triggers);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _loadTestMode() async {
    try {
      final status = await _api.getAlarmStatus();
      if (!mounted) return;
      setState(() => _testMode = status.testMode);
    } catch (_) {
      // Se queda en null: el switch no se dibuja antes que la verdad.
    }
  }

  Future<void> _toggleTestMode(bool enabled) async {
    if (_savingTestMode) return;
    final previous = _testMode;
    setState(() {
      _testMode = enabled;
      _savingTestMode = true;
    });
    try {
      final saved = await _api.setAlarmTestMode(enabled);
      if (!mounted) return;
      setState(() => _testMode = saved);
    } catch (_) {
      if (!mounted) return;
      // Revertir importa más acá que en cualquier otro switch: dejarlo en
      // "activado" sin que el backend lo haya guardado hace creer que la
      // alarma está muda cuando en realidad va a sonar.
      setState(() => _testMode = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude cambiar el modo prueba')),
      );
    } finally {
      if (mounted) setState(() => _savingTestMode = false);
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

  /// El modo prueba va PRIMERO y fuera de todos los short-circuits.
  ///
  /// Estaba dentro del ListView final, después de los returns tempranos de "no
  /// hay sensores" y de `_failed`: si `GET /config/sensor-alarm-triggers`
  /// fallaba, la pantalla mostraba "No pude leer qué sensores disparan la
  /// alarma" y el toggle NO se dibujaba —aunque su propia lectura hubiera
  /// funcionado y el modo estuviera activo—. Como no hay otro lugar en la App
  /// donde apagarlo, la alarma quedaba muda sin forma de revertirla desde el
  /// celular. No depende de `_triggers`: no puede desaparecer con ellos.
  Widget _buildBody() {
    final contacts = _group(true);
    final motions = _group(false);
    final sinSensores = contacts.isEmpty && motions.isEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          CceSpace.lg, CceSpace.sm, CceSpace.lg, CceSpace.xxl),
      children: [
        ..._testModeSection(),
        if (_failed)
          _Aviso(
            texto: 'No pude leer qué sensores disparan la alarma.',
            onReintentar: _load,
          )
        else if (sinSensores)
          const _Aviso(
            texto: 'La casa no tiene sensores de apertura ni de movimiento.',
          )
        else ...[
          Text(
            'Con la alarma armada, sólo estos sensores hacen sonar la sirena.',
            style: CceText.caption,
          ),
          if (contacts.isNotEmpty) ..._section('Aperturas', contacts),
          if (motions.isNotEmpty) ..._section('Movimiento', motions),
        ],
      ],
    );
  }

  /// Modo prueba: el disparo llega sólo como notificación (CCE#122).
  ///
  /// Va ACÁ, al lado de qué sensores disparan, porque es la otra mitad de la
  /// misma pregunta: qué hace la alarma cuando salta. Y el texto lo dice sin
  /// vueltas — es un toggle manual, no vence solo, y la única defensa contra
  /// olvidarlo prendido es que se lea.
  List<Widget> _testModeSection() {
    final testMode = _testMode;
    if (testMode == null) return const [];
    return [
      const SectionHeader(title: 'Modo prueba'),
      Container(
        height: kRowHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CceColors.strokeSoft)),
        ),
        child: Row(
          children: [
            Icon(
              testMode ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              size: 20,
              color: testMode ? _amber : CceColors.textTertiary,
            ),
            SizedBox(width: CceSpace.md),
            const Expanded(
              child: Text('La alarma no suena', style: CceText.body),
            ),
            SizedBox(width: CceSpace.sm),
            CceSwitch(
              value: testMode,
              accent: _amber,
              onChanged: _savingTestMode ? null : _toggleTestMode,
            ),
          ],
        ),
      ),
      SizedBox(height: CceSpace.sm),
      Text(
        testMode
            ? 'ACTIVADO: la alarma sigue armada y sigue disparando, pero el '
                'aviso llega sólo como notificación — sin sirena, sin pantalla '
                'roja y sin repetirse. Se apaga a mano.'
            : 'Para acostumbrarte a la alarma sin que suene: armala, salí y '
                'hacela saltar. El aviso te llega igual, en silencio.',
        style: CceText.caption.copyWith(
          color: testMode ? _amber : CceColors.textTertiary,
        ),
      ),
      SizedBox(height: CceSpace.md),
    ];
  }

  /// Ámbar y no rojo: en la pantalla de la alarma el rojo ya significa
  /// "armada", y mezclarlos sería peor que no decir nada.
  static const Color _amber = Color(0xFFFFB300);

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

/// Un estado vacío o con error, DENTRO de la lista y no en lugar de ella: lo
/// que va arriba (el modo prueba) tiene que seguir a la vista.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.onReintentar});

  final String texto;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: CceSpace.lg, vertical: CceSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: CceText.body.copyWith(color: CceColors.textTertiary),
            ),
            if (onReintentar != null) ...[
              SizedBox(height: CceSpace.lg),
              TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
            ],
          ],
        ),
      );
}
