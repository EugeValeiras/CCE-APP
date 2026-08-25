// Parseo y etiquetas del historial de llamadas (telefonía 4G).
//
// Lo que protege: el veredicto de una llamada NO es obvio. `not-connected`
// puede significar "no contestaron" o "sonó y la casa cortó sola" (el
// ring-and-hangup de una automatización, donde la llamada perdida ERA el
// aviso), y esa diferencia sale de `hangupBy`. Si la etiqueta se equivoca, la
// app dice que algo falló cuando en realidad funcionó como se diseñó.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/phone_call.dart';

void main() {
  group('PhoneCall.fromJson', () {
    test('llamada entrante atendida', () {
      final c = PhoneCall.fromJson({
        'direction': 'in',
        'number': '+5492616260811',
        'contactName': 'Eugenio',
        'contactId': 'c1',
        'startedAt': 1700000000000,
        'connectedAt': 1700000003600,
        'durationMs': 25000,
        'result': 'answered',
        'hangupBy': 'remote',
      });

      expect(c.incoming, isTrue);
      expect(c.displayName, 'Eugenio');
      expect(c.duration, const Duration(seconds: 25));
      expect(c.result, CallResult.answered);
      expect(c.isMissed, isFalse);
      expect(c.resultLabel, 'Atendida');
      expect(c.connectedAt, isNotNull);
    });

    test('perdida: RING sin atender', () {
      final c = PhoneCall.fromJson({
        'direction': 'in',
        'number': '+5492616260811',
        'startedAt': 1700000000000,
        'durationMs': 0,
        'result': 'missed',
      });

      expect(c.isMissed, isTrue);
      expect(c.resultLabel, 'Perdida');
      expect(c.duration, Duration.zero);
      expect(c.connectedAt, isNull);
      // Sin contacto en la libreta, se muestra el número.
      expect(c.displayName, '+5492616260811');
    });

    test('saliente de automatización: sonó y la casa cortó sola', () {
      // Ring-and-hangup: `not-connected` + hangupBy local. NO es un fallo — la
      // llamada perdida es el aviso, y así tiene que leerse.
      final c = PhoneCall.fromJson({
        'direction': 'out',
        'number': '+5492616260811',
        'startedAt': 1700000000000,
        'durationMs': 0,
        'result': 'not-connected',
        'hangupBy': 'local',
      });

      expect(c.incoming, isFalse);
      expect(c.resultLabel, 'Sonó y se cortó');
    });

    test('saliente que nadie atendió', () {
      final c = PhoneCall.fromJson({
        'direction': 'out',
        'number': '+5492616260811',
        'startedAt': 1700000000000,
        'durationMs': 0,
        'result': 'not-connected',
        'hangupBy': 'remote',
      });

      // No dice "falló": el módem no distingue un rechazo de la red de una
      // llamada no atendida, y la app no inventa la diferencia.
      expect(c.resultLabel, 'No contestaron');
    });

    test('rechazada y fallida con causa', () {
      expect(
        PhoneCall.fromJson({
          'direction': 'in',
          'number': '1',
          'startedAt': 0,
          'durationMs': 0,
          'result': 'rejected',
        }).resultLabel,
        'Rechazada',
      );
      expect(
        PhoneCall.fromJson({
          'direction': 'out',
          'number': '1',
          'startedAt': 0,
          'durationMs': 0,
          'result': 'failed',
          'cause': 'no network service',
        }).resultLabel,
        'Falló (no network service)',
      );
    });

    test('un payload incompleto NO rompe (result desconocido → failed)', () {
      final c = PhoneCall.fromJson({'direction': 'out'});
      expect(c.number, '');
      expect(c.displayName, 'Número desconocido');
      expect(c.result, CallResult.failed);
      expect(c.duration, Duration.zero);
      expect(c.resultLabel, 'Falló');
    });

    test('una llamada sin caller ID se distingue de una que no está en la libreta', () {
      final anon = PhoneCall.fromJson(
          {'direction': 'in', 'number': '', 'startedAt': 0, 'durationMs': 0});
      final unknown = PhoneCall.fromJson(
          {'direction': 'in', 'number': '+5491199999999', 'startedAt': 0, 'durationMs': 0});
      expect(anon.displayName, 'Número desconocido');
      expect(unknown.displayName, '+5491199999999');
    });
  });

  group('PhoneStatus', () {
    test('parseo con señal anidada', () {
      final s = PhoneStatus.fromJson({
        'enabled': true,
        'online': true,
        'registered': true,
        'operator': 'AR PERSONAL Personal',
        'tech': 'WCDMA',
        'signal': {'rssi': 17, 'dbm': -79, 'bars': 4},
        'lineActive': 'unknown',
        'ownNumber': '+5492616260811',
      });

      expect(s.signalBars, 4);
      expect(s.operator, 'AR PERSONAL Personal');
      expect(s.ownNumber, '+5492616260811');
    });

    test('registrado NO se reporta como "activo": la línea puede no cursar', () {
      // El hallazgo que costó un diagnóstico entero: una línea sin habilitar
      // se registra igual y reporta operador y señal impecables.
      final s = PhoneStatus.fromJson({
        'enabled': true,
        'online': true,
        'registered': true,
        'operator': 'AR PERSONAL Personal',
        'lineActive': 'unknown',
      });
      expect(s.lineLabel, 'AR PERSONAL Personal');
      expect(s.lineLabel, isNot(contains('activa')));
    });

    test('línea inactiva lo dice explícitamente', () {
      final s = PhoneStatus.fromJson({
        'enabled': true,
        'online': true,
        'registered': true,
        'operator': 'AR PERSONAL Personal',
        'lineActive': 'inactive',
      });
      expect(s.lineLabel, 'Línea inactiva');
    });

    test('sin módem y deshabilitado', () {
      expect(
        PhoneStatus.fromJson({'enabled': true, 'online': false}).lineLabel,
        'Módem no disponible',
      );
      expect(PhoneStatus.fromJson({}).lineLabel, 'Deshabilitado');
      expect(
        PhoneStatus.fromJson({'enabled': true, 'online': true, 'registered': false})
            .lineLabel,
        'Sin red',
      );
    });
  });
}
