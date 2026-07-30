import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/utils/vacuum_state.dart';

/// Device mínimo del robot con el estado dado (misma forma que manda la API).
Device robot(Map<String, dynamic> state) => Device.fromJson({
      'id': 'dev_9749ba54ab83',
      'name': 'Roborock Qrevo',
      'type': 'Robotic vacuum',
      'state': state,
    });

void main() {
  group('vacuumStateLabel', () {
    test('la actividad del sidecar manda sobre el vacuumState de Matter', () {
      // Caso real medido el 2026-07-30: Matter dice 'docked' pero el robot
      // está cargando — el label debe salir de la actividad.
      expect(
        vacuumStateLabel(robot({'vacuumState': 'docked', 'vacuumActivity': 'charging'})),
        'Cargando',
      );
      expect(
        vacuumStateLabel(robot({'vacuumState': 'docked', 'vacuumActivity': 'washing_mop'})),
        'Lavando la mopa',
      );
      // Y al revés: vacuumState pegado en 'cleaning' (incidente 2026-07-29)
      // con el robot quieto en la base.
      expect(
        vacuumStateLabel(robot({'vacuumState': 'cleaning', 'vacuumActivity': 'charging'})),
        'Cargando',
      );
    });

    test('estados en habitación llevan el nombre reportado por el robot', () {
      expect(
        vacuumStateLabel(robot({
          'vacuumActivity': 'segment_cleaning',
          'vacuumRoomName': 'Kitchen',
        })),
        'Limpiando Kitchen',
      );
      expect(
        vacuumStateLabel(robot({
          'vacuumActivity': 'going_to_target',
          'vacuumRoomName': 'Living room',
        })),
        'Moviéndose a Living room',
      );
      // Una faena en la base NO lleva habitación aunque haya cola viva.
      expect(
        vacuumStateLabel(robot({
          'vacuumActivity': 'washing_mop',
          'vacuumRoomName': 'Kitchen',
        })),
        'Lavando la mopa',
      );
    });

    test('sin sesión del sidecar cae al vacuumState de Matter', () {
      expect(vacuumStateLabel(robot({'vacuumState': 'docked'})), 'En la base');
      expect(vacuumStateLabel(robot({'vacuumState': 'cleaning'})), 'Limpiando');
      expect(vacuumStateLabel(robot({'vacuumState': 'error'})), 'Con error');
      expect(vacuumStateLabel(robot({})), isNull);
    });

    test('actividad desconocida no inventa label: cae al fallback', () {
      expect(
        vacuumStateLabel(robot({'vacuumState': 'docked', 'vacuumActivity': 'mystery'})),
        'En la base',
      );
    });
  });

  group('vacuumWorking', () {
    test('las faenas en la base cuentan como trabajando', () {
      expect(vacuumWorking(robot({'vacuumActivity': 'washing_mop'})), isTrue);
      expect(vacuumWorking(robot({'vacuumActivity': 'emptying_bin'})), isTrue);
    });

    test('cargando o en reposo no es trabajar', () {
      expect(vacuumWorking(robot({'vacuumActivity': 'charging'})), isFalse);
      expect(vacuumWorking(robot({'vacuumActivity': 'idle'})), isFalse);
    });

    test('la actividad manda: Matter pegado en cleaning no engaña', () {
      expect(
        vacuumWorking(robot({'vacuumState': 'cleaning', 'vacuumActivity': 'charging'})),
        isFalse,
      );
    });

    test('fallback a vacuumState sin sidecar', () {
      expect(vacuumWorking(robot({'vacuumState': 'cleaning'})), isTrue);
      expect(vacuumWorking(robot({'vacuumState': 'docked'})), isFalse);
    });
  });
}
