import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/capability_renderers.dart';

void main() {
  List<CapabilityRendererKind> kinds(List<String> caps) =>
      capabilityRenderersFor(caps).map((e) => e.kind).toList();

  group('capabilityRenderersFor', () {
    test('luz típica: switch + brightness en orden canónico', () {
      expect(kinds(['switch', 'brightness']),
          [CapabilityRendererKind.onoff, CapabilityRendererKind.brightness]);
    });

    test('orden canónico: onoff siempre antes que brightness', () {
      expect(kinds(['brightness', 'switch']),
          [CapabilityRendererKind.onoff, CapabilityRendererKind.brightness]);
    });

    test('guard on polisémico: lock reclama el on (sin onoff)', () {
      expect(kinds(['switch', 'lock']), [CapabilityRendererKind.lock]);
    });

    test('guard on polisémico: alarm reclama el on (sin onoff)', () {
      expect(kinds(['switch', 'alarm']), [CapabilityRendererKind.alarm]);
    });

    test('sensores colapsan a un solo readout (dedupe por kind)', () {
      expect(kinds(['sensor', 'motion', 'contact']),
          [CapabilityRendererKind.sensor]);
    });

    test('capability desconocida se ignora (forward-compat)', () {
      expect(kinds(['switch', 'capacidad_del_futuro']),
          [CapabilityRendererKind.onoff]);
    });

    test('vacía → sin renderers', () {
      expect(kinds([]), isEmpty);
    });

    test('vacuum va primero, sensor al final', () {
      final result = kinds(['sensor', 'vacuum', 'switch']);
      expect(result.first, CapabilityRendererKind.vacuum);
      expect(result.last, CapabilityRendererKind.sensor);
    });
  });
}
