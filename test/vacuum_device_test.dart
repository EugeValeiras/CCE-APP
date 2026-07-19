// Test de contrato del VACUUM: parsea el payload REAL del Roborock Qrevo
// (capturado en vivo de GET /api/devices/merged, dev_9749ba54ab83) y verifica
// el arquetipo isVacuum + las exclusiones (no-luz, no-sensor).
//
// AISLADO A PROPÓSITO (mismo criterio que device_fixture_test): importa SOLO
// models/device.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';

/// Shape real del merged device (2026-07-19). El sidecar puede sumar
/// rooms/fanSpeed/fanSpeeds cuando tiene sesión — se testean aparte.
const vacuumJson = <String, dynamic>{
  'id': 'dev_9749ba54ab83',
  'name': 'Roborock Qrevo',
  'type': 'Robotic vacuum',
  'manufacturer': 'Matter',
  'capabilities': ['vacuum'],
  'state': {
    'on': false,
    'bri': 0,
    'reachable': true,
    'vacuumState': 'docked',
    'cleanMode': 'Deep Clean, Vacuum and Mop',
    'cleanModes': [
      'Quiet, Vacuum Only',
      'Auto, Vacuum Only',
      'Deep Clean, Vacuum Only',
      'Quiet, Mop Only',
      'Auto, Mop Only',
      'Deep Clean, Mop Only',
      'Quiet, Vacuum and Mop',
      'Auto, Vacuum and Mop',
      'Deep Clean, Vacuum and Mop',
    ],
    'battery': 100,
  },
  'bindings': [
    {
      'bindingId': 'matter_10648728013574452593_1',
      'provider': 'matter',
      'capabilities': ['vacuum'],
      'available': true,
      'priority': 10,
    }
  ],
  'hidden': false,
};

void main() {
  group('Device.fromJson (vacuum real)', () {
    test('parsea el payload vivo del Qrevo', () {
      final d = Device.fromJson(Map<String, dynamic>.from(vacuumJson));
      expect(d.id, 'dev_9749ba54ab83');
      expect(d.state.vacuumState, 'docked');
      expect(d.state.cleanMode, 'Deep Clean, Vacuum and Mop');
      expect(d.state.cleanModes, hasLength(9));
      expect(d.state.battery, 100);
      expect(d.state.reachable, isTrue);
    });

    test('arquetipo: isVacuum y exclusiones', () {
      final d = Device.fromJson(Map<String, dynamic>.from(vacuumJson));
      expect(d.isVacuum, isTrue);
      // Sin la exclusión en isLight el robot aparecería como luz fantasma.
      expect(d.isLight, isFalse);
      expect(d.isSensorDevice, isFalse);
      expect(d.isThermostat, isFalse);
      expect(d.isLock, isFalse);
      expect(d.isMediaDevice, isFalse);
    });

    test('rooms del sidecar (vacuum_rooms) parsean con segmentId', () {
      final json = Map<String, dynamic>.from(vacuumJson);
      json['state'] = {
        ...vacuumJson['state'] as Map,
        'rooms': [
          {'id': 'r16', 'name': 'Cocina', 'segmentId': 16},
          {'id': 'r17', 'name': 'Living', 'segmentId': 17},
        ],
        'fanSpeed': 'Balanced',
        'fanSpeeds': ['Quiet', 'Balanced', 'Turbo', 'Max'],
      };
      final d = Device.fromJson(json);
      expect(d.state.rooms, hasLength(2));
      expect(d.state.rooms!.first.name, 'Cocina');
      expect(d.state.rooms!.first.segmentId, 16);
      expect(d.state.fanSpeed, 'Balanced');
      expect(d.state.fanSpeeds, hasLength(4));
    });

    test('copyWith conserva los campos vacuum no tocados', () {
      final d = Device.fromJson(Map<String, dynamic>.from(vacuumJson));
      final next = d.state.copyWith(vacuumState: 'cleaning');
      expect(next.vacuumState, 'cleaning');
      expect(next.cleanMode, 'Deep Clean, Vacuum and Mop');
      expect(next.cleanModes, hasLength(9));
      expect(next.battery, 100);
    });

    test('state sin campos vacuum → null (no defaults inventados)', () {
      final d = Device.fromJson({
        'id': 'dev_x',
        'name': 'Luz',
        'type': 'Dimmable light',
        'capabilities': ['switch', 'brightness'],
        'state': {'on': true, 'bri': 128, 'reachable': true},
      });
      expect(d.state.vacuumState, isNull);
      expect(d.state.cleanModes, isNull);
      expect(d.state.battery, isNull);
      expect(d.isVacuum, isFalse);
    });
  });
}
