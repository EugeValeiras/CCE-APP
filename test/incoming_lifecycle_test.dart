// CCE#21: la card de la entrante se retira por CUALQUIERA de las vías por las
// que la app se entera de que dejó de sonar — no por una sola.
//
// Lo que pasó en el teléfono real: entró una llamada, el que llamaba cortó
// antes de que atendieran, y la card quedó pegada con Rechazar/Atender. El
// backend había avisado DOS veces (copiado del event store, 26/08/2026):
//
//   phone:call-state      { event:'ended', direction:'in', result:'missed',
//                           hangupBy:'remote' }
//   device:state-changed  { callState:'ended' }  →  { on:false, callState:'idle' }
//
// y `_incoming` colgaba del primero nada más. Acá cada vía se prueba POR
// SEPARADO —el punto del arreglo es que cualquiera alcance—, en los dos
// órdenes, y que la perdida entre al historial y al contador una sola vez.
//
// La tercera vía es `refresh()` tras reconectar el socket. El test empuja la
// secuencia REAL del socket (`true` → `false` → `true`): con ella, el listener
// que había no refrescaba nunca.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/phone_audio_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/telephony_service.dart';
import 'package:cce_app/views/telephony/dial_display.dart';
import 'package:cce_app/views/telephony_screen.dart';

// ── Lo que emitió el backend, tal cual ───────────────────────────────────────

/// `phone:call-state` del primer RING, con caller ID…
const _incomingCami = <String, dynamic>{
  'event': 'incoming',
  'number': '+542616110154',
  'contactId': 'cmt96lp8k',
  'direction': 'in',
  'contactName': 'Cami',
  'timestamp': 1787776653610,
};

/// …y SIN caller ID, como llegan 3 de cada 4 en el event store: el número
/// viene después, en un delta del device.
const _incomingBlank = <String, dynamic>{
  'event': 'incoming',
  'number': '',
  'direction': 'in',
  'timestamp': 1787776816480,
};

/// `phone:call-state` de fin: cortaron antes de que atendieran.
const _endedMissed = <String, dynamic>{
  'event': 'ended',
  'number': '+542616110154',
  'result': 'missed',
  'hangupBy': 'remote',
  'contactId': 'cmt96lp8k',
  'direction': 'in',
  'startedAt': 1787776653609,
  'timestamp': 1787776691749,
  'durationMs': 0,
  'contactName': 'Cami',
};

/// `device:state-changed` de dev_phone, en el orden en que salieron.
const _ringingIn = <String, dynamic>{
  'on': true,
  'callState': 'ringing',
  'callDirection': 'in',
  'callStartedAt': 1787776816479,
};
const _peerNumber = <String, dynamic>{'peerNumber': '+542616110154'};
const _active = <String, dynamic>{'callState': 'active'};
const _ended = <String, dynamic>{'callState': 'ended'};
const _idle = <String, dynamic>{'on': false, 'callState': 'idle'};

// ── Dobles ───────────────────────────────────────────────────────────────────

/// Socket sin red: los tres canales que el servicio escucha se empujan a mano.
class _FakeSocket extends SocketService {
  final _devices = StreamController<DeviceStateEvent>.broadcast();
  final _calls = StreamController<PhoneCallStateEvent>.broadcast();
  final _conn = StreamController<bool>.broadcast();

  @override
  Stream<DeviceStateEvent> get onDeviceChanged => _devices.stream;
  @override
  Stream<PhoneCallStateEvent> get onCallState => _calls.stream;
  @override
  Stream<bool> get onConnectionChanged => _conn.stream;

  void device(Map<String, dynamic> state) =>
      _devices.add(DeviceStateEvent(deviceId: kPhoneDeviceId, state: state));

  void call(Map<String, dynamic> payload) => _calls.add(
        PhoneCallStateEvent(event: payload['event'] as String, payload: payload),
      );

  void connected(bool value) => _conn.add(value);
}

/// `/phone/*` sin red. [status] es lo que contesta `/phone/status`; [gate]
/// retiene la respuesta para meter un evento del socket mientras el GET viaja.
class _FakeApi extends ApiService {
  _FakeApi(super.config);

  PhoneStatus status = _status();
  Completer<void>? gate;
  int statusReads = 0;

  @override
  Future<PhoneStatus> getPhoneStatus() async {
    statusReads++;
    if (gate case final g?) await g.future;
    return status;
  }

  @override
  Future<List<PhoneCall>> getPhoneCalls({int limit = 50}) async => const [];

