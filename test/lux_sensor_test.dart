// CCE#112: los SNZB-03PR2 miden lux y el backend lo expone como `sensor.lux`
// con la capability `illuminance`. Tres cosas que la app tiene que hacer bien:
//
//   1. Parsear el número por REST y por el evento del WebSocket, y NO perderlo
//      cuando llega un evento que no lo trae (el `{motion:true}` de Matter):
//      la whitelist de DeviceSensor.merge es la única, y esta es la trampa que
//      CCE#100 sufrió con lightModes.
//   2. Tolerar la capability nueva sin romper el render (forward-compat).
//   3. Narrar los umbrales: «Luz de X baja de 30 lx», «si luz < 30 lx».
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/utils/capability_renderers.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';

class _FakeSocket extends SocketService {
  final _events = StreamController<DeviceStateEvent>.broadcast();

  @override
  Stream<DeviceStateEvent> get onDeviceChanged => _events.stream;

  void push(String deviceId, {Map<String, dynamic>? sensor}) =>
      _events.add(DeviceStateEvent(deviceId: deviceId, sensor: sensor));
}

/// «Movimiento pasillo» tal como lo sirve GET /devices tras CCE#112.
Map<String, dynamic> pasilloJson({int? lux}) => {
      'id': 'dev_a4c13819aaa6ffff',
      'name': 'Movimiento pasillo',
      'type': 'eWeLink Motion Sensor',
      'capabilities': ['sensor', 'motion', 'illuminance'],
      'state': {'on': false, 'bri': 1, 'reachable': true},
      'sensor': {
        'battery': '100',
        'motion': false,
        'brightness': 'darker',
        'lux': ?lux,
        'trigTime': 1788580804437,
      },
    };

void main() {
  group('modelo — sensor.lux y la capability illuminance', () {
    test('REST: el lux se lee como entero', () {
      final d = Device.fromJson(pasilloJson(lux: 17));
      expect(d.sensor?.lux, 17);
      expect(d.sensor?.brightness, 'darker', reason: 'el binario sigue');
      expect(d.capabilities, contains('illuminance'));
    });

    test('un lux con decimales (si algún provider lo mandara) no tira', () {
      expect(DeviceSensor.fromJson({'lux': 17.6}).lux, 17);
      expect(DeviceSensor.fromJson({'lux': '29'}).lux, 29);
      expect(DeviceSensor.fromJson({'lux': 'abc'}).lux, isNull);
    });

    test('el SNZB-03P viejo no trae lux y sigue igual', () {
      final d = Device.fromJson({
        ...pasilloJson(),
        'capabilities': ['sensor', 'motion'],
      });
      expect(d.sensor?.lux, isNull);
      expect(d.sensor?.brightness, 'darker');
    });

    test('la capability nueva no rompe el render: va al readout de sensor', () {
      final kinds = capabilityRenderersFor(['sensor', 'motion', 'illuminance'])
          .map((e) => e.kind)
          .toList();
      expect(kinds, [CapabilityRendererKind.sensor]);
    });
  });

  group('WebSocket — el lux sobrevive al primer evento', () {
    late Device device;
    late DevicesService service;
    late _FakeSocket socket;

    setUp(() {
      socket = _FakeSocket();
      device = Device.fromJson(pasilloJson(lux: 17));
      // 127.0.0.1:1 a propósito: el default apunta a la casa real.
      service = DevicesService(
        config: ServerConfig(host: '127.0.0.1', port: 1),
        socket: socket,
      );
      service.debugSeedDevices([device]);
    });

    Future<void> send(Map<String, dynamic> sensor) async {
      socket.push(device.id, sensor: sensor);
      await pumpEventQueue();
    }

    test('el {motion:true} de Matter no borra el lux ni el brightness', () async {
      await send({'motion': true});
      expect(device.sensor?.motion, isTrue);
      expect(device.sensor?.lux, 17, reason: 'la trampa de CCE#100: la whitelist');
      expect(device.sensor?.brightness, 'darker');
    });

    test('un update de sólo luz (el WS de eWeLink, SIN la clave motion) actualiza lux y brightness', () async {
      await send({'lux': 120, 'brightness': 'brighter'});
      expect(device.sensor?.lux, 120);
      expect(device.sensor?.brightness, 'brighter');
      expect(device.sensor?.motion, isFalse, reason: 'lo que no vino se conserva');
      expect(device.sensor?.battery, '100');
    });

    test('un lux inconvertible conserva el anterior y aplica el resto', () async {
      await send({'motion': true, 'lux': 'abc'});
      expect(device.sensor?.motion, isTrue);
      expect(device.sensor?.lux, 17);
    });
  });

  group('frases — el umbral de luz se narra en lx', () {
    late DevicesService devices;

    setUp(() {
      devices = DevicesService(
        config: ServerConfig(host: '127.0.0.1', port: 1),
        socket: SocketService(),
      );
      devices.debugSeedDevices([Device.fromJson(pasilloJson(lux: 17))]);
    });

    SensorTrigger trigger(String op, num value) => SensorTrigger.fromJson({
          'sensorId': 'dev_a4c13819aaa6ffff',
          'sensorField': 'lux',
          'sensorValue': value,
          'sensorOperator': op,
        });

    test('disparador: baja de / sube de', () {
      expect(sensorTriggerPhrase(trigger('lt', 30), devices),
          'Luz de Movimiento pasillo baja de 30 lx');
      expect(sensorTriggerPhrase(trigger('gte', 100), devices),
          'Luz de Movimiento pasillo sube de 100 lx');
    });

    test('condición: «si luz < 30 lx» y su cláusula', () {
      final c = AutomationCondition.sensor(
        sensorId: 'dev_a4c13819aaa6ffff',
        field: 'lux',
        value: 30,
        operator: 'lt',
      );
      expect(conditionPhrase(c, devices), 'si luz < 30 lx');
      expect(conditionClause(c, devices),
          'la luz de Movimiento pasillo está por debajo de 30 lx');
    });

    test('la cláusula del «cuando»', () {
      final a = Automation.fromJson({
        'id': 'auto_lux',
        'name': 'Pasillo',
        'icon': '⚡',
        'enabled': true,
        'mode': 'toggle',
        'trigger': {
          'type': 'sensor',
          'sensorTriggers': [trigger('lt', 30).toJson()],
        },
        'actions': <Map<String, dynamic>>[],
      });
      expect(triggerClause(a, devices), contains('la luz de Movimiento pasillo baje de 30 lx'));
    });

    test('el brightness binario sigue narrándose como siempre', () {
      final c = AutomationCondition.sensor(
        sensorId: 'dev_a4c13819aaa6ffff',
        field: 'brightness',
        value: 'darker',
      );
      expect(conditionPhrase(c, devices), 'si está oscuro');
    });
  });
}
