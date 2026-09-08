// CCE#133: la alarma tiene dos formas de armarse, y la pantalla tiene que
// decir CUÁL.
//
// La alarma casi no se usaba porque era todo o nada: con los 20 sensores
// marcados, armarla con gente adentro la hacía sonar en cuanto alguien cruzaba
// el pasillo. Ahora se elige entre perimetral y total.
//
// Lo que se fija acá:
//   1. El estado grande dice el tipo. «ARMADA» a secas es información
//      incompleta el día que hay dos formas de armarla.
//   2. Elegir el tipo NO arma. El dial es el que arma — un segmentado que
//      armara la casa de un toque convertiría un cambio de preferencia en un
//      armado accidental.
//   3. Armar manda el tipo que se está viendo; y lo que vuelve del backend
//      manda sobre lo que se pidió.
//   4. Contra una API vieja (sin `mode`) la pantalla NO dibuja el selector ni
//      inventa un tipo: mismo criterio que el `testMode: bool?` de CCE#122.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/alarm_mode.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/siren_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_theme.dart';
import 'package:cce_app/theme/components/cce_segmented.dart';
import 'package:cce_app/views/alarm_view.dart';

/// Puerto muerto en loopback: el `ServerConfig` por default apunta a la casa
/// REAL, y un test que se escape del doble le mandaría comandos al aparato.
ServerConfig _nowhere() => ServerConfig(host: '127.0.0.1', port: 1);

class _FakeApi extends ApiService {
  _FakeApi(
    super.config, {
    this.armed = false,
    this.mode = AlarmMode.total,
  });

  bool armed;

  /// `null` = backend viejo: no conoce los tipos de alarma.
  AlarmMode? mode;

  /// Lo que el backend devuelve al armar, si es distinto de lo que se pidió.
  AlarmMode? forceModeOnArm;
  bool failModePut = false;

  final List<String> armPuts = [];
  final List<String> modePuts = [];

  @override
  Future<({bool armed, AlarmMode? mode, bool? testMode})> getAlarmStatus() async =>
      (armed: armed, mode: mode, testMode: false);

  @override
  Future<({bool armed, AlarmMode? mode})> setAlarmArmed(
    bool armed, {
    AlarmMode? mode,
  }) async {
    armPuts.add('$armed${mode == null ? '' : '/${mode.wire}'}');
    this.armed = armed;
    if (mode != null) this.mode = mode;
    return (armed: armed, mode: forceModeOnArm ?? this.mode);
  }

  @override
  Future<AlarmMode> setAlarmMode(AlarmMode mode) async {
    if (failModePut) throw Exception('backend caído');
    modePuts.add(mode.wire);
    this.mode = mode;
    return mode;
  }

  @override
  Future<Map<String, bool>> getSensorAlarmTriggers() async => const {};

  @override
  Future<Map<String, String>> getSensorAlarmLevels() async => const {};

  /// La pantalla busca el último `alarm:armed-changed` para el «armada desde».
  /// Sin este override saldría un GET de verdad contra la casa.
  @override
  Future<EventsPage> getEvents({
    String? eventName,
    String? channel,
    String? globalId,
    int limit = 100,
    String? cursor,
  }) async =>
      EventsPage(items: const []);
}

class _FakeSocket extends SocketService {
  @override
  void connect(ServerConfig config) {}

  @override
  void disconnect() {}
}

class _FakeSiren extends SirenService {
  @override
  Future<void> init() async {}

  @override
  Future<void> startSiren({String sound = 'alarm'}) async {}

  @override
  Future<void> stop() async {}
}

Widget _app(Widget home) => MaterialApp(theme: CceTheme.dark(), home: home);