  @override
  Future<List<PhoneContact>> getPhoneContacts() async => const [];
}

/// Audio de mentira: sólo el estado que la pantalla lee.
class _FakeAudio extends PhoneAudioService {
  _FakeAudio({required super.config});

  @override
  PhoneAudioState get state => PhoneAudioState.off;
  @override
  bool get isOn => false;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  Future<bool> take() async => false;
  @override
  Future<void> release() async {}
}

/// El servicio REAL —el ciclo de vida de `_incoming` es lo que se prueba— con
/// la red y el audio de mentira.
class _Telephony extends TelephonyService {
  _Telephony({required super.config, required super.socket, required super.api})
      : _audio = _FakeAudio(config: config);

  final _FakeAudio _audio;

  @override
  _FakeAudio get audio => _audio;
}

/// El snapshot de `/phone/status`, recortado a la llamada.
PhoneStatus _status({
  String state = 'idle',
  String? direction,
  String? number,
  String? name,
}) =>
    PhoneStatus.fromJson({
      'enabled': true,
      'online': true,
      'registered': true,
      'call': {
        'state': state,
        'direction': ?direction,
        'peerNumber': ?number,
        'contactName': ?name,
        'elapsedMs': 0,
      },
      'audioRoute': 'speaker',
    });

class _Rig {
  _Rig()
      : config = ServerConfig(host: '127.0.0.1', port: 1),
        socket = _FakeSocket() {
    api = _FakeApi(config);
    telephony = _Telephony(config: config, socket: socket, api: api);
  }

  final ServerConfig config;
  final _FakeSocket socket;
  late final _FakeApi api;
  late final _Telephony telephony;

  /// Arranca como el shell y deja correr el seed: si no, la reconexión de
  /// abajo encontraría el `refresh()` del seed en vuelo y se saltearía.
  Future<void> start() async {
    telephony.start();
    await pumpEventQueue();
  }

  /// Una entrante sonando por las dos vías, como en la vida real.
  Future<void> ring([Map<String, dynamic> incoming = _incomingCami]) async {
    socket.call(incoming);
    socket.device(_ringingIn);
    await pumpEventQueue();
  }

  /// La reconexión tal como la ve el servicio: conectó, se cayó, volvió.
  Future<void> reconnect() async {
    socket.connected(true);
    socket.connected(false);
    socket.connected(true);
    await pumpEventQueue();
  }
}

