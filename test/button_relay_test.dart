// Test de contrato del RELÉ-PULSADOR (EugeValeiras/CCE#40).
//
// Un device que declara `switch` Y `button` a la vez es un actuador que además
// es una tecla de pared. El caso real es el SONOFF ZBMINIR2 en modo detach: su
// `state.on` es cierto pero no controla ninguna luz, así que el plano lo pinta
// NEUTRO en vez de encendido.
//
// Lo que este test protege es que el criterio siga siendo QUIRÚRGICO: ninguna
// luz, ningún botón a pilas y ningún sensor puro puede caer adentro. Los
// payloads salen de GET /api/devices/merged de la casa real (2026-08-28), donde
// de 68 devices matchea exactamente uno.
//
// AISLADO A PROPÓSITO (mismo criterio que device_fixture_test): importa SOLO
// models/device.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';

/// Shape real del relé en detach (merged, 2026-08-28).
const relayJson = <String, dynamic>{
  'id': 'dev_6ce4a4fffe449134',
  'name': 'Living patio interno',
  'type': 'eWeLink Switch Button',
  'manufacturer': 'SONOFF',
  'productname': 'ZBMINIR2',
  'modelid': 'ZBMINIR2',
  'capabilities': ['sensor', 'button', 'switch'],
  'state': {'on': true, 'bri': 1, 'reachable': true},
  'sensor': {'lastKey': 0},
  'bindings': [
    {
      'bindingId': 'ewelink_acc4002926',
      'provider': 'ewelink',
      'identifier': '6ce4a4fffe449134',
      'capabilities': ['sensor', 'button', 'switch'],
      'available': true,
      'priority': 40,
      'commandable': true,
    }
  ],
  'preferredBindingId': 'ewelink_acc4002926',
  'hidden': false,
};

Device dev(String type, List<String> caps, {Map<String, dynamic>? sensor}) =>
    Device.fromJson(<String, dynamic>{
      'id': 'dev_x',
      'name': 'x',
      'type': type,
      'capabilities': caps,
      'state': {'on': true, 'bri': 1, 'reachable': true},
      'sensor': ?sensor,
    });

void main() {
  group('Device.isButtonRelay (payloads reales)', () {
    test('el ZBMINIR2 en detach matchea, con state.on true', () {
      final d = Device.fromJson(Map<String, dynamic>.from(relayJson));
      expect(d.isButtonRelay, isTrue);
      expect(d.state.on, isTrue,
          reason: 'el bug es justamente que on:true se pintaba como encendido');
      expect(d.state.reachable, isTrue,
          reason: 'neutro NO es "sin conexión": son lecturas distintas');
    });

    test('las luces declaran switch SIN button: no cambian en nada', () {
      expect(
          dev('Extended color light', [
            'brightness',
            'color_hsv',
            'color_temperature',
            'switch'
          ]).isButtonRelay,
          isFalse);
      expect(dev('Tuya Light', ['brightness', 'switch']).isButtonRelay, isFalse);
      expect(dev('On/Off light', ['switch']).isButtonRelay, isFalse);
    });

    test('los botones a pilas declaran button SIN switch', () {
      expect(
          dev('eWeLink Button', ['button', 'sensor'],
              sensor: {'battery': '100', 'lastKey': 0}).isButtonRelay,
          isFalse);
      expect(
          dev('Hue Switch', ['button', 'dial', 'sensor'],
              sensor: {'battery': '100', 'outlets': 4}).isButtonRelay,
          isFalse);
    });

    test('sensores puros, termostato, robot y TV tampoco matchean', () {
      expect(
          dev('eWeLink Motion Sensor', ['sensor'],
              sensor: {'motion': false}).isButtonRelay,
          isFalse);
      expect(
          dev('Tuya Thermostat', ['sensor', 'switch', 'thermostat'])
              .isButtonRelay,
          isFalse);
      expect(dev('Robotic vacuum', ['vacuum']).isButtonRelay, isFalse);
      expect(
          dev('tv', [
            'app_launcher',
            'channel',
            'input_select',
            'media_playback',
            'switch',
            'volume'
          ]).isButtonRelay,
          isFalse);
    });

    test('sin capabilities, o con una sola de las dos, no alcanza', () {
      expect(dev('lo que sea', const []).isButtonRelay, isFalse);
      expect(dev('lo que sea', ['switch']).isButtonRelay, isFalse);
      expect(dev('lo que sea', ['button']).isButtonRelay, isFalse);
    });

    test('el relé no rompe los arquetipos que ya existían', () {
      final d = Device.fromJson(Map<String, dynamic>.from(relayJson));
      expect(d.isLight, isFalse, reason: 'no es una luz');
      expect(d.isThermostat, isFalse);
      expect(d.isLock, isFalse, reason: 'la excepción de la cerradura sigue suya');
      expect(d.isVacuum, isFalse, reason: 'la excepción del robot sigue suya');
      expect(d.isSwitch, isTrue, reason: 'sigue abriendo su pantalla de switch');
    });
  });
}
