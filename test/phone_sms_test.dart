// CCE#23: los SMS de la línea de la casa en la app.
//
// Lo que protege: (1) el modelo lee el contrato de `GET /phone/sms` /
// `phone:sms` sin perder tildes ni ñ —el backend ya los manda bien y acá no
// se los puede romper—, (2) el servicio suma al historial y al contador de
// no leídos por el socket, sin duplicar lo que después vuelve por el GET,
// y (3) en el historial de la casa un SMS se lee como "SMS de <quién>".
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/models/phone_sms.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/telephony_service.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/history/phone_events.dart';

/// Lo que emite el backend en `phone:sms`, con el texto YA decodificado del
/// PDU (UCS2): tildes y ñ intactas.
const _codigo = <String, dynamic>{
  'event': 'received',
  'id': '9c1f0a2e-1111-4a5b-9c0d-000000000001',
  'number': '+5492616260811',
  'contactId': 'cami',
  'contactName': 'Cami',
  'text': 'Tu código de verificación es 482913. Válido por 10 min. ñÑáéíóú',
  'sentAt': 1787787180000,
  'receivedAt': 1787787185000,
  'parts': 1,
  'timestamp': 1787787185000,
};

/// De la operadora: remitente alfanumérico, sin contacto.
const _personal = <String, dynamic>{
  'event': 'received',
  'id': '9c1f0a2e-1111-4a5b-9c0d-000000000002',
  'number': 'Personal',
  'text': 'Tu credito es \$9000',
  'sentAt': 1787745907000,
  'receivedAt': 1787745910000,
  'parts': 1,
};

class _FakeSocket extends SocketService {
  final _sms = StreamController<PhoneSmsEvent>.broadcast();
  final _conn = StreamController<bool>.broadcast();

  @override
  Stream<PhoneSmsEvent> get onSms => _sms.stream;
  @override
  Stream<bool> get onConnectionChanged => _conn.stream;
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
  bool smsFails = false;

  @override
  Future<PhoneStatus> getPhoneStatus() async => const PhoneStatus();
  @override
  Future<List<PhoneCall>> getPhoneCalls({int limit = 50}) async => const [];
  @override
  Future<List<PhoneContact>> getPhoneContacts() async => const [];
  @override
  Future<List<PhoneSms>> getPhoneSms({int limit = 50}) async {
    if (smsFails) throw Exception('sin endpoint');
    return seed;
  }
}

void main() {
  group('PhoneSms.fromJson', () {
    test('el texto llega con todas las tildes y la ñ', () {
      final s = PhoneSms.fromJson(_codigo);
      expect(s.text, 'Tu código de verificación es 482913. Válido por 10 min. ñÑáéíóú');
      expect(s.displayName, 'Cami');
      expect(s.number, '+5492616260811');
      expect(s.hasDialableNumber, isTrue);
      expect(s.parts, 1);
      // La fecha que se muestra es la de la red, no la de la Pi.
      expect(s.when, DateTime.fromMillisecondsSinceEpoch(1787787180000));
    });

    test('un remitente alfanumérico se muestra como nombre y no se disca', () {
      final s = PhoneSms.fromJson(_personal);
      expect(s.displayName, 'Personal');
      expect(s.hasDialableNumber, isFalse);
    });

    test('sin sentAt cae a receivedAt; sin remitente lo dice', () {
      final s = PhoneSms.fromJson({
        'id': 'x',
        'number': '',
        'text': 'hola',
        'sentAt': null,
        'receivedAt': 1787787185000,
      });
      expect(s.sentAt, isNull);
      expect(s.when, DateTime.fromMillisecondsSinceEpoch(1787787185000));
      expect(s.displayName, 'Remitente desconocido');
    });
  });

  group('TelephonyService · SMS', () {
    late _FakeSocket socket;
    late _FakeApi api;
    late TelephonyService svc;

    setUp(() {
      socket = _FakeSocket();
      api = _FakeApi(ServerConfig());
      svc = TelephonyService(config: ServerConfig(), socket: socket, api: api);
    });

    tearDown(() => svc.dispose());

    test('un SMS por el socket entra al historial y suma al contador', () async {
      svc.start();
      await Future<void>.delayed(Duration.zero);

      socket.sms(_codigo);
      await Future<void>.delayed(Duration.zero);

      expect(svc.sms, hasLength(1));
      expect(svc.sms.first.text, contains('código de verificación'));
      expect(svc.unseenSms, 1);
      expect(svc.unseenTotal, 1);

      svc.markSmsSeen();
      expect(svc.unseenSms, 0);
    });

    test('el mismo id dos veces (socket + GET tras reconectar) es UN mensaje', () async {
      svc.start();
      await Future<void>.delayed(Duration.zero);

      socket.sms(_codigo);
      socket.sms(_codigo);
      await Future<void>.delayed(Duration.zero);
      expect(svc.sms, hasLength(1));
      expect(svc.unseenSms, 1);

      // El GET vuelve con el mismo mensaje y uno más viejo.
      api.seed = [PhoneSms.fromJson(_codigo), PhoneSms.fromJson(_personal)];
      await svc.refresh();
      expect(svc.sms.map((s) => s.id).toList(), [
        _codigo['id'],
        _personal['id'],
      ]);
      // Lo que ya se contó no se vuelve a contar.
      expect(svc.unseenSms, 1);
    });

    test('lo que entró por el socket mientras el GET viajaba queda adelante', () async {
      api.seed = [PhoneSms.fromJson(_personal)];
      svc.start();
      socket.sms(_codigo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(svc.sms.map((s) => s.displayName).toList(), ['Cami', 'Personal']);
    });

    test('un GET /phone/sms que falla no tumba el teléfono', () async {
      api.smsFails = true;
      svc.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(svc.error, isNull);
      expect(svc.sms, isEmpty);
    });
  });

  group('historial de la casa', () {
    final devices =
        DevicesService(config: ServerConfig(), socket: SocketService());

    EventRecord ev(Map<String, dynamic> payload) => EventRecord(
          time: '2026-08-26T23:33:05.000Z',
          id: 'e1',
          channel: 'websocket',
          eventName: kSmsEvent,
          payload: payload,
        );

    test('phone:sms es un evento del teléfono y se lee con el modelo de SMS', () {
      final e = ev(_codigo);
      expect(isPhoneEvent(e), isTrue);
      expect(isCallLogNoise(e), isFalse);
      expect(smsFromEvent(e)?.displayName, 'Cami');
      expect(callFromEvent(e), isNull);
    });

    test('se presenta como "SMS de <quién>" con el texto', () {
      final r = presentEvent(ev(_codigo), devices);
      expect(r.title, 'SMS de Cami');
      expect(r.subtitle, contains('código de verificación'));
      expect(r.color, CceColors.accent);
    });

    test('de la operadora: el nombre alfanumérico', () {
      final r = presentEvent(ev(_personal), devices);
      expect(r.title, 'SMS de Personal');
    });
  });
}
