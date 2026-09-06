// CCE#56: el evento de sensor que llega por WebSocket y el sensor que llega
// por REST se parsean CON LA MISMA lista de campos (DeviceSensor.merge).
//
// El bug: `_applyDeviceEvent` re-armaba el DeviceSensor a mano con casteos
// crudos (`as num?`) mientras `fromJson` ya tenía el parseo defensivo de
// `trigTime` — que eWeLink manda como String. El cast tiraba EVALUANDO los
// argumentos del constructor, o sea antes de asignar: se perdía el bloque de
// sensor entero (motion, contact, temperatura) y `notifyListeners()` quedaba
// del otro lado de la excepción, así que un cambio de state ya aplicado en el
// mismo evento tampoco llegaba a la UI.
//
// Los tests entran por el MISMO camino que producción: un DeviceStateEvent
// empujado por el socket, no una llamada directa al parser.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';

/// Socket sin red: los eventos de device se empujan a mano.
class _FakeSocket extends SocketService {
  final _events = StreamController<DeviceStateEvent>.broadcast();

  @override
  Stream<DeviceStateEvent> get onDeviceChanged => _events.stream;

  void push(
    String deviceId, {
    Map<String, dynamic>? state,
    Map<String, dynamic>? sensor,
  }) =>
      _events.add(
        DeviceStateEvent(deviceId: deviceId, state: state, sensor: sensor),
      );
}

/// Un sensor de contacto sembrado, el socket que le empuja eventos y el
/// contador de notificaciones a la UI.
class _Rig {
  _Rig({DeviceSensor? sensor, DeviceState? state}) {
    device = Device(
      id: 'dev_sensor',
      name: 'Kitchen door',
      type: 'eWeLink Contact Sensor',
      capabilities: const ['sensor', 'contact'],
      state: state ?? DeviceState(),
      sensor: sensor,
    );
    service = DevicesService(config: ServerConfig(), socket: socket);
    service.debugSeedDevices([device]);
    service.addListener(() => notifies++);
  }

  final _FakeSocket socket = _FakeSocket();
  late final Device device;
  late final DevicesService service;
  int notifies = 0;

  Future<void> send({
    Map<String, dynamic>? state,
    Map<String, dynamic>? sensor,
  }) async {
    socket.push('dev_sensor', state: state, sensor: sensor);
    await pumpEventQueue();
  }

  DeviceSensor? get sensor => device.sensor;
}

