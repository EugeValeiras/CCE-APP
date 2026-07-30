import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/vacuum_modes.dart';

/// Los 9 cleanModes REALES del Roborock Qrevo (capturados en vivo del device
/// dev_9749ba54ab83 vía Matter RvcCleanMode.SupportedModes).
const realModes = [
  'Quiet, Vacuum Only',
  'Auto, Vacuum Only',
  'Deep Clean, Vacuum Only',
  'Quiet, Mop Only',
  'Auto, Mop Only',
  'Deep Clean, Mop Only',
  'Quiet, Vacuum and Mop',
  'Auto, Vacuum and Mop',
  'Deep Clean, Vacuum and Mop',
];

void main() {
  group('VacuumModeMatrix.tryBuild', () {
    test('arma la matriz 3x3 con los modos reales del Qrevo', () {
      final m = VacuumModeMatrix.tryBuild(realModes);
      expect(m, isNotNull);
      expect(m!.powers, ['Quiet', 'Auto', 'Deep Clean']);
      expect(m.functions, ['Vacuum Only', 'Mop Only', 'Vacuum and Mop']);
    });

    test('compose devuelve el label REAL del robot', () {
      final m = VacuumModeMatrix.tryBuild(realModes)!;
      expect(m.compose('Auto', 'Vacuum and Mop'), 'Auto, Vacuum and Mop');
      expect(realModes.contains(m.compose('Deep Clean', 'Mop Only')), isTrue);
    });

    test('split descompone el modo activo', () {
      final m = VacuumModeMatrix.tryBuild(realModes)!;
      final parts = m.split('Deep Clean, Vacuum and Mop');
      expect(parts, isNotNull);
      expect(parts!.power, 'Deep Clean');
      expect(parts.function, 'Vacuum and Mop');
    });

    test('split de un modo fuera de la matriz devuelve null', () {
      final m = VacuumModeMatrix.tryBuild(realModes)!;
      expect(m.split('Turbo, Vacuum Only'), isNull);
      expect(m.split('Auto'), isNull);
      expect(m.split(null), isNull);
    });

    test('modos que no parten en dos → null (fallback a lista cruda)', () {
      expect(VacuumModeMatrix.tryBuild(['Auto', 'Turbo']), isNull);
      expect(
        VacuumModeMatrix.tryBuild(['A, B, C', 'A, B']), // doble separador
        isNull,
      );
    });

    test('producto cruzado incompleto → null', () {
      // 3 modos con 2 powers × 2 functions ≠ 3 → no es matriz completa.
      expect(
        VacuumModeMatrix.tryBuild(
            ['Quiet, Vacuum Only', 'Auto, Vacuum Only', 'Quiet, Mop Only']),
        isNull,
      );
    });

    test('lista vacía o de un elemento → null', () {
      expect(VacuumModeMatrix.tryBuild(null), isNull);
      expect(VacuumModeMatrix.tryBuild([]), isNull);
      expect(VacuumModeMatrix.tryBuild(['Auto, Vacuum Only']), isNull);
    });
  });

  group('labels español de las mitades', () {
    test('powers conocidas', () {
      expect(vacuumPowerLabel('Quiet'), 'Silencioso');
      expect(vacuumPowerLabel('Auto'), 'Auto');
      expect(vacuumPowerLabel('Deep Clean'), 'Profundo');
      expect(vacuumPowerLabel('Turbo'), 'Turbo'); // desconocida → cruda
    });

    test('functions conocidas', () {
      expect(vacuumFunctionLabel('Vacuum Only'), 'Aspirar');
      expect(vacuumFunctionLabel('Mop Only'), 'Trapear');
      expect(vacuumFunctionLabel('Vacuum and Mop'), 'Ambos');
      expect(vacuumFunctionLabel('Scrub'), 'Scrub'); // desconocida → cruda
    });
  });
}
