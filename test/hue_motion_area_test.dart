// Hue MotionAware on/off (EugeValeiras/CCE#96): el sensor del área gana
// `switch` y es el ÚNICO sensor cuyo `on` se escribe. Lo que fija este test es
// la clasificación —de ella salen el rótulo «MotionAware», el toggle en la
// pantalla del sensor y que el wizard lo ofrezca— y que ningún otro sensor la
// herede.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';

Device device(Map<String, dynamic> over) => Device.fromJson({
  'id': 'dev_x',
  'name': 'X',
  'type': 'Hue Motion Sensor',
  'capabilities': ['sensor', 'motion'],
  'state': {'on': true, 'bri': 0, 'reachable': true},
  'sensor': {'motion': false},
  ...over,
});

void main() {
  group('isHueMotionArea', () {
    test('el área de la casa: sensor + motion + switch por un binding hue', () {
      final hall = device({
        'id': 'dev_d0901c3c59d6',
        'name': 'Hall',
        'capabilities': ['sensor', 'motion', 'switch'],
        'bindings': [
          {
            'bindingId': 'hue_C42996FFFECB8971_sensor_area_2231ae14',
            'provider': 'hue',
          },
        ],
      });
      expect(hall.isHueMotionArea, isTrue);
      expect(hall.hasRealOnOff, isTrue);
      // Sigue siendo un sensor de movimiento, no una luz ni un switch de pared.
      expect(hall.isMotionSensor, isTrue);
      expect(hall.isSensorDevice, isTrue);
      expect(hall.isLight, isFalse);
      expect(hall.isSwitch, isFalse);
    });

    test('también con `source` hue y sin bindings (payload legacy)', () {
      final hall = device({
        'source': 'hue',
        'capabilities': ['sensor', 'motion', 'switch'],
      });
      expect(hall.isHueMotionArea, isTrue);
    });

    test('un Hue Motion Sensor PIR (sin switch) no es un área', () {
      final pir = device({
        'source': 'hue',
        'capabilities': ['sensor', 'motion'],
      });
      expect(pir.isHueMotionArea, isFalse);
      expect(pir.hasRealOnOff, isFalse);
    });

    test('motion + switch de otro proveedor no es un área de Hue', () {
      final otro = device({
        'source': 'ewelink',
        'capabilities': ['sensor', 'motion', 'switch'],
        'bindings': [
          {'bindingId': 'ewelink_1000abcd', 'provider': 'ewelink'},
        ],
      });
      expect(otro.isHueMotionArea, isFalse);
    });

    test('una luz Hue no es un área', () {
      final luz = device({
        'type': 'Extended color light',
        'source': 'hue',
        'capabilities': ['switch', 'brightness', 'color_hsv'],
        'sensor': null,
      });
      expect(luz.isHueMotionArea, isFalse);
      expect(luz.hasRealOnOff, isTrue);
    });
  });

  group('hasRealOnOff (guard del on polisémico)', () {
    test('cerradura y alarma NO: su on es trabada / armada', () {
      expect(
        device({
          'type': 'lock',
          'capabilities': ['switch', 'lock'],
          'sensor': null,
        }).hasRealOnOff,
        isFalse,
      );
      expect(
        device({
          'type': 'Alarm',
          'capabilities': ['switch', 'alarm'],
          'sensor': null,
        }).hasRealOnOff,
        isFalse,
      );
    });
  });
}
