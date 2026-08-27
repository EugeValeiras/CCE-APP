// CCE#23: la pantalla de mensajes del teléfono.
//
// Lo que se fija: entrar ES ver los mensajes (el contador se pone en cero al
// montar), cada fila muestra quién y el texto con sus acentos, un mensaje
// nuevo por el socket aparece sin recargar, y el que abrió la push queda
// resaltado.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/models/phone_sms.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/telephony_service.dart';
import 'package:cce_app/theme/cce_theme.dart';
import 'package:cce_app/theme/components/cce_card.dart';
import 'package:cce_app/views/telephony/sms_screen.dart';

const _codigo = <String, dynamic>{
  'event': 'received',
  'id': 'sms-1',
  'number': '+5492616260811',
  'contactId': 'cami',
  'contactName': 'Cami',
  'text': 'Tu código de verificación es 482913. Válido por 10 min.',
  'sentAt': 1787787180000,
  'receivedAt': 1787787185000,
  'parts': 1,
};

const _personal = <String, dynamic>{
  'event': 'received',
  'id': 'sms-2',
  'number': 'Personal',
  'text': 'Mañana vence tu pack. ¡Recargá!',
  'sentAt': 1787745907000,
  'receivedAt': 1787745910000,
  'parts': 2,
};

class _FakeSocket extends SocketService {
  final _sms = StreamController<PhoneSmsEvent>.broadcast();

  @override
  Stream<PhoneSmsEvent> get onSms => _sms.stream;
  @override
  Stream<bool> get onConnectionChanged => const Stream.empty();
  @override
  Stream<DeviceStateEvent> get onDeviceChanged => const Stream.empty();
  @override
  Stream<PhoneCallStateEvent> get onCallState => const Stream.empty();

  void sms(Map<String, dynamic> payload) =>
      _sms.add(PhoneSmsEvent(payload: payload));
}

class _FakeApi extends ApiService {
  _FakeApi(super.config);
  List<PhoneSms> seed = const [];

  @override
  Future<PhoneStatus> getPhoneStatus() async => const PhoneStatus();
  @override
  Future<List<PhoneCall>> getPhoneCalls({int limit = 50}) async => const [];
  @override
  Future<List<PhoneContact>> getPhoneContacts() async => const [];
  @override
  Future<List<PhoneSms>> getPhoneSms({int limit = 50}) async => seed;
}

Widget _app(Widget home) => MaterialApp(theme: CceTheme.dark(), home: home);

void main() {
  late _FakeSocket socket;
  late _FakeApi api;
  late TelephonyService svc;

  setUp(() {
    socket = _FakeSocket();
    api = _FakeApi(ServerConfig());
    svc = TelephonyService(config: ServerConfig(), socket: socket, api: api);
  });

  tearDown(() => svc.dispose());

  testWidgets('lista quién y el texto, con acentos; entrar pone el contador en cero',
      (tester) async {
    api.seed = [PhoneSms.fromJson(_personal)];
    svc.start();
    await tester.pump();
    socket.sms(_codigo);
    await tester.pump();
    expect(svc.unseenSms, 1);
    socket.sms(_codigo); // repetido: no se duplica ni se vuelve a contar
    await tester.pump();
    expect(svc.unseenSms, 1);
    expect(svc.sms, hasLength(2));

    await tester.pumpWidget(_app(SmsScreen(telephony: svc)));
    await tester.pump();

    expect(svc.unseenSms, 0);
    expect(find.text('Mensajes'), findsOneWidget);
    expect(find.text('2 mensajes'), findsOneWidget);
    expect(find.text('Cami'), findsOneWidget);
    expect(find.text('+5492616260811'), findsOneWidget);
    expect(
      find.text('Tu código de verificación es 482913. Válido por 10 min.'),
      findsOneWidget,
    );
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Mañana vence tu pack. ¡Recargá!'), findsOneWidget);
  });

  testWidgets('vacío: lo dice, no muestra una lista en blanco', (tester) async {
    svc.start();
    await tester.pumpWidget(_app(SmsScreen(telephony: svc)));
    await tester.pump();

    expect(find.text('Todavía no hay mensajes.'), findsOneWidget);
    expect(find.text('Sin mensajes'), findsOneWidget);
  });

  testWidgets('un SMS que llega con la pantalla abierta aparece sin recargar',
      (tester) async {
    svc.start();
    await tester.pumpWidget(_app(SmsScreen(telephony: svc)));
    await tester.pump();
    expect(find.text('Cami'), findsNothing);

    socket.sms(_codigo);
    // Un pump entrega el evento del socket; el siguiente pinta el rebuild.
    await tester.pump();
    await tester.pump();

    expect(find.text('Cami'), findsOneWidget);
    expect(find.text('1 mensaje'), findsOneWidget);
  });

  testWidgets('el mensaje que abrió la push queda resaltado', (tester) async {
    api.seed = [PhoneSms.fromJson(_codigo), PhoneSms.fromJson(_personal)];
    svc.start();
    await tester.pump();

    await tester.pumpWidget(_app(SmsScreen(telephony: svc, focusId: 'sms-2')));
    await tester.pump();

    // Sólo la fila de Personal lleva el borde de acento (la superficie
    // teñida); la de Cami sigue neutra.
    final cards = tester.widgetList<CceCard>(find.byType(CceCard)).toList();
    final tinted = cards.where((c) => c.borderColor != null).length;
    expect(cards.length, 2);
    expect(tinted, 1);
  });
}
