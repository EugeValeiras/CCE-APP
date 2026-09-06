// CCE#122 — Modo prueba de la alarma.
//
// Dos cosas, y la primera es un BUG que hay que arreglar para que la otra
// sirva de algo:
//
//  1. `_onAlarmTriggered` arrancaba la sirena y tomaba la pantalla SIN mirar
//     `event.critical`. Con la App abierta, el disparo degradado del modo
//     prueba sonaba igual que un robo — o sea que el modo prueba no se cumplía
//     justo en el dispositivo donde más importa. El Dashboard ya lo resolvía
//     del otro lado; ésta es la mitad que faltaba.
//
//  2. El toggle, y que el estado SE VEA. Es manual y no vence solo: la única
//     defensa contra olvidarlo prendido es que la pantalla lo diga.
//
// Nada de esto puede pegarle a la casa real: el `ServerConfig` de estos tests
// apunta a 127.0.0.1:1 y toda la red pasa por el doble.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/alarm_event.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/siren_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_theme.dart';
import 'package:cce_app/theme/components/cce_switch.dart';
import 'package:cce_app/views/active_alarm_view.dart';
import 'package:cce_app/views/alarm_sensors_screen.dart';
import 'package:cce_app/views/alarm_view.dart';

/// Puerto muerto en loopback: si algo se escapa del doble, falla acá y no en
/// la casa del dueño.
ServerConfig _nowhere() => ServerConfig(host: '127.0.0.1', port: 1);

class _FakeApi extends ApiService {
  _FakeApi(super.config, {this.armed = false, this.testMode = false});

  bool armed;
  /// `null` = el backend no conoce la clave (uno viejo).
  bool? testMode;
  bool failTestModePut = false;
  /// `GET /config/sensor-alarm-triggers` revienta (backend a medias, red).
  bool failTriggers = false;
  final List<bool> testModePuts = [];
  int statusReads = 0;

  @override
  Future<({bool armed, bool? testMode})> getAlarmStatus() async {
    statusReads++;
    return (armed: armed, testMode: testMode);
  }

  @override
  Future<bool> setAlarmTestMode(bool enabled) async {
    if (failTestModePut) throw Exception('backend caído');
    testModePuts.add(enabled);
    testMode = enabled;
    return enabled;
  }

  @override
  Future<Map<String, bool>> getSensorAlarmTriggers() async {
    if (failTriggers) throw Exception('backend caído');
    return const {};
  }

  @override
  Future<EventsPage> getEvents({
    String? eventName,
    String? channel,
    String? globalId,
    int limit = 100,
    String? cursor,
  }) async =>
      EventsPage(items: const []);

  @override
  Future<void> ackAlarm(String alarmId) async {}
}

/// Socket que no abre nada: los eventos se empujan a mano con
/// `debugEmitAlarm` / `debugEmitLive`, que son de la clase base.
class _FakeSocket extends SocketService {
  bool disposed = false;

  @override
  void connect(ServerConfig config) {}

  @override
  void disconnect() {}

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Sirena de mentira. Lo único que interesa es SI arrancó: el `AudioPlayer`
/// real ni se construye (por eso es lazy en `SirenService`).
class _FakeSiren extends SirenService {
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  String? lastSound;

  @override
  Future<void> init() async {}

