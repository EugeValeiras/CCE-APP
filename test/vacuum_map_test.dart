import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/vacuum_map.dart';

/// Espejo del vector sintético del backend (roborock-map.spec.ts): grid 4x3 en
/// espacio pantalla, ya flipado por el server. Acá se valida SOLO la
/// decodificación (deflate+base64) y la semántica de bytes — el flip no es
/// asunto de la app.
void main() {
  int floor(int seg) => (seg << 3) | 7;

  Map<String, dynamic> mapJson() {
    final grid = [
      // fila 0 (arriba): fuera, fuera, pared, piso seg17
      0, 0, 1, floor(17),
      // fila 1: pared, piso s/seg, piso seg17, fuera
      1, floor(0), floor(17), 0,
      // fila 2 (abajo): fuera, pared, piso seg16, piso seg16
      0, 1, floor(16), floor(16),
    ];
    return {
      'width': 4,
      'height': 3,
      'pixelSizeMm': 50,
      'grid': base64Encode(zlib.encode(grid)),
      'gridEncoding': 'deflate+base64',
      'segments': [16, 17],
      'robot': {'x': 2.0, 'y': 2.0, 'angle': -90},
      'charger': {'x': 1.0, 'y': 3.0},
      'path': [
        [1.0, 3.0],
        [2.0, 2.0],
      ],
      'mapIndex': 7,
      'mapSequence': 42,
    };
  }

  test('fromJson decodifica el grid y la metadata', () {
    final map = VacuumMapData.fromJson(mapJson())!;
    expect(map.width, 4);
    expect(map.height, 3);
    expect(map.grid.length, 12);
    expect(map.segments, [16, 17]);
    expect(map.robot!.x, 2.0);
    expect(map.robotAngle, -90);
    expect(map.charger!.y, 3.0);
    expect(map.path.length, 2);
    expect(map.mapSequence, 42);
  });

  test('semántica de bytes: kindAt y segmentAt', () {
    final map = VacuumMapData.fromJson(mapJson())!;
    expect(map.kindAt(0, 0), 0); // fuera
    expect(map.kindAt(2, 0), 1); // pared
    expect(map.segmentAt(3, 0), 17);
    expect(map.segmentAt(1, 1), isNull); // piso sin segmento
    expect(map.segmentAt(2, 2), 16);
    expect(map.segmentAt(2, 0), isNull); // pared no es piso
    expect(map.segmentAt(-1, 5), isNull); // fuera de rango no explota
  });

  test('formas inesperadas devuelven null en vez de romper', () {
    expect(VacuumMapData.fromJson({}), isNull);
    // Encoding desconocido.
    final bad = mapJson()..['gridEncoding'] = 'raw';
    expect(VacuumMapData.fromJson(bad), isNull);
    // Grid que no matchea width*height.
    final short = mapJson()..['grid'] = base64Encode(zlib.encode([1, 2, 3]));
    expect(VacuumMapData.fromJson(short), isNull);
    // Base64 corrupto.
    final corrupt = mapJson()..['grid'] = '@@@no-base64@@@';
    expect(VacuumMapData.fromJson(corrupt), isNull);
  });
}
