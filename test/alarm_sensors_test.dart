// CCE#29: qué sensores disparan la alarma.
//
// El riesgo de esta tarea es UNO y está acá: el mapa `sensorAlarmTriggers`
// mezcla ids canónicos (dev_*) con ids de provider (ewelink_*, matter_*)
// según cuándo se guardó cada entrada. Filtrar "qué protege" sólo por
// `device.id` haría desaparecer sensores que hoy están marcados — lo contrario
// de lo que la pantalla promete. Por eso casi todos los tests de abajo pasan
// por una entrada guardada con bindingId.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_theme.dart';
import 'package:cce_app/theme/components/cce_switch.dart';
import 'package:cce_app/utils/alarm_triggers.dart';
import 'package:cce_app/views/alarm_sensors_screen.dart';
import 'package:cce_app/views/alarm_view.dart';
import 'package:cce_app/views/rooms_list_screen.dart';

Device _contact(
  String id, {
  String? name,
  List<String> bindings = const [],
  bool open = false,
}) =>
    Device(
      id: id,
      name: name ?? id,
      type: 'contact sensor',
      bindingIds: bindings,
      state: DeviceState(),
      sensor: DeviceSensor(contact: open),
    );

Device _motion(
  String id, {
  String? name,
  List<String> bindings = const [],
  bool active = false,
}) =>
    Device(
      id: id,
      name: name ?? id,
      type: 'motion sensor',
      bindingIds: bindings,
      state: DeviceState(),
      sensor: DeviceSensor(motion: active),
    );

/// Inventario real de la casa en miniatura: una puerta marcada por su id
/// canónico, otra marcada por un bindingId legacy, una sin marcar y un sensor
/// de movimiento sin marcar.
DevicesService _devices(List<Device> devices) {
  final service =
      DevicesService(config: _nowhere(), socket: SocketService());
  service.debugSeedDevices(devices);
  return service;
}

class _FakeApi extends ApiService {
  _FakeApi(super.config, {this.triggers = const {}});

  Map<String, bool> triggers;

  /// La pantalla también lee el modo prueba (CCE#122). Sin este override, el
  /// GET saldría de verdad — y el `ServerConfig` por default apunta a la casa
  /// del dueño.
  @override
  Future<({bool armed, bool? testMode})> getAlarmStatus() async =>
      (armed: false, testMode: false);
  int reads = 0;
  final List<String> puts = [];
  bool failPut = false;

  /// Si está seteado, la lectura queda colgada hasta completarlo: así se
  /// puede mirar la pantalla ANTES de que sepa de qué estado parte.
  Completer<void>? gate;

  @override
  Future<Map<String, bool>> getSensorAlarmTriggers() async {
    reads++;
    final g = gate;
    if (g != null) await g.future;
    return Map<String, bool>.from(triggers);
  }

  @override
  Future<void> setSensorAlarmTrigger(String deviceId, bool fires) async {
    if (failPut) throw Exception('backend caído');
    puts.add('$deviceId=$fires');
    final next = Map<String, bool>.from(triggers);
    if (fires) {
      next[deviceId] = true;
    } else {
      next.remove(deviceId);
    }
    triggers = next;
  }
}

/// Puerto muerto en loopback: el `ServerConfig` por default apunta a la casa
/// REAL del dueño, y un test que se escape del doble le hablaría al aparato.
ServerConfig _nowhere() => ServerConfig(host: '127.0.0.1', port: 1);

Widget _app(Widget home) => MaterialApp(theme: CceTheme.dark(), home: home);