  @override
  Future<void> startSiren({String sound = 'alarm'}) async {
    starts++;
    lastSound = sound;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

AlarmEvent _event({required bool critical}) => AlarmEvent(
      automationId: 'sensor-dev_puerta',
      automationName: 'Puerta de entrada',
      message: 'Apertura detectada',
      sound: critical ? 'alarm' : 'none',
      critical: critical,
      timestamp: 1,
    );

Widget _app(Widget home) => MaterialApp(theme: CceTheme.dark(), home: home);

void main() {
  group('el tipo del disparo decide qué hace la App', () {
    late _FakeApi api;
    late _FakeSocket socket;
    late _FakeSiren siren;

    setUp(() {
      api = _FakeApi(_nowhere(), armed: true);
      socket = _FakeSocket();
      siren = _FakeSiren();
    });

    /// La pantalla de la alarma está pensada para un teléfono real: en los
    /// 800x600 del test por defecto, el overlay del disparo desborda.
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(AlarmView(
        initialConfig: _nowhere(),
        api: api,
        socket: socket,
        siren: siren,
      )));
      await tester.pump();
      await tester.pump();
    }

    /// El aviso in-app deja un timer de 6 s: sin esto el test termina con un
    /// timer pendiente y flutter_test lo marca como error.
    Future<void> dejarPasarElAviso(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
    }

    testWidgets('un disparo NO crítico no toca la sirena ni la pantalla',
        (tester) async {
      await pump(tester);

      socket.debugEmitAlarm(_event(critical: false));
      await tester.pump();

      expect(siren.starts, 0,
          reason: 'con el modo prueba activo, esto es lo que NO puede sonar');
      expect(find.byType(ActiveAlarmView), findsNothing,
          reason: 'ni pantalla roja a página completa');
      // El aviso in-app sí: el disparo ocurrió y hay que enterarse.
      expect(find.text('Puerta de entrada'), findsWidgets);
      expect(find.text('Apertura detectada'), findsWidgets);

      await dejarPasarElAviso(tester);
    });

    testWidgets('un disparo CRÍTICO sigue tomando la pantalla y sonando',
        (tester) async {
      await pump(tester);

      socket.debugEmitAlarm(_event(critical: true));
      await tester.pump();

      expect(siren.starts, 1, reason: 'es la alarma de la casa: tiene que sonar');
      expect(siren.lastSound, 'alarm');
      expect(find.byType(ActiveAlarmView), findsOneWidget);

      await dejarPasarElAviso(tester);
    });

    testWidgets('un evento sin `critical` declarado se lee del tipo',
        (tester) async {
      // Es lo que emite el backend por websocket: `type`, no `critical`.
      expect(
        AlarmEvent.fromJson({'automationName': 'x', 'type': 'info'}).critical,
        isFalse,
      );
      expect(
        AlarmEvent.fromJson({'automationName': 'x', 'type': 'critical'}).critical,
        isTrue,
      );
    });
  });

  group('el modo prueba se ve en la pantalla de la alarma', () {
    testWidgets('con el modo activo, el dial lo declara', (tester) async {
      final api = _FakeApi(_nowhere(), armed: true, testMode: true);
      await tester.pumpWidget(_app(AlarmView(
        initialConfig: _nowhere(),
        api: api,
        socket: _FakeSocket(),
        siren: _FakeSiren(),
      )));
      await tester.pump();
      await tester.pump();

      expect(find.text('ARMADA'), findsOneWidget);
      expect(find.text('MODO PRUEBA · no va a sonar'), findsOneWidget,
          reason: '"ARMADA" a secas mientras no suena es una trampa');
    });

    testWidgets('sin modo prueba, la pantalla es la de siempre',
        (tester) async {
      final api = _FakeApi(_nowhere(), armed: true);
      await tester.pumpWidget(_app(AlarmView(
        initialConfig: _nowhere(),
        api: api,
        socket: _FakeSocket(),
        siren: _FakeSiren(),
      )));
      await tester.pump();
      await tester.pump();

      expect(find.text('ARMADA'), findsOneWidget);
      expect(find.textContaining('MODO PRUEBA'), findsNothing);
    });

    testWidgets('prenderlo desde otro cliente llega por config:changed',
        (tester) async {
      final api = _FakeApi(_nowhere(), armed: true);
      final socket = _FakeSocket();
      await tester.pumpWidget(_app(AlarmView(
        initialConfig: _nowhere(),
        api: api,
        socket: socket,
        siren: _FakeSiren(),
      )));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('MODO PRUEBA'), findsNothing);

      // El CLI o el dashboard lo prendieron: el backend lo emite así.
      api.testMode = true;
      socket.debugEmitLive('config:changed', {'section': 'alarm'});
      await tester.pump();
      await tester.pump();

      expect(find.text('MODO PRUEBA · no va a sonar'), findsOneWidget);
    });
  });

