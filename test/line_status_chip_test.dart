// EugeValeiras/CCE#81 — la última llamada como ESTADO del teléfono: lo que
// `dev_phone` publica en `lastCallResult` / `lastCallDirection` / `lastCallAt`
// se lee bajo el chip de la línea, y hasta la primera llamada no se muestra.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/views/telephony/line_status_chip.dart';

void main() {
  final now = DateTime(2026, 9, 2, 15, 0);
  final threeMinAgo =
      now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch;

  group('lastCallSummary', () {
    test('sin resultado no hay nada que decir', () {
      expect(lastCallSummary(result: null, direction: 'out', at: 1), isNull);
      expect(lastCallSummary(result: '', direction: 'out', at: 1), isNull);
    });

    test('saliente contestada, hace 3 min', () {
      expect(
        lastCallSummary(
          result: 'answered',
          direction: 'out',
          at: threeMinAgo,
          now: now,
        ),
        'Última llamada: saliente, contestaron · hace 3 min',
      );
    });

    test('las mismas palabras que el historial, por resultado', () {
      String of(String result, String direction) => lastCallSummary(
            result: result,
            direction: direction,
            at: null,
          )!;
      expect(of('answered', 'in'), 'Última llamada: entrante, atendida');
      expect(of('missed', 'in'), 'Última llamada: entrante, perdida');
      expect(of('rejected', 'in'), 'Última llamada: entrante, rechazada');
      expect(
        of('not-connected', 'out'),
        'Última llamada: saliente, no contestaron',
      );
      expect(of('failed', 'out'), 'Última llamada: saliente, falló');
    });
  });

  group('DeviceState y PhoneStatus', () {
    test('leen lastCall* del JSON y no inventan nada si falta', () {
      final s = DeviceState.fromJson({
        'on': false,
        'lastCallResult': 'not-connected',
        'lastCallDirection': 'out',
        'lastCallAt': threeMinAgo,
      });
      expect(s.lastCallResult, 'not-connected');
      expect(s.lastCallDirection, 'out');
      expect(s.lastCallAt, threeMinAgo);
      final empty = DeviceState.fromJson({'on': false});
      expect(empty.lastCallResult, isNull);
      expect(empty.lastCallAt, isNull);

      final status = PhoneStatus.fromJson({
        'enabled': true,
        'online': true,
        'call': {'state': 'idle'},
        'lastCall': {
          'direction': 'in',
          'number': '+54911',
          'startedAt': threeMinAgo,
          'durationMs': 0,
          'result': 'missed',
        },
      });
      expect(status.lastCallResult, 'missed');
      expect(status.lastCallDirection, 'in');
      expect(status.lastCallAt, threeMinAgo);
      expect(PhoneStatus.fromJson({'lastCall': null}).lastCallResult, isNull);
    });
  });

  testWidgets('el chip muestra la última llamada, y el estado en vivo manda',
      (tester) async {
    Future<void> pump(DeviceState state, PhoneStatus status) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LineStatusChip(status: status, state: state),
        ),
      ));
      await tester.pump();
    }

    // Sin ninguna llamada cerrada: ni una línea de más.
    await pump(
      DeviceState.fromJson({'on': false}),
      const PhoneStatus(enabled: true, online: true),
    );
    expect(find.textContaining('Última llamada'), findsNothing);

    // El seed de /status trae una; el socket todavía no dijo nada.
    await pump(
      DeviceState.fromJson({'on': false}),
      PhoneStatus(
        enabled: true,
        online: true,
        lastCallResult: 'missed',
        lastCallDirection: 'in',
        lastCallAt: threeMinAgo,
      ),
    );
    expect(find.textContaining('entrante, perdida'), findsOneWidget);

    // Llega el estado en vivo con otra llamada: gana.
    await pump(
      DeviceState.fromJson({
        'on': false,
        'lastCallResult': 'answered',
        'lastCallDirection': 'out',
        'lastCallAt': threeMinAgo,
      }),
      PhoneStatus(
        enabled: true,
        online: true,
        lastCallResult: 'missed',
        lastCallDirection: 'in',
        lastCallAt: threeMinAgo,
      ),
    );
    expect(find.textContaining('saliente, contestaron'), findsOneWidget);
    expect(find.textContaining('perdida'), findsNothing);
  });
}
