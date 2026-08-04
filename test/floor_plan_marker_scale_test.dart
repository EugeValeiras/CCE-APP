import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/floor_plan.dart';

// markerScale por plano (EugeValeiras/CCE#2): el tamaño de los markers es un
// atributo del plano que viene del backend, no una preferencia local.
void main() {
  FloorPlan plan(Map<String, dynamic> extra) => FloorPlan.fromJson({
        'id': 'p1',
        'name': 'PB',
        'svg': '<svg/>',
        ...extra,
      });

  group('FloorPlan.fromJson markerScale', () {
    test('parsea el factor que guarda el backend (int o double)', () {
      expect(plan({'markerScale': 1.4}).markerScale, 1.4);
      expect(plan({'markerScale': 2}).markerScale, 2.0);
    });

    test('ausente queda null — los clientes asumen 1.0', () {
      expect(plan({}).markerScale, isNull);
    });

    test('valores rotos (no num / no finito) se descartan', () {
      expect(plan({'markerScale': '1.4'}).markerScale, isNull);
      expect(plan({'markerScale': double.nan}).markerScale, isNull);
      expect(plan({'markerScale': double.infinity}).markerScale, isNull);
    });
  });

  test('withMarkerScale copia el plano preservando el resto', () {
    final original = plan({
      'icon': 'icons0:mdi:pot',
      'vacuumRoom': {'deviceId': 'dev_x', 'segmentId': 6},
      'markerScale': 1.0,
    });
    final bumped = original.withMarkerScale(1.2);
    expect(bumped.markerScale, 1.2);
    expect(bumped.id, original.id);
    expect(bumped.svg, original.svg);
    expect(bumped.icon, original.icon);
    expect(bumped.vacuumRoom?.segmentId, 6);
    // El original es inmutable: la copia no lo toca.
    expect(original.markerScale, 1.0);
  });

  group('FloorPlansData.visiblePlan', () {
    FloorPlansData data({String? activeId}) => FloorPlansData(
          plans: [plan({'id': 'a'}), plan({'id': 'b'}), plan({'id': 'c'})],
          activePlanId: activeId,
          positions: {
            'b': {
              'dev1': LightPosition(1, 1),
              'dev2': LightPosition(2, 2),
            },
            'c': {'dev3': LightPosition(3, 3)},
          },
        );

    test('respeta el candidato si existe', () {
      expect(data().visiblePlan('c')?.id, 'c');
    });

    test('candidato inexistente cae al plano con más devices posicionados',
        () {
      expect(data().visiblePlan('borrado')?.id, 'b');
      expect(data().visiblePlan(null)?.id, 'b');
    });

    test('sin planos devuelve null', () {
      final empty = FloorPlansData(
        plans: const [],
        activePlanId: null,
        positions: const {},
      );
      expect(empty.visiblePlan('a'), isNull);
    });
  });
}
