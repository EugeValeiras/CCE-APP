import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/floor_plan.dart';

void main() {
  group('VacuumRoomLink.fromJson', () {
    test('parsea el vínculo que guarda el dashboard', () {
      final link = VacuumRoomLink.fromJson(
        {'deviceId': 'dev_9749ba54ab83', 'segmentId': 6},
      );
      expect(link, isNotNull);
      expect(link!.deviceId, 'dev_9749ba54ab83');
      expect(link.segmentId, 6);
    });

    // Al desvincular, el backend deja la clave en null: no debe romper.
    test('null / ausente / tipo raro dan null en vez de tirar', () {
      expect(VacuumRoomLink.fromJson(null), isNull);
      expect(VacuumRoomLink.fromJson('nada'), isNull);
      expect(VacuumRoomLink.fromJson(const []), isNull);
    });

    test('descarta vínculos incompletos', () {
      expect(VacuumRoomLink.fromJson({'segmentId': 6}), isNull);
      expect(VacuumRoomLink.fromJson({'deviceId': 'dev_x'}), isNull);
      expect(VacuumRoomLink.fromJson({'deviceId': '', 'segmentId': 6}), isNull);
    });
  });

  group('FloorPlan.fromJson', () {
    test('trae el vacuumRoom junto al resto del plano', () {
      final plan = FloorPlan.fromJson({
        'id': 'p1',
        'name': 'Cocina',
        'svg': '<svg/>',
        'icon': 'icons0:mdi:pot',
        'vacuumRoom': {'deviceId': 'dev_x', 'segmentId': 6},
      });
      expect(plan.vacuumRoom?.segmentId, 6);
      expect(plan.icon, 'icons0:mdi:pot');
    });

    test('un plano sin vínculo (el caso normal) queda en null', () {
      final plan = FloorPlan.fromJson({'id': 'p1', 'name': 'X', 'svg': ''});
      expect(plan.vacuumRoom, isNull);
    });
  });

  group('VacuumRoomQueue', () {
    Map<String, dynamic> queueJson() => {
          'segments': [3, 6, 9],
          'names': ['Living room', 'Kitchen', 'Office'],
          'current': 1,
          'phase': 'running',
        };

    test('parsea el progreso que publica el sidecar', () {
      final q = VacuumRoomQueue.fromJson(queueJson());
      expect(q, isNotNull);
      expect(q!.segments, [3, 6, 9]);
      expect(q.current, 1);
      expect(q.currentSegment, 6);
      expect(q.phase, 'running');
    });

    test('currentSegment no explota si el índice viene fuera de rango', () {
      final q = VacuumRoomQueue.fromJson({...queueJson(), 'current': 9});
      expect(q!.currentSegment, isNull);
    });

    test('sin cola / sin segmentos da null', () {
      expect(VacuumRoomQueue.fromJson(null), isNull);
      expect(VacuumRoomQueue.fromJson({'segments': []}), isNull);
    });

    test('DeviceState levanta el roomQueue del JSON del device', () {
      final st = DeviceState.fromJson({
        'on': false,
        'vacuumState': 'cleaning',
        'roomQueue': queueJson(),
      });
      expect(st.roomQueue?.currentSegment, 6);
    });

    test('un device sin cola deja roomQueue en null', () {
      final st = DeviceState.fromJson({'on': false, 'vacuumState': 'docked'});
      expect(st.roomQueue, isNull);
    });
  });
}
