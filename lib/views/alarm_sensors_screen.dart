import 'package:flutter/material.dart';

import '../models/alarm_mode.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_switch.dart';
import '../theme/components/section_header.dart';
import '../utils/alarm_triggers.dart';
import 'alarm_view.dart' show protectedSensors;

/// Qué sensores pueden hacer sonar la alarma, y EN QUÉ TIPO de alarma.
///
/// Es la pantalla del engranaje de la alarma. Lista TODOS los sensores de
/// apertura y movimiento de la casa (sin filtrar por el flag: acá se elige),
/// mientras que "qué protege" muestra sólo los marcados.
///
/// Cada sensor marcado responde DOS preguntas (CCE#133): si participa —el
/// switch— y en cuál de las dos alarmas —el chip—. «Perímetro» suena en las
/// dos; «Interior», sólo en la total. El chip aparece únicamente cuando el
/// switch está prendido: un nivel para un sensor que no participa no
/// significa nada y sólo agrega una decisión falsa a la pantalla.
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

  /// En qué tipo de alarma participa cada sensor (CCE#133). Vacío contra una
  /// API vieja: sin niveles todo vale `interior`, que es como era antes.
  Map<String, String> _levels = const {};

  /// ¿El backend conoce los tipos de alarma? null = todavía no se sabe.
  /// Contra una API vieja los chips NO se dibujan: un selector cuyo PUT 404ea
  /// siempre es peor que no ofrecerlo.
  bool? _supportsModes;
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
    _loadLevels();
    try {
      final triggers = await _api.getSensorAlarmTriggers();
      if (!mounted) return;
      setState(() => _triggers = triggers);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Los niveles, best-effort y aparte: un backend viejo no conoce el
  /// endpoint, y eso no puede dejar sin configurar la participación — que es
  /// lo que ya funcionaba antes de CCE#133.
  Future<void> _loadLevels() async {
    try {
      final levels = await _api.getSensorAlarmLevels();
      if (!mounted) return;
      setState(() => _levels = levels);
    } catch (_) {
      // Se queda vacío; el soporte lo decide `_loadTestMode` con el estado.
    }
  }

  Future<void> _loadTestMode() async {
    try {
      final status = await _api.getAlarmStatus();
      if (!mounted) return;
      setState(() {
        _testMode = status.testMode;
        // El ESTADO es lo que dice si el backend conoce los tipos: que el mapa
        // de niveles venga vacío es ambiguo —puede ser una casa sin nada
        // configurado—, pero un `mode` en la respuesta no lo es.
        _supportsModes = status.mode != null;
      });
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

    // Al PRENDER se manda el nivel SUGERIDO por lo que el sensor mide —una
    // apertura es perímetro, un movimiento es interior—, no el default. Sin
    // esto una puerta recién marcada quedaría en `interior`, o sea fuera de la
    // alarma perimetral, que es justo la que uno arma para dormir.
    final level = fires ? suggestedLevel(device) : null;

    // Optimista: el switch salta ya y se revierte si el PUT falla.
    final optimistic = Map<String, bool>.from(current);
    final optimisticLevels = Map<String, String>.from(_levels);
    final previousLevels = _levels;
    if (fires) {
      optimistic[device.id] = true;
      if (level != null) optimisticLevels[device.id] = level.wire;
    } else {
      // El nivel se va con la marca, en el mismo movimiento: es la contracara
      // de lo que hace el backend al recibir `fires:false`. No se ve —el chip
      // ya desaparece porque el switch quedó apagado—, pero dejar el mapa
      // local diciendo algo distinto del config es la clase de desfasaje que
      // muerde recién cuando alguien lo lee desde otro lado.
      for (final key in firingKeys(device, current)) {
        optimistic.remove(key);
        optimisticLevels.remove(key);
      }
      optimistic.remove(device.id);
      optimisticLevels.remove(device.id);
    }
    setState(() {
      _triggers = optimistic;
      _levels = optimisticLevels;
      _saving.add(device.id);
    });

    try {
      final saved = await writeFiresAlarm(
        _api,
        device,
        current,
        fires: fires,
        level: level,
      );
      if (!mounted) return;
      setState(() => _triggers = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _triggers = current; // revert
        _levels = previousLevels;
      });
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

  /// Alterna el nivel de un sensor entre perímetro e interior (CCE#133).
  ///
  /// Sólo hay dos valores, así que el chip es un toggle: no hay menú que
  /// abrir ni valor oculto. Lo que cambia es a qué alarma responde el sensor,
  /// y el chip lo dice con todas las letras antes y después del toque.
  Future<void> _cycleLevel(Device device) async {
    final triggers = _triggers;
    if (triggers == null || _saving.contains(device.id)) return;

    final actual = levelOf(device, _levels);
    final siguiente = actual == SensorAlarmLevel.perimeter
        ? SensorAlarmLevel.interior
        : SensorAlarmLevel.perimeter;

    final previous = _levels;
    final optimistic = Map<String, String>.from(_levels);
    optimistic[device.id] = siguiente.wire;
    for (final binding in device.bindingIds) {
      optimistic.remove(binding);
    }
    setState(() {
      _levels = optimistic;
      _saving.add(device.id);
    });

    try {
      final saved = await writeSensorAlarmLevel(
        _api,
        device,
        previous,
        level: siguiente,
      );
      if (!mounted) return;
      setState(() => _levels = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _levels = previous); // revert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pude cambiar el nivel de «${widget.devices.displayName(device)}»',
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
            _supportsModes == true
                ? 'Sólo estos sensores hacen sonar la sirena. «Perímetro» suena '
                    'en las dos alarmas; «Interior», sólo en la total.'
                : 'Con la alarma armada, sólo estos sensores hacen sonar la sirena.',
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
          // El nivel SÓLO para los que participan, y sólo si el backend
          // conoce los tipos: un chip sobre un sensor apagado ofrecería una
          // decisión que no hace nada.
          if (fires && _supportsModes == true) ...[
            SizedBox(width: CceSpace.sm),
            _LevelChip(
              level: levelOf(device, _levels),
              onTap: _saving.contains(device.id)
                  ? null
                  : () => _cycleLevel(device),
            ),
          ],
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

/// El nivel de un sensor, como chip tocable (CCE#133).
///
/// Toggle y no menú: hay exactamente dos valores, y el chip muestra SIEMPRE el
/// vigente con su nombre completo. Los colores separan las dos ideas —el
/// perímetro es lo que protege con gente adentro, el interior es lo que sólo
/// entra con la casa vacía— sin usar el rojo, que en esta pantalla ya
/// significa "dispara la alarma".
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, required this.onTap});

  final SensorAlarmLevel level;
  final VoidCallback? onTap;

  static const Color _perimetro = Color(0xFF4DB6AC);
  static const Color _interior = Color(0xFF9575CD);

  @override
  Widget build(BuildContext context) {
    final esPerimetro = level == SensorAlarmLevel.perimeter;
    final color = esPerimetro ? _perimetro : _interior;
    return Semantics(
      button: true,
      label: 'Nivel: ${level.label}. ${level.blurb}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: CceSpace.sm, vertical: CceSpace.xs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(CceRadii.pill),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              level.label,
              style: CceText.label.copyWith(color: color),
            ),
          ),
        ),
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
