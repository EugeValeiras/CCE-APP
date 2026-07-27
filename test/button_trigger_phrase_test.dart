import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/button_events.dart';

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
}
