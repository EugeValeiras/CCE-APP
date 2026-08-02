import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/floor_plan.dart';
import 'package:cce_app/models/vacuum_map.dart';

/// El ancla y la posición en vivo son las dos mitades de "el robot sobre el
/// plano": si el mapeo se corre, el robot se dibuja en otra habitación, y si el
/// parseo no es defensivo un plano con datos raros rompe la pantalla entera.
void main() {
  VacuumAnchor anchor({
    double scale = 1,
    double offsetX = 0,
    double offsetY = 0,
    double rotationDeg = 0,
  }) =>
      VacuumAnchor(
        deviceId: 'dev_9749ba54ab83',
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY,
        rotationDeg: rotationDeg,
      );

  group('VacuumAnchor.toPlan', () {
    test('sin rotación: escala y traslada el píxel absoluto del mapa', () {
      final a = anchor(offsetX: 100, offsetY: 50);
      expect(a.toPlan(0, 0), (x: 100.0, y: 50.0));
      expect(a.toPlan(10, 20), (x: 110.0, y: 70.0));
      // Los planos generados salen con scale 1 (1 px de RRMap = 1 unidad), pero
      // el campo existe para planos con otra calibración.
      expect(anchor(scale: 2).toPlan(3, 4), (x: 6.0, y: 8.0));
    });

    test('rotationDeg 90 gira en horario (el plano tiene la y para abajo)', () {
      final p = anchor(rotationDeg: 90).toPlan(10, 0);
      expect(p.x, closeTo(0, 1e-9));
      expect(p.y, closeTo(10, 1e-9));
      final q = anchor(rotationDeg: 90).toPlan(0, 10);
      expect(q.x, closeTo(-10, 1e-9));
      expect(q.y, closeTo(0, 1e-9));
    });

    test('rotationDeg 180 espeja, y el offset se aplica DESPUÉS de rotar', () {
      final p = anchor(rotationDeg: 180, offsetX: 5, offsetY: 5).toPlan(10, 5);
      expect(p.x, closeTo(-5, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
    });

    test('rotationDeg 45 con escala: la fórmula del contrato, tal cual', () {
      // planX = offsetX + scale·(x·cos θ − y·sin θ), ídem Y.
      final p = anchor(scale: 2, rotationDeg: 45).toPlan(1, 0);
      expect(p.x, closeTo(1.41421356, 1e-6));
      expect(p.y, closeTo(1.41421356, 1e-6));
    });

    test('dos lecturas distintas mapean a puntos distintos y coherentes', () {
      final a = anchor(offsetX: -1520, offsetY: -2040);
      final p1 = a.toPlan(1600, 2100);
      final p2 = a.toPlan(1610, 2100);
      expect(p1, (x: 80.0, y: 60.0));
      expect(p2.x - p1.x, 10.0); // 10 px de mapa = 50 cm reales
      expect(p2.y, p1.y);
    });
  });

  group('VacuumAnchor.fromJson', () {
    test('parsea el ancla que guarda el dashboard', () {
      final a = VacuumAnchor.fromJson({
        'deviceId': 'dev_9749ba54ab83',
        'scale': 1,
        'offsetX': -1520,
        'offsetY': -2040.5,
        'rotationDeg': 0,
      });
      expect(a, isNotNull);
      expect(a!.deviceId, 'dev_9749ba54ab83');
      expect(a.scale, 1.0);
      expect(a.offsetX, -1520.0);
      expect(a.offsetY, -2040.5);
      expect(a.rotationDeg, 0.0);
    });

    test('sin rotationDeg asume 0 (el caso de los planos generados)', () {
      final a = VacuumAnchor.fromJson(
        {'deviceId': 'dev_x', 'scale': 1, 'offsetX': 0, 'offsetY': 0},
      );
      expect(a?.rotationDeg, 0.0);
    });

    // Al desanclar, el backend deja la clave en null: no debe romper.
    test('null / ausente / tipo raro dan null en vez de tirar', () {
      expect(VacuumAnchor.fromJson(null), isNull);
      expect(VacuumAnchor.fromJson('nada'), isNull);
      expect(VacuumAnchor.fromJson(const []), isNull);
    });

    test('descarta anclas incompletas o imposibles', () {
      expect(VacuumAnchor.fromJson({'scale': 1, 'offsetX': 0, 'offsetY': 0}),
          isNull);
      expect(
          VacuumAnchor.fromJson(
              {'deviceId': '', 'scale': 1, 'offsetX': 0, 'offsetY': 0}),
          isNull);
      expect(VacuumAnchor.fromJson({'deviceId': 'dev_x', 'scale': 1}), isNull);
      // Escala 0 o negativa: colapsaría el robot en un punto.
      expect(
          VacuumAnchor.fromJson(
              {'deviceId': 'dev_x', 'scale': 0, 'offsetX': 0, 'offsetY': 0}),
          isNull);
      expect(
          VacuumAnchor.fromJson({
            'deviceId': 'dev_x',
            'scale': double.nan,
            'offsetX': 0,
            'offsetY': 0,
          }),
          isNull);
      expect(
          VacuumAnchor.fromJson({
            'deviceId': 'dev_x',
            'scale': 1,
            'offsetX': double.infinity,
            'offsetY': 0,
          }),
          isNull);
    });

    test('una rotación con forma rara cae a 0, no invalida el ancla', () {
      final a = VacuumAnchor.fromJson({
        'deviceId': 'dev_x',
        'scale': 1,
        'offsetX': 0,
        'offsetY': 0,
        'rotationDeg': 'mucho',
      });
      expect(a?.rotationDeg, 0.0);
    });
  });

  group('FloorPlan.fromJson', () {
    test('trae el vacuumAnchor junto al resto del plano', () {
      final plan = FloorPlan.fromJson({
        'id': 'p1',
        'name': 'Cocina',
        'svg': '<svg/>',
        'vacuumRoom': {'deviceId': 'dev_x', 'segmentId': 6},
        'vacuumAnchor': {
          'deviceId': 'dev_x',
          'scale': 1,
          'offsetX': 10,
          'offsetY': 20,
        },
      });
      expect(plan.vacuumAnchor?.deviceId, 'dev_x');
      expect(plan.vacuumAnchor?.offsetX, 10.0);
      expect(plan.vacuumRoom?.segmentId, 6);
    });

    // Todos los planos dibujados a mano: la capa del robot no se monta y la
    // pantalla queda exactamente como antes.
    test('un plano sin ancla (el caso normal hoy) queda en null', () {
      final plan = FloorPlan.fromJson({'id': 'p1', 'name': 'X', 'svg': ''});
      expect(plan.vacuumAnchor, isNull);
    });

    test('un ancla rota no se lleva puesto el plano', () {
      final plan = FloorPlan.fromJson({
        'id': 'p1',
        'name': 'X',
        'svg': '<svg/>',
        'vacuumAnchor': {'deviceId': 'dev_x'},
      });
      expect(plan.vacuumAnchor, isNull);
      expect(plan.name, 'X');
    });
  });

  group('VacuumPosition.fromJson', () {
    test('parsea la posición que publica el sidecar', () {
      final p = VacuumPosition.fromJson({
        'x': 1600.5,
        'y': 2100,
        'angle': 137.4,
        'segmentId': 6,
        'at': 1785000000000,
      });
      expect(p, isNotNull);
      expect(p!.x, 1600.5);
      expect(p.y, 2100.0);
      expect(p.angle, 137.4);
      expect(p.segmentId, 6);
      expect(p.at, 1785000000000);
    });

    test('sin ángulo / sin segmento sigue siendo una posición válida', () {
      final p = VacuumPosition.fromJson(
        {'x': 10, 'y': 20, 'angle': null, 'segmentId': null},
      );
      expect(p?.x, 10.0);
      expect(p?.angle, isNull);
      expect(p?.segmentId, isNull);
      expect(p?.at, isNull);
    });

    test('null / sin coordenadas / tipo raro dan null en vez de tirar', () {
      expect(VacuumPosition.fromJson(null), isNull);
      expect(VacuumPosition.fromJson('nada'), isNull);
      expect(VacuumPosition.fromJson({'y': 20}), isNull);
      expect(VacuumPosition.fromJson({'x': 'lejos', 'y': 20}), isNull);
      expect(VacuumPosition.fromJson({'x': double.nan, 'y': 20}), isNull);
    });

    test('dos lecturas iguales son iguales (no disparan animación)', () {
      final a = VacuumPosition.fromJson({'x': 1, 'y': 2, 'at': 10});
      final b = VacuumPosition.fromJson({'x': 1, 'y': 2, 'at': 10});
      final c = VacuumPosition.fromJson({'x': 1, 'y': 2, 'at': 20});
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('DeviceState', () {
    test('levanta la vacuumPosition del estado del device', () {
      final st = DeviceState.fromJson({
        'on': false,
        'vacuumState': 'cleaning',
        'vacuumActivity': 'segment_cleaning',
        'vacuumPosition': {'x': 1600, 'y': 2100, 'angle': 90, 'at': 1},
      });
      expect(st.vacuumPosition?.x, 1600.0);
      expect(st.vacuumPosition?.angle, 90.0);
    });

    test('un robot que no trabaja no trae posición', () {
      final st = DeviceState.fromJson(
        {'on': false, 'vacuumState': 'docked', 'vacuumPosition': null},
      );
      expect(st.vacuumPosition, isNull);
    });

    test('el resto del estado no se entera si la posición viene rota', () {
      final st = DeviceState.fromJson({
        'on': false,
        'battery': 82,
        'vacuumPosition': {'x': 'ahi'},
      });
      expect(st.vacuumPosition, isNull);
      expect(st.battery, 82);
    });
  });
}