void main() {
  group('la entrante se retira por cada vía, por separado', () {
    test('por el phone:call-state de fin', () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();
      expect(rig.telephony.incoming, isNotNull);
      expect(rig.telephony.incoming!['contactName'], 'Cami');

      rig.socket.call(_endedMissed);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      // La perdida entra al historial y al contador en el acto.
      expect(rig.telephony.calls, hasLength(1));
      expect(rig.telephony.calls.first.isMissed, isTrue);
      expect(rig.telephony.unseenMissed, 1);
      rig.telephony.stop();
    });

    test('por el device: `ended`', () async {
      // La vía que hasta CCE#21 el listener ignoraba a propósito.
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.socket.device(_ended);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      // Sin `phone:call-state` de fin todavía: no hay historial que inventar.
      expect(rig.telephony.calls, isEmpty);
      expect(rig.telephony.unseenMissed, 0);
      rig.telephony.stop();
    });

    test('por el device: `idle` solo, si el `ended` también se perdió',
        () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.socket.device(_idle);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      rig.telephony.stop();
    });

    test('por refresh() tras reconectar, si la llamada terminó mientras tanto',
        () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();
      final reads = rig.api.statusReads;

      // Se cayó el socket, la llamada terminó (nadie se enteró) y volvió.
      rig.api.status = _status(state: 'idle');
      await rig.reconnect();
      expect(rig.api.statusReads, reads + 1,
          reason: 'la reconexión tiene que re-leer /phone/status');
      expect(rig.telephony.incoming, isNull);
      rig.telephony.stop();
    });

    test('por refresh() aunque el snapshot diga `ended` y no `idle`', () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.api.status = _status(state: 'ended', direction: 'in');
      await rig.reconnect();
      expect(rig.telephony.incoming, isNull);
      rig.telephony.stop();
    });
  });

  group('las vías no se pisan', () {
    test('device primero, phone:call-state después: la perdida entra una vez',
        () async {
      // El orden del event store: `ended` e `idle` del device pueden llegar
      // antes que el `phone:call-state`. La card cae con el primero y el
      // historial/contador con el segundo — ni se duplica ni se pierde.
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.socket.device(_ended);
      rig.socket.device(_idle);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);

      rig.socket.call(_endedMissed);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      expect(rig.telephony.calls, hasLength(1));
      expect(rig.telephony.unseenMissed, 1);
      rig.telephony.stop();
    });

    test('phone:call-state primero, device después: ídem', () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.socket.call(_endedMissed);
      rig.socket.device(_ended);
      rig.socket.device(_idle);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      expect(rig.telephony.calls, hasLength(1));
      expect(rig.telephony.unseenMissed, 1);

      // Y un refresh() encima tampoco rompe nada.
      rig.api.status = _status(state: 'idle');
      await rig.reconnect();
      expect(rig.telephony.incoming, isNull);
      expect(rig.telephony.unseenMissed, 1);
      rig.telephony.stop();
    });

    test('las tres vías seguidas notifican sin tirar', () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();
      var notifies = 0;
      rig.telephony.addListener(() => notifies++);

      rig.socket.device(_ended);
      rig.socket.device(_idle);
      rig.socket.call(_endedMissed);
      await pumpEventQueue();
      await rig.reconnect();
      expect(rig.telephony.incoming, isNull);
      expect(notifies, greaterThan(0));
      rig.telephony.stop();
    });
  });

  group('no rompe la entrante legítima', () {
    test('mientras el device diga `ringing`, la card se queda', () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring(_incomingBlank);
      final before = rig.telephony.incoming;
      expect(before, isNotNull);

      // El caller ID llega después, en un delta sin callState.
      rig.socket.device(_peerNumber);
      // Y un `ringing` repetido tampoco la mueve.
      rig.socket.device(_ringingIn);
      await pumpEventQueue();
      expect(rig.telephony.incoming, same(before));
      rig.telephony.stop();
    });

    test('refresh() con la entrante sonando en /status la deja como está',
        () async {
      final rig = _Rig();
      await rig.start();
      await rig.ring();
      final before = rig.telephony.incoming;

      rig.api.status =
          _status(state: 'ringing', direction: 'in', number: '+542616110154');
      await rig.reconnect();
      expect(rig.telephony.incoming, same(before));
      rig.telephony.stop();
    });

    test('refresh() ARMA la entrante si /status dice que suena y el aviso se perdió',
        () async {
      // Al volver de background con la llamada todavía sonando: el
      // `phone:call-state` de `incoming` se fue con el socket caído, pero el
      // snapshot lo sabe. La card tiene que estar, con quién.
      final rig = _Rig();
      await rig.start();
      expect(rig.telephony.incoming, isNull);

      rig.api.status = _status(
        state: 'ringing',
        direction: 'in',
        number: '+542616110154',
        name: 'Cami',
      );
      await rig.reconnect();
      final incoming = rig.telephony.incoming;
      expect(incoming, isNotNull);
      expect(incoming!['number'], '+542616110154');
      expect(incoming['contactName'], 'Cami');
      expect(incoming['direction'], 'in');
      rig.telephony.stop();
    });

    test('un `ringing` saliente en /status no inventa una entrante', () async {
      final rig = _Rig();
      await rig.start();

      rig.api.status = _status(state: 'ringing', direction: 'out');
      await rig.reconnect();
      expect(rig.telephony.incoming, isNull);
      rig.telephony.stop();
    });

    test('una entrante que llega mientras el GET viaja no se pisa con el snapshot',
        () async {
      // refresh() arranca con la línea libre; antes de que conteste, entra una
      // llamada por el socket. La respuesta (vieja) dice `idle`: no manda.
      final rig = _Rig();
      await rig.start();
      rig.api.gate = Completer<void>();
      rig.api.status = _status(state: 'idle');

      socketReconnect() async {
        rig.socket.connected(true);
        rig.socket.connected(false);
        rig.socket.connected(true);
        await pumpEventQueue();
      }

      await socketReconnect();
      expect(rig.telephony.loading, isTrue, reason: 'el GET tiene que estar en vuelo');
      await rig.ring();
      final live = rig.telephony.incoming;
      expect(live, isNotNull);

      rig.api.gate!.complete();
      await pumpEventQueue();
      expect(rig.telephony.loading, isFalse);
      expect(rig.telephony.incoming, same(live));
      rig.telephony.stop();
    });

    test('atendida desde otro lado (`active`) deja de ser entrante', () async {
      // La misma regla, del otro lado: la card de la entrante vive mientras
      // SUENA. Si la atienden desde el dashboard o el HAT, el device pasa a
      // `active` y lo que corresponde es la card de la llamada en curso, no
      // Atender/Rechazar sobre una llamada ya atendida.
      final rig = _Rig();
      await rig.start();
      await rig.ring();

      rig.socket.device(_active);
      await pumpEventQueue();
      expect(rig.telephony.incoming, isNull);
      rig.telephony.stop();
    });
  });

  group('la pantalla', () {
    /// DevicesService REAL sembrado con el teléfono en reposo, el servicio de
    /// telefonía REAL, y el socket falso alimentando a los dos: es el camino de
    /// producción menos la red.
    late _Rig rig;
    late DevicesService devices;

    Widget screen() => MaterialApp(
          home: TelephonyScreen(
            device: devices.byId(kPhoneDeviceId)!,
            service: devices,
            telephony: rig.telephony,
          ),
        );

    setUp(() {
      rig = _Rig();
      devices = DevicesService(config: rig.config, socket: rig.socket)
        ..debugSeedDevices([
          Device(
            id: kPhoneDeviceId,
            name: 'Teléfono',
            type: 'phone',
            capabilities: const ['phone'],
            state: DeviceState(
              callState: 'idle',
              lineActive: 'active',
              signalBars: 3,
              networkTech: 'WCDMA',
              networkOperator: 'Personal',
            ),
          ),
        ]);
    });

    /// El evento viaja por un stream asíncrono: un `pump` lo entrega y otro
    /// pinta. La card de la entrante tiene un pulso infinito, así que nada de
    /// `pumpAndSettle`. (Y nada de `pumpEventQueue` acá: con el reloj falso de
    /// `testWidgets` un `Future.delayed(0)` no dispara solo y el test cuelga.)
    Future<void> deliver(WidgetTester t) async {
      await t.pump();
      await t.pump();
    }

    testWidgets('la card se monta con la entrante y se desmonta sola al cortar',
        (t) async {
      rig.telephony.start();
      await t.pumpWidget(screen());
      await deliver(t);
      expect(find.byTooltip('Llamar'), findsOneWidget);
      expect(find.byTooltip('Atender'), findsNothing);

      // Suena.
      rig.socket.call(_incomingCami);
      rig.socket.device(_ringingIn);
      await deliver(t);
      expect(find.text('Cami'), findsOneWidget);
      expect(find.byTooltip('Atender'), findsOneWidget);
      expect(find.byTooltip('Rechazar'), findsOneWidget);
      expect(find.byType(DialDisplay), findsNothing);

      // Cortaron antes de atender: SÓLO el device se entera (el
      // `phone:call-state` se perdió). La card tiene que irse igual.
      rig.socket.device(_ended);
      rig.socket.device(_idle);
      await deliver(t);
      expect(find.byTooltip('Atender'), findsNothing);
      expect(find.byTooltip('Rechazar'), findsNothing);
      expect(find.byTooltip('Llamar'), findsOneWidget);
      expect(find.byType(DialDisplay), findsOneWidget);

      // Y cuando el `phone:call-state` llega tarde, el historial suma sin
      // volver a montar nada.
      rig.socket.call(_endedMissed);
      await deliver(t);
      expect(find.byTooltip('Atender'), findsNothing);
      expect(find.text('1'), findsWidgets, reason: 'el badge de perdidas y la tecla 1');
      expect(rig.telephony.unseenMissed, 1);

      await t.pumpWidget(const SizedBox());
      rig.telephony.stop();
    });

    testWidgets('con el aviso sin número, la card muestra el número del device',
        (t) async {
      // 3 de cada 4 entrantes: `{event:'incoming', number:''}` y después el
      // device manda `{peerNumber}`. Un '' no le puede ganar al dato.
      rig.telephony.start();
      await t.pumpWidget(screen());
      await deliver(t);

      rig.socket.call(_incomingBlank);
      rig.socket.device(_ringingIn);
      await deliver(t);
      expect(find.byTooltip('Atender'), findsOneWidget);
      expect(find.text('Número desconocido'), findsOneWidget,
          reason: 'todavía no hay caller ID: se dice');

      rig.socket.device(_peerNumber);
      await deliver(t);
      expect(find.text('+542616110154'), findsOneWidget);
      expect(find.text('Número desconocido'), findsNothing);
      expect(find.byTooltip('Atender'), findsOneWidget);

      // Y se va como cualquier otra.
      rig.socket.device(_ended);
      await deliver(t);
      expect(find.byTooltip('Atender'), findsNothing);
      expect(find.byTooltip('Llamar'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      rig.telephony.stop();
    });
  });
}
