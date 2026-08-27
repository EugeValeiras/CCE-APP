// CCE#23: el canal de APNs vive en un lugar que está siempre montado.
//
// Antes el handler lo ponía AlarmView al montarse, y en el teléfono esa
// pantalla se abre a demanda: tocar una push no le llegaba a nadie. Acá se
// fija que el token y los toques llegan a quien escuche, y que un toque sin
// nadie escuchando (arranque en frío) espera al primero que lo pida.

import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/services/push_channel.dart';

void main() {
  final push = PushChannel.instance;

  test('el token se reparte y queda guardado para el que llega tarde', () async {
    final seen = <String>[];
    final sub = push.onToken.listen(seen.add);

    await push.debugDeliver('onToken', 'abcdef0123456789abcdef');
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['abcdef0123456789abcdef']);
    expect(push.lastToken, 'abcdef0123456789abcdef');
    await sub.cancel();
  });

  test('un toque con alguien escuchando llega por el stream, no queda pendiente',
      () async {
    final taps = <Map<String, dynamic>>[];
    final sub = push.onPushTapped.listen(taps.add);

    await push.debugDeliver('onPushTapped', {
      'title': 'SMS de Cami',
      'body': 'Tu código es 482913',
      'kind': 'phone-sms',
      'smsId': 'sms-1',
    });
    await Future<void>.delayed(Duration.zero);

    expect(taps, hasLength(1));
    expect(taps.first['kind'], 'phone-sms');
    expect(taps.first['smsId'], 'sms-1');
    expect(push.takePendingTap(), isNull);
    await sub.cancel();
  });

  test('un toque SIN nadie escuchando se guarda y se entrega una sola vez', () async {
    await push.debugDeliver('onPushTapped', {'kind': 'phone-sms', 'smsId': 'x'});

    final pending = push.takePendingTap();
    expect(pending?['smsId'], 'x');
    expect(push.takePendingTap(), isNull);
  });

  test('una push en primer plano llega con sus claves extra', () async {
    final received = <Map<String, dynamic>>[];
    final sub = push.onPushReceived.listen(received.add);

    await push.debugDeliver('onPushReceived', {
      'title': 'SMS de Personal',
      'body': 'Tu credito es \$9000',
      'kind': 'phone-sms',
    });
    await Future<void>.delayed(Duration.zero);

    expect(received.single['kind'], 'phone-sms');
    await sub.cancel();
  });

  test('un método desconocido o un payload raro no tiran', () async {
    await push.debugDeliver('onWhatever', 42);
    await push.debugDeliver('onPushTapped', 'no es un mapa');
    final pending = push.takePendingTap();
    expect(pending, isNotNull);
    expect(pending, isEmpty);
  });
}
