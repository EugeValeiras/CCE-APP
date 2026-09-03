// CCE#101 — El termostato dice si está CALENTANDO.
//
// La API manda ahora `heating` (DP102, el relé dando calor), `fault` (DP12) y
// `childLock` (DP6) en el estado del termostato, y el push LAN los trae SOLOS
// (el DP102 cambia después que el DP1). Lo que se prueba es el criterio del
// issue en la app: (a) el modelo los lee y el re-armado del socket no los
// pierde, (b) el tile dice «Calentando» / «En temperatura» / «Apagado» según
// la actividad y no según el modo, (c) el historial narra «empezó a calentar»
// / «dejó de calentar» y la falla.
//
// Estado real de la casa el 02/09: apagado, 18,3° actual, 19,5° objetivo,
// systemMode 'heat' (el MODO, que no dice si calienta ahora).
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/widgets/thermostat_tile.dart';

const _stateJson = <String, dynamic>{
  'on': false,
  'bri': 1,
  'reachable': true,
  'currentTemp': 18.3,
  'targetTemp': 19.5,
  'tempMode': 'Manual',
  'systemMode': 'heat',
  'minTemp': 5,
  'maxTemp': 45,
  'heating': false,
  'fault': 0,
  'childLock': false,
};

int _seq = 0;
EventRecord _ev(Map<String, dynamic> state) {
  _seq++;
  return EventRecord(
    time: '2026-09-03T15:00:${_seq.toString().padLeft(2, '0')}.000Z',
    id: 'e$_seq',
    channel: 'websocket',
    eventName: 'device:state-changed',
    payload: {'deviceId': 'dev_8b2bfaeba4a3', 'state': state},
  );
}

void main() {
  group('el modelo lee la actividad del relé', () {
    test('heating, fault y childLock salen del JSON', () {
      final s = DeviceState.fromJson(_stateJson);
      expect(s.heating, isFalse);
      expect(s.fault, 0);
      expect(s.childLock, isFalse);
      expect(s.systemMode, 'heat'); // el modo sigue ahí, pero no es la actividad
    });

    test('sin las claves (API vieja) quedan en null, no en false', () {
      final s = DeviceState.fromJson({'on': true, 'bri': 1, 'reachable': true});
      expect(s.heating, isNull);
      expect(s.fault, isNull);
      expect(s.childLock, isNull);
    });

    test('copyWith conserva los tres campos', () {
      final s = DeviceState.fromJson(_stateJson).copyWith(on: true);
      expect(s.heating, isFalse);
      expect(s.fault, 0);
      expect(s.childLock, isFalse);
      expect(s.copyWith(heating: true).heating, isTrue);
    });
  });

  group('la franja del tile dice qué está HACIENDO', () {
    final base = DeviceState.fromJson(_stateJson);

    test('apagado', () {
      expect(thermostatStateLabel(base, heating: false), 'Apagado');
    });

    test('prendido y en temperatura, con el ambiente al lado', () {
      final s = base.copyWith(on: true, heating: false);
      expect(thermostatStateLabel(s, heating: false), 'En temperatura · 18.3°');
    });

    test('calentando: el relé da calor, aunque el modo fuera heat desde antes', () {
      final s = base.copyWith(on: true, heating: true);
      expect(thermostatStateLabel(s, heating: true), 'Calentando · 18.3°');
    });

    test('sin heating (API vieja) conserva la franja de siempre', () {
      final s = DeviceState.fromJson({
        'on': true,
        'bri': 1,
        'reachable': true,
        'currentTemp': 20.7,
      });
      expect(thermostatStateLabel(s, heating: false), 'Actual 20.7°');
    });

    test('sin conexión manda sobre todo', () {
      final s = base.copyWith(on: true, heating: true, reachable: false);
      expect(thermostatStateLabel(s, heating: true), 'Sin conexión');
    });
  });

  group('el historial narra la actividad', () {
    final devices =
        DevicesService(config: ServerConfig(), socket: SocketService());

    test('empezó a calentar, con la llama', () {
      final r = presentEvent(_ev({'heating': true}), devices);
      expect(r.title, endsWith('empezó a calentar'));
      expect(r.color, CceColors.warm);
    });

    test('dejó de calentar', () {
      final r = presentEvent(_ev({'heating': false}), devices);
      expect(r.title, endsWith('dejó de calentar'));
    });

    test('apagarse manda sobre el heating:false que viene con el mismo push', () {
      final r = presentEvent(_ev({'on': false, 'heating': false}), devices);
      expect(r.title, endsWith(': apagado'));
    });

    test('una falla manda sobre todo y es roja', () {
      final r = presentEvent(_ev({'fault': 3, 'heating': false}), devices);
      expect(r.title, 'Falla del termostato (código 3)');
      expect(r.color, CceColors.danger);
    });

    test('fault 0 es «sin falla» y no se narra', () {
      final r = presentEvent(_ev({'fault': 0, 'currentTemp': 20}), devices);
      expect(r.subtitle, '20.0°');
      expect(r.title, isNot(contains('Falla')));
    });

    test('el objetivo y la temperatura siguen leyéndose', () {
      expect(presentEvent(_ev({'targetTemp': 21.5}), devices).subtitle, 'a 21.5°');
      expect(presentEvent(_ev({'currentTemp': 18.3}), devices).subtitle, '18.3°');
    });
  });
}