void main() {
  group('helper compartido: ¿este device dispara?', () {
    test('el id canónico marcado dispara', () {
      expect(firesAlarm(_contact('dev_a'), {'dev_a': true}), isTrue);
    });

    test('una entrada guardada con el bindingId TAMBIÉN dispara', () {
      final d = _contact('dev_a', bindings: ['ewelink_acc4', 'matter_58']);
      expect(firesAlarm(d, {'ewelink_acc4': true}), isTrue,
          reason: 'el mapa guarda ids de provider en las entradas viejas');
      expect(firesAlarm(d, {'matter_58': true}), isTrue);
    });

    test('sin entrada, con la entrada en false o con mapa vacío no dispara',
        () {
      final d = _contact('dev_a', bindings: ['ewelink_acc4']);
      expect(firesAlarm(d, const {}), isFalse);
      expect(firesAlarm(d, {'dev_a': false}), isFalse);
      expect(firesAlarm(d, {'otro': true}), isFalse);
    });

    test('el bindingId de OTRO device no lo contagia', () {
      final a = _contact('dev_a', bindings: ['ewelink_1']);
      final b = _contact('dev_b', bindings: ['ewelink_2']);
      final triggers = {'ewelink_1': true};
      expect(firesAlarm(a, triggers), isTrue);
      expect(firesAlarm(b, triggers), isFalse);
    });

    test('apagar borra la clave LEGACY, no sólo la canónica', () async {
      final api = _FakeApi(_nowhere(), triggers: {'ewelink_acc4': true});
      final d = _contact('dev_a', bindings: ['ewelink_acc4']);

      final next =
          await writeFiresAlarm(api, d, api.triggers, fires: false);

      expect(api.puts, contains('ewelink_acc4=false'),
          reason: 'escribir sólo dev_a dejaría el sensor disparando');
      expect(firesAlarm(d, next), isFalse);
      expect(firesAlarm(d, api.triggers), isFalse);
    });

    test('prender escribe el id canónico, que es el que lee el backend',
        () async {
      final api = _FakeApi(_nowhere());
      final d = _contact('dev_a', bindings: ['ewelink_acc4']);

      final next = await writeFiresAlarm(api, d, api.triggers, fires: true);

      expect(api.puts, ['dev_a=true']);
      expect(firesAlarm(d, next), isTrue);
    });
  });

  group('pseudo-sensores del backend', () {
    Device pseudo(String id, String type, List<String> bindings) => Device(
          id: id,
          name: id,
          type: type,
          capabilities: const ['contact'],
          bindingIds: bindings,
          state: DeviceState(),
          sensor: DeviceSensor(contact: false),
        );

    test('los anunciadores del portón y la alarma no son sensores', () {
      expect(
          isPseudoSensor(
              pseudo('dev_announcer_porton', 'announcer', ['announcer_porton'])),
          isTrue);
      expect(isPseudoSensor(pseudo('dev_alarm', 'alarm', ['alarm_alarm'])),
          isTrue);
      // Un sensor de verdad no se filtra por parecerse de nombre.
      expect(
          isPseudoSensor(_contact('dev_a', bindings: ['ewelink_acc4'])), isFalse);
    });

    test('quedan fuera de las dos listas, no sólo de la vista', () {
      final real = _contact('dev_real', name: 'Puerta real');
      final lista = protectedSensors([
        real,
        pseudo('dev_announcer_porton', 'announcer', ['announcer_porton']),
        pseudo('dev_announcer_porton_abierto', 'announcer',
            ['announcer_porton_abierto']),
        pseudo('dev_alarm', 'alarm', ['alarm_alarm']),
      ]);
      expect(lista.map((d) => d.id), ['dev_real'],
          reason: 'marcar "la alarma" para que dispare la alarma no significa nada');
    });
  });

  group('"qué protege" muestra sólo lo que dispara', () {
    final marcada = _contact('dev_marcada', name: 'Puerta marcada');
    final legacy = _contact('dev_legacy',
        name: 'Puerta legacy', bindings: ['ewelink_acc4'], open: true);
    final suelta = _contact('dev_suelta', name: 'Puerta suelta', open: true);
    final mov = _motion('dev_mov', name: 'Movimiento pasillo');

    Future<void> pump(
      WidgetTester tester, {
      required Map<String, bool>? triggers,
      VoidCallback? onConfigure,
    }) =>
        tester.pumpWidget(_app(Scaffold(
          body: ListView(children: [
            ProtectedList(
              devices: _devices([marcada, legacy, suelta, mov]),
              triggers: triggers,
              onConfigure: onConfigure ?? () {},
            ),
          ]),
        )));

    testWidgets('el sensor con el flag en false no aparece', (tester) async {
      await pump(tester, triggers: {'dev_marcada': true, 'dev_suelta': false});

      expect(find.text('Puerta marcada'), findsOneWidget);
      expect(find.text('Puerta suelta'), findsNothing);
      expect(find.text('Movimiento pasillo'), findsNothing);
    });

    testWidgets('el sensor marcado con un bindingId SÍ aparece',
        (tester) async {
      await pump(tester, triggers: {'ewelink_acc4': true});

      expect(find.text('Puerta legacy'), findsOneWidget,
          reason: 'filtrar por device.id lo habría escondido');
      expect(find.text('Puerta marcada'), findsNothing);
    });

    testWidgets('el contador cuenta sólo sobre lo filtrado', (tester) async {
      // Hay DOS aperturas abiertas (legacy y suelta) pero sólo una dispara.
      await pump(tester, triggers: {'ewelink_acc4': true});

      expect(find.text('1 ABIERTA'), findsOneWidget);
      expect(find.text('2 ABIERTAS'), findsNothing);
    });

    testWidgets('con cero marcados explica por qué y lleva a configurar',
        (tester) async {
      var abierto = 0;
      await pump(tester, triggers: const {}, onConfigure: () => abierto++);

      expect(find.text('QUÉ PROTEGE'), findsOneWidget,
          reason: 'la sección no puede desaparecer sin explicación');
      expect(find.text('Ningún sensor dispara la alarma'), findsOneWidget);
      expect(find.text('Tocá para elegir cuáles'), findsOneWidget);

      await tester.tap(find.text('Ningún sensor dispara la alarma'));
      await tester.pump();
      expect(abierto, 1);
    });

    testWidgets('sin el mapa leído todavía, la sección espera', (tester) async {
      await pump(tester, triggers: null);

      expect(find.text('QUÉ PROTEGE'), findsNothing);
      expect(find.text('Puerta marcada'), findsNothing);
    });
  });

  group('pantalla de sensores de la alarma', () {
    late DevicesService devices;
    late _FakeApi api;

    final legacy = _contact('dev_legacy',
        name: 'Puerta legacy', bindings: ['ewelink_acc4']);
    final suelta = _contact('dev_suelta', name: 'Puerta suelta');
    final mov = _motion('dev_mov', name: 'Movimiento pasillo');

    setUp(() {
      devices = _devices([legacy, suelta, mov]);
      api = _FakeApi(_nowhere());
    });

    tearDown(() => devices.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
          _app(AlarmSensorsScreen(devices: devices, api: api)));
      await tester.pump();
      await tester.pump();
    }

    CceSwitch switchOf(WidgetTester tester, String name) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      return tester.widget<CceSwitch>(
        find.descendant(of: row.first, matching: find.byType(CceSwitch)),
      );
    }

    testWidgets('lista los candidatos agrupados y sin filtrar por el flag',
        (tester) async {
      api.triggers = {'ewelink_acc4': true};
      await pump(tester);

      // Todos los de apertura y movimiento, marcados o no: acá se elige.
      expect(find.text('Puerta legacy'), findsOneWidget);
      expect(find.text('Puerta suelta'), findsOneWidget);
      expect(find.text('Movimiento pasillo'), findsOneWidget);
      expect(find.text('APERTURAS'), findsOneWidget);
      expect(find.text('MOVIMIENTO'), findsOneWidget);
      expect(find.text('1 DE 2'), findsOneWidget); // aperturas marcadas
    });

    testWidgets('el switch refleja una entrada guardada con bindingId',
        (tester) async {
      api.triggers = {'ewelink_acc4': true};
      await pump(tester);

      expect(switchOf(tester, 'Puerta legacy').value, isTrue);
      expect(switchOf(tester, 'Puerta suelta').value, isFalse);
    });

    testWidgets('una sola lectura del mapa alimenta toda la lista',
        (tester) async {
      await pump(tester);
      expect(api.reads, 1);

      // Un evento del inventario reconstruye la lista: no puede releer.
      devices.debugSeedDevices([legacy, suelta, mov]);
      await tester.pump();
      await tester.pump();

      expect(api.reads, 1, reason: 'una lectura por fila serían N GET iguales');
    });

    testWidgets('mientras no se sabe el estado, los switches no se tocan',
        (tester) async {
      api.gate = Completer<void>(); // la lectura queda colgada.
      await tester.pumpWidget(
          _app(AlarmSensorsScreen(devices: devices, api: api)));
      await tester.pump();

      // Los de SENSORES: el del modo prueba (CCE#122) se lee por otro camino
      // y no depende de este mapa, así que no entra en esta cuenta.
      final sensores = ['Puerta legacy', 'Puerta suelta', 'Movimiento pasillo'];
      for (final nombre in sensores) {
        expect(switchOf(tester, nombre).onChanged, isNull,
            reason: 'un switch en "no" que nadie leyó miente sobre la alarma');
      }

      api.gate!.complete();
      await tester.pump();
      await tester.pump();

      for (final nombre in sensores) {
        expect(switchOf(tester, nombre).onChanged, isNotNull,
            reason: 'con el mapa leído, los switches se habilitan');
      }
    });

    testWidgets('prender un sensor escribe su id canónico', (tester) async {
      await pump(tester);

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Puerta suelta'), matching: find.byType(Row)).first,
        matching: find.byType(CceSwitch),
      ));
      await tester.pump();
      await tester.pump();

      expect(api.puts, ['dev_suelta=true']);
      expect(switchOf(tester, 'Puerta suelta').value, isTrue);
    });

    testWidgets('si el PUT falla, el switch vuelve y se avisa', (tester) async {
      api.triggers = {'ewelink_acc4': true};
      await pump(tester);
      api.failPut = true;

      await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Puerta legacy'), matching: find.byType(Row)).first,
        matching: find.byType(CceSwitch),
      ));
      await tester.pump();
      await tester.pump();

      expect(switchOf(tester, 'Puerta legacy').value, isTrue,
          reason: 'el toggle optimista tiene que revertirse');
      expect(find.text('No pude cambiar «Puerta legacy»'), findsOneWidget);
    });
  });

  group('cerrar sesión al pie de la home', () {
    testWidgets('es una fila tocable que dice qué hace', (tester) async {
      var tocado = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: ListView(children: [SignOutRow(onTap: () => tocado++)]),
      )));

      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(tester.getSize(find.byType(SizedBox).first).height,
          SignOutRow.kHeight);

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pump();
      expect(tocado, 1);
    });
  });
}