  group('el toggle, en la pantalla de sensores de la alarma', () {
    late DevicesService devices;
    late _FakeApi api;

    setUp(() {
      devices = DevicesService(config: _nowhere(), socket: _FakeSocket());
      // La sección del modo prueba vive en la lista de sensores: sin sensores
      // la pantalla muestra su vacío y no hay nada que configurar.
      devices.debugSeedDevices([
        Device(
          id: 'dev_puerta',
          name: 'Puerta de entrada',
          type: 'contact sensor',
          state: DeviceState(),
          sensor: DeviceSensor(contact: false),
        ),
      ]);
      api = _FakeApi(_nowhere());
    });

    tearDown(() => devices.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester
          .pumpWidget(_app(AlarmSensorsScreen(devices: devices, api: api)));
      await tester.pump();
      await tester.pump();
    }

    CceSwitch testModeSwitch(WidgetTester tester) {
      final row = find.ancestor(
        of: find.text('La alarma no suena'),
        matching: find.byType(Row),
      );
      return tester.widget<CceSwitch>(
        find.descendant(of: row.first, matching: find.byType(CceSwitch)),
      );
    }

    testWidgets('está apagado y explica para qué sirve', (tester) async {
      await pump(tester);

      expect(find.text('MODO PRUEBA'), findsOneWidget);
      expect(testModeSwitch(tester).value, isFalse);
      expect(
        find.textContaining('sin que suene'),
        findsOneWidget,
        reason: 'el texto tiene que decir qué hace, no sólo cómo se llama',
      );
    });

    testWidgets('prenderlo escribe y el texto pasa a decir que no suena',
        (tester) async {
      await pump(tester);

      await tester.tap(find.descendant(
        of: find
            .ancestor(
                of: find.text('La alarma no suena'), matching: find.byType(Row))
            .first,
        matching: find.byType(CceSwitch),
      ));
      await tester.pump();
      await tester.pump();

      expect(api.testModePuts, [true]);
      expect(testModeSwitch(tester).value, isTrue);
      expect(find.textContaining('sin sirena'), findsOneWidget);
    });

    testWidgets('si el PUT falla, el switch vuelve y se avisa', (tester) async {
      await pump(tester);
      api.failTestModePut = true;

      await tester.tap(find.descendant(
        of: find
            .ancestor(
                of: find.text('La alarma no suena'), matching: find.byType(Row))
            .first,
        matching: find.byType(CceSwitch),
      ));
      await tester.pump();
      await tester.pump();

      expect(testModeSwitch(tester).value, isFalse,
          reason: 'dejarlo prendido sin guardar hace creer que no va a sonar');
      expect(find.text('No pude cambiar el modo prueba'), findsOneWidget);
    });

    testWidgets('si no se pudo leer el estado, no se dibuja un switch que miente',
        (tester) async {
      final caido = _ApiQueFalla(_nowhere());
      await tester.pumpWidget(
          _app(AlarmSensorsScreen(devices: devices, api: caido)));
      await tester.pump();
      await tester.pump();

      expect(find.text('MODO PRUEBA'), findsNothing);
      expect(find.text('La alarma no suena'), findsNothing);
    });

    /**
     * I5: contra un backend viejo, `GET /config/alarm-armed` contesta 200 SIN
     * `testMode`. Leerlo como `false` dibujaba un switch que parece funcionar
     * y cuyo PUT 404ea siempre.
     */
    testWidgets('un backend que no conoce la clave tampoco dibuja el switch',
        (tester) async {
      final viejo = _ApiSinTestMode(_nowhere());
      await tester.pumpWidget(
          _app(AlarmSensorsScreen(devices: devices, api: viejo)));
      await tester.pump();
      await tester.pump();

      expect(find.text('MODO PRUEBA'), findsNothing,
          reason: 'ausente no es apagado: es "no se sabe"');
    });

    /**
     * B4 — el bloqueante: la sección estaba DESPUÉS de los returns tempranos
     * de "no hay sensores" y de `_failed`. Si fallaba el GET de los triggers,
     * la pantalla mostraba el error y el toggle no se dibujaba, aunque el modo
     * estuviera activo. Como no hay otro lugar en la App donde apagarlo, la
     * alarma quedaba muda sin forma de revertirla desde el celular.
     */
    testWidgets('el toggle sigue estando aunque falle la lectura de sensores',
        (tester) async {
      api.testMode = true;
      api.failTriggers = true;

      await pump(tester);

      expect(find.text('No pude leer qué sensores disparan la alarma.'),
          findsOneWidget);
      expect(find.text('MODO PRUEBA'), findsOneWidget,
          reason: 'sin esto la alarma queda muda y sin forma de revertirla');
      expect(testModeSwitch(tester).value, isTrue);
      expect(testModeSwitch(tester).onChanged, isNotNull,
          reason: 'y tiene que poder apagarse, no sólo verse');
    });

    testWidgets('y se puede APAGAR con la lectura de sensores caída',
        (tester) async {
      api.testMode = true;
      api.failTriggers = true;
      await pump(tester);

      await tester.tap(find.descendant(
        of: find
            .ancestor(
                of: find.text('La alarma no suena'), matching: find.byType(Row))
            .first,
        matching: find.byType(CceSwitch),
      ));
      await tester.pump();
      await tester.pump();

      expect(api.testModePuts, [false]);
      expect(api.testMode, isFalse);
    });

    testWidgets('el toggle sigue estando aunque la casa no tenga sensores',
        (tester) async {
      final vacia = DevicesService(config: _nowhere(), socket: _FakeSocket());
      addTearDown(vacia.dispose);
      vacia.debugSeedDevices([]);
      api.testMode = true;

      await tester.pumpWidget(
          _app(AlarmSensorsScreen(devices: vacia, api: api)));
      await tester.pump();
      await tester.pump();

      expect(find.text('La casa no tiene sensores de apertura ni de movimiento.'),
          findsOneWidget);
      expect(find.text('MODO PRUEBA'), findsOneWidget);
    });
  });