void main() {
  group('trigTime por el path del evento (WS)', () {
    test('String numérico: se aplica y queda parseado a int', () async {
      final rig = _Rig();
      await rig.send(sensor: {'contact': true, 'trigTime': '1788040000000'});

      expect(rig.sensor?.trigTime, 1788040000000);
      expect(rig.sensor?.trigTime, isA<int>());
      expect(rig.sensor?.contact, isTrue);
      expect(rig.notifies, 1, reason: 'la UI se tiene que enterar');
    });

    test('num: sigue funcionando exactamente igual', () async {
      final rig = _Rig();
      await rig.send(sensor: {'contact': false, 'trigTime': 1788040000000});

      expect(rig.sensor?.trigTime, 1788040000000);
      expect(rig.sensor?.contact, isFalse);
    });

    test('no parseable: cae al valor anterior y el resto se aplica igual',
        () async {
      final rig = _Rig(sensor: DeviceSensor(trigTime: 111, motion: false));
      await rig.send(sensor: {'motion': true, 'trigTime': 'abc'});

      expect(rig.sensor?.motion, isTrue, reason: 'el motion NO se pierde');
      expect(rig.sensor?.trigTime, 111, reason: 'conserva el último bueno');
      expect(rig.notifies, 1);
    });

    test('no parseable y sin valor previo: null, sin tirar', () async {
      final rig = _Rig();
      await rig.send(sensor: {'contact': true, 'trigTime': 'abc'});

      expect(rig.sensor?.trigTime, isNull);
      expect(rig.sensor?.contact, isTrue);
    });
  });

  group('el evento se aplica COMPLETO', () {
    test('el state del mismo evento llega a la UI aunque el sensor sea raro',
        () async {
      // El caso del issue: `state` se aplica arriba de todo, y la excepción del
      // sensor se llevaba puesto el notifyListeners() de abajo.
      final rig = _Rig(state: DeviceState(on: false));
      await rig.send(
        state: {'on': true},
        sensor: {'motion': true, 'trigTime': '1788040000000'},
      );

      expect(rig.device.state.on, isTrue);
      expect(rig.sensor?.motion, isTrue);
      expect(rig.notifies, 1, reason: 'sin notify el cambio queda invisible');
      expect(rig.device.lastEventAt, isNotNull);
    });

    test('un campo con el tipo cambiado no se lleva puesto a los demás',
        () async {
      final rig = _Rig();
      await rig.send(sensor: {
        'motion': true,
        'contact': false,
        'temperature': '21.5', // el día que llegue como String
        'battery': 87, // el día que llegue como número
        'trigTime': '1788040000000',
      });

      expect(rig.sensor?.motion, isTrue);
      expect(rig.sensor?.contact, isFalse);
      expect(rig.sensor?.temperature, 21.5);
      expect(rig.sensor?.battery, '87');
      expect(rig.sensor?.trigTime, 1788040000000);
    });

    test('el merge conserva lo que el evento no trae', () async {
      final rig = _Rig(
        sensor: DeviceSensor(
          temperature: 22.0,
          humidity: 55.0,
          battery: '100',
          motion: false,
          trigTime: 111,
        ),
      );
      await rig.send(sensor: {'motion': true, 'trigTime': '222'});

      expect(rig.sensor?.motion, isTrue);
      expect(rig.sensor?.trigTime, 222);
      expect(rig.sensor?.temperature, 22.0, reason: 'no se pierde la temp');
      expect(rig.sensor?.humidity, 55.0);
      expect(rig.sensor?.battery, '100');
    });
  });

  group('fixture dorado — el path del evento, no sólo el REST', () {
    final entries =
        (jsonDecode(File('test/fixtures/merged-golden.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final sensors = [
      for (final e in entries)
        if (e['sensor'] is Map)
          (e['id'] as String, Map<String, dynamic>.from(e['sensor'] as Map)),
    ];

    test('el fixture trae lux en algún sensor (CCE#112): si no, la aserción de abajo compara null contra null', () {
      // El golden se recaptura de producción con `npm run contract:capture`
      // (CCE-API). Hasta que el API con lux esté deployado, los cuatro
      // SNZB-03PR2 llevan el lux del journal de eWeLink de la hora de la
      // captura (05/09/2026: 21, 19, 17 y 17 lx) y la capability
      // `illuminance`, agregados a mano y marcados acá; la próxima recaptura
      // real los reemplaza.
      expect(sensors.where((s) => s.$2['lux'] is num), isNotEmpty,
          reason: 'recapturá el golden con el API que expone lux');
    });

    test('el fixture trae trigTime, y numérico', () {
      // Desde CCE#56 el API emite trigTime SIEMPRE como número, venga como
      // venga de eWeLink; el golden anterior a ese fix traía 4 String y por
      // eso este test pedía los dos tipos. La tolerancia a String la sigue
      // probando el rig sintético de arriba (`trigTime: '222'`).
      final tipos = sensors
          .map((s) => s.$2['trigTime'])
          .where((v) => v != null)
          .map((v) => v is String ? 'String' : 'num')
          .toSet();
      expect(tipos, equals(<String>{'num'}),
          reason: 'si el fixture trae trigTime String, el API dejó de '
              'normalizarlo (CCE#56); si no trae ninguno, recapturalo con '
              '`npm run contract:capture`');
    });

    test('cada sensor del fixture entra por el WS sin romper', () async {
      for (final (id, raw) in sensors) {
        final device = Device(
          id: id,
          name: id,
          type: 'sensor',
          state: DeviceState(),
        );
        final socket = _FakeSocket();
        final service =
            DevicesService(config: ServerConfig(), socket: socket)
              ..debugSeedDevices([device]);
        var notifies = 0;
        service.addListener(() => notifies++);

        socket.push(id, sensor: raw);
        await pumpEventQueue();

        expect(notifies, 1, reason: 'el evento de $id no se aplicó');
        expect(device.sensor, isNotNull, reason: 'sensor nulo en $id');
        expect(device.sensor!.trigTime, isA<int?>());
        if (raw['trigTime'] != null) {
          expect(device.sensor!.trigTime, isNotNull,
              reason: 'trigTime de $id (${raw['trigTime']}) se perdió');
        }
      }
    });

    test('el WS y el REST dan el MISMO sensor para el mismo mapa', () {
      // La garantía que reemplaza a las dos listas de campos duplicadas.
      for (final (id, raw) in sensors) {
        final rest = DeviceSensor.fromJson(raw);
        final ws = DeviceSensor.merge(null, raw);
        expect(ws.trigTime, rest.trigTime, reason: 'trigTime de $id');
        expect(ws.motion, rest.motion, reason: 'motion de $id');
        expect(ws.contact, rest.contact, reason: 'contact de $id');
        expect(ws.temperature, rest.temperature, reason: 'temperature de $id');
        expect(ws.humidity, rest.humidity, reason: 'humidity de $id');
        expect(ws.battery, rest.battery, reason: 'battery de $id');
        expect(ws.brightness, rest.brightness, reason: 'brightness de $id');
        expect(ws.lux, rest.lux, reason: 'lux de $id');
        expect(ws.lastKey, rest.lastKey, reason: 'lastKey de $id');
        expect(ws.outlet, rest.outlet, reason: 'outlet de $id');
        expect(ws.outlets, rest.outlets, reason: 'outlets de $id');
      }
    });
  });

  group('el REST conserva su comportamiento', () {
    test('DeviceSensor.fromJson parsea los dos tipos de trigTime', () {
      expect(DeviceSensor.fromJson({'trigTime': 1788040000000}).trigTime,
          1788040000000);
      expect(DeviceSensor.fromJson({'trigTime': '1788040000000'}).trigTime,
          1788040000000);
      expect(DeviceSensor.fromJson({'trigTime': 'abc'}).trigTime, isNull);
      expect(DeviceSensor.fromJson(const {}).trigTime, isNull);
    });
  });
}
