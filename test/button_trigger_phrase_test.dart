import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/button_events.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/views/automations/sheets/trigger_sheet.dart';

void main() {
  // El bug: la frase del trigger trataba `lastKey` como NÚMERO DE BOTÓN y
  // decía "Botón 0 del Office 1-Button" para un pulsador de un solo botón.
  // lastKey es el TIPO de pulsación; el botón físico lo dice sensorOutlet.
  group('pressKindLabel — contrato de lastKey', () {
    test('0/1/2 son click, doble y mantenido', () {
      expect(pressKindLabel(0), 'Click');
      expect(pressKindLabel(1), 'Doble click');
      expect(pressKindLabel(2), 'Mantenido');
    });

    test('sin dato no inventa un número de botón', () {
      expect(pressKindLabel(null), 'Pulsación');
    });

    test('un código desconocido se muestra tal cual, no como botón', () {
      expect(pressKindLabel(7), 'Pulsación 7');
    });
  });

  group('lastPressValue — el "ÚLTIMA" que mostraba un guion', () {
    test('con trigTime (eWeLink) usa ese dato', () {
      final hace5min = DateTime.now().subtract(const Duration(minutes: 5));
      final v = lastPressValue(hace5min.millisecondsSinceEpoch);
      expect(v, isNot('—'));
    });

    // Hue no manda trigTime: sin respaldo el recuadro quedaba en '—' para
    // siempre, no de a ratos.
    test('sin trigTime cae al último evento del historial', () {
      final hace2h = DateTime.now().subtract(const Duration(hours: 2));
      expect(lastPressValue(null, fallback: hace2h), isNot('—'));
    });

    test('sin trigTime y sin historial recién ahí muestra el guion', () {
      expect(lastPressValue(null), '—');
      expect(lastPressValue(null, fallback: null), '—');
    });
  });

  // El tab "Sensor" del editor quedaba en GRIS al crear una automatización desde
  // un botón: el trigger se armaba a mano con sensorValue:true, pero para
  // lastKey el valor es el TIPO de pulsación (un número). defaultTriggerFor es
  // la única fuente de ese contrato.
  group('defaultTriggerFor — campo y valor por tipo de device', () {
    Device dev(String type) => Device.fromJson({
      'id': 'dev_x',
      'name': 'X',
      'type': type,
      'state': {'on': false, 'bri': 0, 'reachable': true},
    });

    test('un botón dispara por lastKey con un NÚMERO, nunca un bool', () {
      final t = defaultTriggerFor(dev('Button'));
      expect(t.sensorField, 'lastKey');
      expect(t.sensorValue, isA<int>());
      expect(t.sensorValue, 0);
    });

    test('el dial también cuenta como botón', () {
      expect(isButtonDevice(dev('Hue Tap Dial')), isTrue);
      expect(defaultTriggerFor(dev('Hue Tap Dial')).sensorField, 'lastKey');
    });

    test('contacto y movimiento sí usan bool', () {
      expect(defaultTriggerFor(dev('Contact sensor')).sensorValue, true);
      expect(defaultTriggerFor(dev('Motion sensor')).sensorValue, true);
    });

    test('el trigger serializa con el sensorId puesto', () {
      final json = defaultTriggerFor(dev('Button')).toJson();
      expect(json['sensorId'], 'dev_x');
      expect(json['sensorField'], 'lastKey');
    });
  });
}