  /**
   * I6: `dispose()` destruía servicios que no había creado.
   * `SocketService.dispose()` cierra sus siete StreamControllers: pasarle el
   * socket compartido de `DevicesService` y salir de la pantalla mataba los
   * eventos de toda la app.
   */
  group('los servicios inyectados son del caller', () {
    testWidgets('salir de la pantalla no cierra un socket que vino de afuera',
        (tester) async {
      final socket = _FakeSocket();
      final siren = _FakeSiren();
      await tester.pumpWidget(_app(AlarmView(
        initialConfig: _nowhere(),
        api: _FakeApi(_nowhere()),
        socket: socket,
        siren: siren,
      )));
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();

      // Si el dispose lo hubiera cerrado, este emit tiraría
      // "Cannot add new events after calling close".
      socket.debugEmitAlarm(_event(critical: false));
      expect(socket.disposed, isFalse);
      expect(siren.disposed, isFalse, reason: 'la sirena inyectada tampoco es suya');
    });
  });
}

/// Backend viejo: contesta 200 pero sin la clave `testMode`.
class _ApiSinTestMode extends _FakeApi {
  _ApiSinTestMode(super.config);

  @override
  Future<({bool armed, bool? testMode})> getAlarmStatus() async =>
      (armed: true, testMode: null);
}

/// Backend caído para la lectura del estado.
class _ApiQueFalla extends _FakeApi {
  _ApiQueFalla(super.config);

  @override
  Future<({bool armed, bool? testMode})> getAlarmStatus() async {
    throw Exception('500');
  }
}

// `Completer` se usa sólo si algún test necesita colgar una lectura.
// ignore: unused_element
Completer<void>? _unused;
