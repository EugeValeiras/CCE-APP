// CCE#112: el historial con el bloque sensor ACUMULADO que la API emite. Un
// evento del SNZB-03PR2 trae `motion` Y `lux` (y un Hue, `motion` y
// `temperature`; un z2m combinado, `temperature` y `lux`): las tres pantallas
// tienen que mostrar ambos. Y una corrida de `motion:false` no puede titularse
// «Movimiento».
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/history/event_grouping.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/history/numeric_readings.dart';

const pasillo = 'dev_a4c13819aaa6ffff';

EventRecord ev(String id, String time, Map<String, dynamic> sensor) => EventRecord(
      time: time,
      id: id,
      channel: 'websocket',
      eventName: 'device:state-changed',
      source: 'external',
      globalId: pasillo,
      payload: {'deviceId': pasillo, 'sensor': sensor},
    );

void main() {
  late DevicesService devices;
  setUp(() {
    devices = DevicesService(
      config: ServerConfig(host: '127.0.0.1', port: 1),
      socket: SocketService(),
    );
    devices.debugSeedDevices([
      Device.fromJson({
        'id': pasillo,
        'name': 'Movimiento pasillo',
        'type': 'eWeLink Motion Sensor',
        'capabilities': ['sensor', 'motion', 'illuminance'],
        'state': {'on': false, 'bri': 1, 'reachable': true},
        'sensor': {'motion': false, 'lux': 17, 'brightness': 'darker'},
      }),
    ]);
  });

  group('la tabla de lecturas numéricas', () {
    test('devuelve TODAS las lecturas presentes, en orden', () {
      final all = numericReadingsOf({'lux': 300, 'temperature': 21.5, 'motion': true});
      expect(all.map((r) => r.$1.key), ['temperature', 'lux']);
      expect(numericReadingsLine({'lux': 300, 'temperature': 21.5}), '21.5° · 300 lx');
      expect(numericReadingsLine({'motion': true}), isNull);
    });
  });

  group('un evento suelto', () {
    test('movimiento con lux acumulado (el camino Matter): título de movimiento Y el lux', () {
      final p = presentEvent(ev('1', '2026-09-05T12:05:00.000Z', {'motion': false, 'lux': 17, 'brightness': 'darker'}), devices);
      expect(p.title, 'Sin movimiento en Movimiento pasillo');
      expect(p.subtitle, '17 lx');
    });

    test('movimiento sin lecturas: como siempre, sin subtítulo', () {
      final p = presentEvent(ev('1', '2026-09-05T12:05:00.000Z', {'motion': true}), devices);
      expect(p.title, 'Movimiento en Movimiento pasillo');
      expect(p.subtitle, isNull);
    });

    test('temperatura Y lux en el mismo bloque (z2m combinado): las dos', () {
      final p = presentEvent(ev('1', '2026-09-05T12:05:00.000Z', {'temperature': 21.5, 'lux': 300}), devices);
      expect(p.title, 'Movimiento pasillo');
      expect(p.subtitle, '21.5° · 300 lx');
    });

    test('lux solo (el push de eWeLink)', () {
      final p = presentEvent(ev('1', '2026-09-05T12:05:00.000Z', {'lux': 17, 'brightness': 'darker'}), devices);
      expect(p.subtitle, '17 lx');
    });
  });

  group('una corrida colapsada', () {
    test('dos motion:false se titulan «Sin movimiento», no «Movimiento»', () {
      final g = EventGroup([
        ev('2', '2026-09-05T12:06:00.000Z', {'motion': false, 'lux': 17}),
        ev('1', '2026-09-05T12:05:00.000Z', {'motion': false, 'lux': 18}),
      ]);
      final p = presentGroup(g, devices);
      expect(p.title, 'Sin movimiento en Movimiento pasillo');
      expect(p.subtitle, contains('desde'));
      expect(p.subtitle, contains('17 lx'));
    });

    test('dos motion:true siguen siendo «Movimiento»', () {
      final g = EventGroup([
        ev('2', '2026-09-05T12:06:00.000Z', {'motion': true}),
        ev('1', '2026-09-05T12:05:00.000Z', {'motion': true}),
      ]);
      expect(presentGroup(g, devices).title, 'Movimiento en Movimiento pasillo');
    });

    test('una corrida de lux se lee «de → a» y no pierde el número', () {
      final g = EventGroup([
        ev('2', '2026-09-05T12:20:00.000Z', {'lux': 22, 'brightness': 'darker'}),
        ev('1', '2026-09-05T12:05:00.000Z', {'lux': 17, 'brightness': 'darker'}),
      ]);
      final p = presentGroup(g, devices);
      expect(p.title, 'Movimiento pasillo');
      expect(p.subtitle, '17 lx → 22 lx');
    });

    test('una corrida con temperatura y lux narra las dos lecturas', () {
      final g = EventGroup([
        ev('2', '2026-09-05T12:20:00.000Z', {'temperature': 22.0, 'lux': 300}),
        ev('1', '2026-09-05T12:05:00.000Z', {'temperature': 21.5, 'lux': 300}),
      ]);
      expect(presentGroup(g, devices).subtitle, '21.5° → 22.0° · 300 lx');
    });
  });

  group('la agrupación', () {
    test('dos lecturas de lux solas dentro de 30 min forman UNA corrida', () {
      final groups = groupEvents([
        ev('2', '2026-09-05T12:20:00.000Z', {'lux': 22, 'brightness': 'darker'}),
        ev('1', '2026-09-05T12:05:00.000Z', {'lux': 17, 'brightness': 'darker'}),
      ], devices);
      expect(groups, hasLength(1));
      expect(groups.first.count, 2);
    });

    test('movimiento con lux acumulado agrupa por el movimiento (la lectura viaja de acompañante)', () {
      final groups = groupEvents([
        ev('2', '2026-09-05T12:06:00.000Z', {'motion': false, 'lux': 17}),
        ev('1', '2026-09-05T12:05:00.000Z', {'motion': false, 'lux': 18}),
      ], devices);
      expect(groups, hasLength(1));
      expect(presentGroup(groups.first, devices).title, 'Sin movimiento en Movimiento pasillo');
    });
  });
}