void main() {
  late _FakeApi api;
  late _FakeSocket socket;

  setUp(() {
    api = _FakeApi(_nowhere());
    socket = _FakeSocket();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(AlarmView(
      initialConfig: _nowhere(),
      api: api,
      socket: socket,
      siren: _FakeSiren(),
    )));
    await tester.pump();
    await tester.pump();
  }

  group('el estado grande dice QUÉ protege', () {
    testWidgets('armada en TOTAL lo declara', (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: AlarmMode.total);
      await pump(tester);

      expect(find.textContaining('ARMADA'), findsOneWidget);
      expect(find.textContaining('TOTAL'), findsOneWidget);
    });

    testWidgets('armada en PERIMETRAL lo declara', (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: AlarmMode.perimeter);
      await pump(tester);

      final label = tester
          .widgetList<Text>(find.textContaining('ARMADA'))
          .first
          .data;
      expect(label, 'ARMADA\nPERIMETRAL',
          reason: '«ARMADA» a secas no dice si podés caminar por la casa');
    });

    testWidgets('desarmada no inventa un tipo en el dial', (tester) async {
      api = _FakeApi(_nowhere(), armed: false, mode: AlarmMode.perimeter);
      await pump(tester);

      expect(find.text('DESARMADA'), findsOneWidget);
      // El selector sí lo muestra (es lo que se va a armar), el dial no.
      expect(find.textContaining('ARMADA\n'), findsNothing);
    });

    testWidgets('contra una API vieja, el dial vuelve a decir ARMADA a secas',
        (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: null);
      await pump(tester);

      expect(find.text('ARMADA'), findsOneWidget,
          reason: 'sin `mode` no hay tipo que declarar: no se inventa');
    });
  });

  group('el selector de tipo', () {
    testWidgets('muestra el elegido y qué promete', (tester) async {
      api = _FakeApi(_nowhere(), mode: AlarmMode.perimeter);
      await pump(tester);

      final seg = tester.widget<CceSegmented<AlarmMode>>(
          find.byType(CceSegmented<AlarmMode>));
      expect(seg.value, AlarmMode.perimeter);
      expect(find.text('Perimetral'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Sólo puertas y accesos. Podés estar adentro.'),
          findsOneWidget,
          reason: '«perimetral» no significa nada por sí solo');
    });

    testWidgets('elegir un tipo NO arma la casa', (tester) async {
      await pump(tester);

      // Escenario afirmado: arranca desarmada y en total.
      expect(find.text('DESARMADA'), findsOneWidget);
      expect(api.armed, isFalse);

      await tester.tap(find.text('Perimetral'));
      await tester.pump();
      await tester.pump();

      expect(api.modePuts, ['perimeter']);
      expect(api.armPuts, isEmpty,
          reason: 'el dial es el que arma; el selector sólo elige');
      expect(api.armed, isFalse);
      expect(find.text('DESARMADA'), findsOneWidget);
    });

    testWidgets('con la alarma ARMADA, cambiar el tipo no la desarma',
        (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: AlarmMode.total);
      await pump(tester);
      expect(find.textContaining('TOTAL'), findsOneWidget);

      await tester.tap(find.text('Perimetral'));
      await tester.pump();
      await tester.pump();

      expect(api.modePuts, ['perimeter']);
      expect(api.armed, isTrue, reason: 'cambiar de tipo no desarma la casa');
      final label =
          tester.widgetList<Text>(find.textContaining('ARMADA')).first.data;
      expect(label, 'ARMADA\nPERIMETRAL');
      expect(find.text('Ahora protege: Sólo puertas y accesos. Podés estar adentro.'),
          findsOneWidget,
          reason: 'armada, la frase habla de lo que protege AHORA');
    });

    testWidgets('si el PUT del tipo falla, el selector vuelve y se avisa',
        (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: AlarmMode.total);
      await pump(tester);
      api.failModePut = true;

      await tester.tap(find.text('Perimetral'));
      await tester.pump();
      await tester.pump();

      final seg = tester.widget<CceSegmented<AlarmMode>>(
          find.byType(CceSegmented<AlarmMode>));
      expect(seg.value, AlarmMode.total,
          reason: 'dejarlo en perimetral sin guardar hace creer que el '
              'movimiento interior está desactivado cuando va a sonar');
      expect(find.text('No pude cambiar el tipo de alarma'), findsOneWidget);
    });

    testWidgets('contra una API vieja el selector NO se dibuja',
        (tester) async {
      api = _FakeApi(_nowhere(), armed: true, mode: null);
      await pump(tester);

      expect(find.byType(CceSegmented<AlarmMode>), findsNothing,
          reason: 'un selector cuyo PUT 404ea siempre es peor que no ofrecerlo');
      expect(find.text('Perimetral'), findsNothing);
    });
  });

  group('armar manda el tipo que se está viendo', () {
    testWidgets('el toggle del dial arma con el tipo elegido', (tester) async {
      api = _FakeApi(_nowhere(), mode: AlarmMode.perimeter);
      await pump(tester);

      await tester.tap(find.text('DESARMADA'));
      await tester.pump();
      await tester.pump();

      expect(api.armPuts, ['true/perimeter'],
          reason: 'lo que se ve en pantalla es lo que se arma');
      final label =
          tester.widgetList<Text>(find.textContaining('ARMADA')).first.data;
      expect(label, 'ARMADA\nPERIMETRAL');
    });

    testWidgets('contra una API vieja arma sin tipo, como siempre',
        (tester) async {
      api = _FakeApi(_nowhere(), mode: null);
      await pump(tester);

      await tester.tap(find.text('DESARMADA'));
      await tester.pump();
      await tester.pump();

      expect(api.armPuts, ['true'],
          reason: 'sin tipos, el PUT es el mismo de antes de CCE#133');
    });

    testWidgets('manda el backend: si devuelve otro tipo, gana el backend',
        (tester) async {
      api = _FakeApi(_nowhere(), mode: AlarmMode.perimeter);
      api.forceModeOnArm = AlarmMode.total;
      await pump(tester);

      await tester.tap(find.text('DESARMADA'));
      await tester.pump();
      await tester.pump();

      final label =
          tester.widgetList<Text>(find.textContaining('ARMADA')).first.data;
      expect(label, 'ARMADA\nTOTAL',
          reason: 'la pantalla dibuja lo que quedó guardado, no lo que pidió');
    });
  });

  group('el tipo cambiado desde otro cliente llega por websocket', () {
    testWidgets('un armado del dashboard o del CLI se ve acá', (tester) async {
      await pump(tester);
      expect(find.text('DESARMADA'), findsOneWidget);

      socket.debugEmitArmed(armed: true, mode: AlarmMode.perimeter);
      await tester.pump();
      await tester.pump();

      final label =
          tester.widgetList<Text>(find.textContaining('ARMADA')).first.data;
      expect(label, 'ARMADA\nPERIMETRAL');
      final seg = tester.widget<CceSegmented<AlarmMode>>(
          find.byType(CceSegmented<AlarmMode>));
      expect(seg.value, AlarmMode.perimeter);
    });

    testWidgets('un evento SIN modo no borra el que ya se conocía',
        (tester) async {
      api = _FakeApi(_nowhere(), mode: AlarmMode.perimeter);
      await pump(tester);

      // Un backend viejo emitiendo el evento de siempre: el tipo que la
      // pantalla ya leyó no puede evaporarse y llevarse el selector con él.
      socket.debugEmitArmed(armed: true, mode: null);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CceSegmented<AlarmMode>), findsOneWidget);
      final label =
          tester.widgetList<Text>(find.textContaining('ARMADA')).first.data;
      expect(label, 'ARMADA\nPERIMETRAL');
    });
  });
}
