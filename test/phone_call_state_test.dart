// CCE#19: la pantalla tiene que reflejar la llamada REAL mientras dure.
//
// El backend emite `device:state-changed` para dev_phone con DELTAS —sólo lo
// que cambió—: `{callState:'dialing', peerName, …}`, después
// `{callState:'active'}`, `{callState:'ended'}`, `{on:false, callState:'idle'}`,
// y `{signalBars: 2}` en el medio. Los de abajo están copiados del event
// store de una llamada real (26/08/2026). Hasta este fix
// `DevicesService._applyDeviceEvent` re-armaba el estado sin el bloque phone y
// cualquiera de esos eventos dejaba callState en null: la pantalla volvía a
// reposo con la llamada viva en cuanto el placeholder de 30 s la soltaba.
//
// Por eso acá el device NO se monta ya "activo" (eso lo cubre
// telephony_screen_test): se siembra en reposo y el estado entra POR EL
// SOCKET, que es el camino que estaba cortado.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/phone_audio_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/telephony_service.dart';
import 'package:cce_app/views/telephony/dial_display.dart';
import 'package:cce_app/views/telephony_screen.dart';

// ── Lo que emitió el backend, tal cual ───────────────────────────────────────

const _dialing = <String, dynamic>{
  'on': true,
  'peerName': 'Euge',
  'callState': 'dialing',
  'peerNumber': '+5492364552179',
  'callDirection': 'out',
  'callStartedAt': 1787766330712,
};
const _active = <String, dynamic>{'callState': 'active'};
const _signal = <String, dynamic>{'signalBars': 2};
const _ended = <String, dynamic>{'callState': 'ended'};
const _idle = <String, dynamic>{'on': false, 'callState': 'idle'};

// ── Dobles ───────────────────────────────────────────────────────────────────

/// Socket sin red: los eventos de device se empujan a mano.
class _FakeSocket extends SocketService {
  final _events = StreamController<DeviceStateEvent>.broadcast();

  @override
  Stream<DeviceStateEvent> get onDeviceChanged => _events.stream;

  void push(Map<String, dynamic> state) =>
      _events.add(DeviceStateEvent(deviceId: kPhoneDeviceId, state: state));
}

class _FakeAudio extends PhoneAudioService {
  _FakeAudio({required super.config});

  bool on = false;

  @override
  PhoneAudioState get state => on ? PhoneAudioState.on : PhoneAudioState.off;
  @override
  bool get isOn => on;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  Future<bool> take() async {
    on = true;
    return true;
  }

  @override
  Future<void> release() async {}
}

/// Telefonía sin red y SIN placeholder: `dialingNumber` siempre null, como
/// después de los 30 s. Lo que la pantalla muestre sale del device.
class _FakeTelephony extends TelephonyService {
  _FakeTelephony({required super.config, required super.socket})
      : _audio = _FakeAudio(config: config);

  final _FakeAudio _audio;
  final PhoneStatus _status = PhoneStatus.fromJson({'audioRoute': 'speaker'});
  List<PhoneContact> fakeContacts = const [];

  /// Llamadas que llegaron a [call]: (number, contactId).
  final List<(String?, String?)> dialed = [];

  @override
  _FakeAudio get audio => _audio;
  @override
  PhoneStatus get status => _status;
  @override
  Map<String, dynamic>? get incoming => null;
  @override
  String? get dialingNumber => null;
  @override
  String? get actionError => null;
  @override
  bool get busy => false;
  @override
  List<PhoneContact> get contacts => fakeContacts;

  @override
  Future<void> refresh() async {}
  @override
  Future<void> loadContacts({bool force = false}) async {}
  @override
  Future<bool> call({String? number, String? contactId}) async {
    dialed.add((number, contactId));
    return true;
  }
}

/// Telefonía real salvo la red: para probar el placeholder y su expiración.
class _ExpiringTelephony extends TelephonyService {
  _ExpiringTelephony({
    required super.config,
    required super.socket,
    super.reloadPhoneDevice,
  });

  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

Device _phone({String callState = 'idle'}) => Device(
      id: kPhoneDeviceId,
      name: 'Teléfono',
      type: 'phone',
      capabilities: const ['phone'],
      state: DeviceState(
        callState: callState,
        lineActive: 'active',
        signalBars: 3,
        networkTech: 'WCDMA',
        networkOperator: 'Personal',
      ),
    );

ServerConfig _config() => ServerConfig(host: '127.0.0.1', port: 1);

/// DevicesService REAL, sembrado con el teléfono en reposo, colgado de un
/// socket falso. Es el camino de producción menos la red.
class _Rig {
  _Rig()
      : config = _config(),
        socket = _FakeSocket() {
    devices = DevicesService(config: config, socket: socket)
      ..debugSeedDevices([_phone()]);
    telephony = _FakeTelephony(config: config, socket: socket);
  }

  final ServerConfig config;
  final _FakeSocket socket;
  late final DevicesService devices;
  late final _FakeTelephony telephony;

  Device get phone => devices.byId(kPhoneDeviceId)!;

  Widget get screen => MaterialApp(
        home: TelephonyScreen(
          device: phone,
          service: devices,
          telephony: telephony,
        ),
      );
}

/// La pantalla tiene un `Timer.periodic` para el cronómetro: hay que
/// desmontarla al final o el test termina con un timer pendiente.
Future<void> _teardown(WidgetTester t) => t.pumpWidget(const SizedBox());

/// El evento del socket viaja por un stream asíncrono: el primer `pump`
/// lo entrega (puede caer después del frame) y el segundo pinta el frame.
Future<void> _deliver(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void main() {
  group('DevicesService aplica los deltas de dev_phone', () {
    test('un delta con sólo callState no borra el resto del bloque phone',
        () async {
      final socket = _FakeSocket();
      final service = DevicesService(config: _config(), socket: socket)
        ..debugSeedDevices([_phone()]);
      final d = service.byId(kPhoneDeviceId)!;

      socket.push(_dialing);
      await pumpEventQueue();
      expect(d.state.callState, 'dialing');
      expect(d.state.peerName, 'Euge');
      expect(d.state.peerNumber, '+5492364552179');
      expect(d.state.callDirection, 'out');
      expect(d.state.callStartedAt, 1787766330712);
      // La línea y la señal no viajaron en el delta: se conservan.
      expect(d.state.lineActive, 'active');
      expect(d.state.signalBars, 3);

      // El paso a 'active' viene SOLO: el peer tiene que sobrevivirlo.
      socket.push(_active);
      await pumpEventQueue();
      expect(d.state.callState, 'active');
      expect(d.phoneInCall, isTrue);
      expect(d.state.peerName, 'Euge');
      expect(d.state.peerNumber, '+5492364552179');
      expect(d.state.callStartedAt, 1787766330712);

      // Y un delta de señal en medio de la llamada no la borra.
      socket.push(_signal);
      await pumpEventQueue();
      expect(d.state.callState, 'active');
      expect(d.phoneInCall, isTrue);
      expect(d.state.signalBars, 2);
      expect(d.state.peerName, 'Euge');
    });

    test('al terminar, el peer se va con la llamada; la línea se queda',
        () async {
      final socket = _FakeSocket();
      final service = DevicesService(config: _config(), socket: socket)
        ..debugSeedDevices([_phone()]);
      final d = service.byId(kPhoneDeviceId)!;

      socket.push(_dialing);
      socket.push(_active);
      socket.push(_ended);
      await pumpEventQueue();
      expect(d.phoneInCall, isFalse);
      expect(d.state.peerName, isNull);

      socket.push(_idle);
      await pumpEventQueue();
      expect(d.state.callState, 'idle');
      expect(d.state.peerName, isNull);
      expect(d.state.peerNumber, isNull);
      expect(d.state.callDirection, isNull);
      // Si quedara, el cronómetro de la PRÓXIMA llamada arrancaría desde ésta.
      expect(d.state.callStartedAt, isNull);
      expect(d.state.lineActive, 'active');
      expect(d.state.signalBars, 3);
    });
  });

  group('la pantalla con el placeholder expirado', () {
    testWidgets('la card y Colgar salen del estado del device y duran',
        (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);

      // Reposo: teclado y Llamar.
      expect(find.byType(DialDisplay), findsOneWidget);
      expect(find.byTooltip('Llamar'), findsOneWidget);
      expect(find.byTooltip('Colgar'), findsNothing);

      // Llega el estado por el socket: la card, con quién, y Colgar.
      rig.socket.push(_dialing);
      await _deliver(t);
      expect(find.text('Euge'), findsOneWidget);
      expect(find.text('Marcando… · +5492364552179'), findsOneWidget);
      expect(find.byTooltip('Colgar'), findsOneWidget);
      expect(find.byTooltip('Llamar'), findsNothing);
      expect(find.byType(DialDisplay), findsNothing);

      rig.socket.push(_active);
      await _deliver(t);
      expect(find.text('En curso · +5492364552179'), findsOneWidget);
      expect(find.byTooltip('Colgar'), findsOneWidget);

      // Pasado el medio minuto —y con un delta de señal en el medio— sigue
      // igual: ya no hay placeholder que sostenga nada, sostiene el estado.
      await t.pump(const Duration(seconds: 31));
      rig.socket.push(_signal);
      await _deliver(t);
      expect(find.byTooltip('Colgar'), findsOneWidget);
      expect(find.text('Euge'), findsOneWidget);
      expect(find.text('En curso · +5492364552179'), findsOneWidget);

      // Termina: la pantalla vuelve a reposo sola.
      rig.socket.push(_ended);
      await _deliver(t);
      expect(find.byTooltip('Colgar'), findsNothing);
      rig.socket.push(_idle);
      await _deliver(t);
      expect(find.byTooltip('Colgar'), findsNothing);
      expect(find.byTooltip('Llamar'), findsOneWidget);
      expect(find.byType(DialDisplay), findsOneWidget);

      await _teardown(t);
    });

    testWidgets('una entrante sonando sigue sin colgarse', (t) async {
      // `ringingIn` manda sobre `live`: con el estado ahora aplicado de
      // verdad, un 'ringing' entrante tiene que seguir siendo Atender/Rechazar.
      final rig = _Rig();
      await t.pumpWidget(rig.screen);

      rig.socket.push({
        'on': true,
        'callState': 'ringing',
        'callDirection': 'in',
        'peerNumber': '+5492616110154',
        'peerName': 'Cami',
      });
      await _deliver(t);
      expect(find.text('Cami'), findsOneWidget);
      expect(find.byTooltip('Atender'), findsOneWidget);
      expect(find.byTooltip('Rechazar'), findsOneWidget);
      expect(find.byTooltip('Colgar'), findsNothing);

      await _teardown(t);
    });
  });

  group('llamar desde la agenda', () {
    const euge = PhoneContact(id: 'c1', name: 'Euge', number: '+5492364552179');

    testWidgets('el botón de llamar del contacto deja el número en el visor',
        (t) async {
      final rig = _Rig();
      rig.telephony.fakeContacts = const [euge];
      // Con el audio ya acá no hay sheet de aviso: el caso normal.
      rig.telephony.audio.on = true;
      await t.pumpWidget(rig.screen);

      await t.tap(find.byTooltip('Contactos'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Llamar a Euge'));
      await t.pumpAndSettle();

      expect(rig.telephony.dialed, [(null, 'c1')]);
      // El visor, no una fila del sheet: el sheet ya se cerró.
      expect(find.text('+5492364552179'), findsOneWidget);
      expect(find.byType(DialDisplay), findsOneWidget);

      // Y cuando el estado llega, la card muestra con quién.
      rig.socket.push(_dialing);
      await _deliver(t);
      expect(find.text('Euge'), findsOneWidget);
      expect(find.text('Marcando… · +5492364552179'), findsOneWidget);

      await _teardown(t);
    });

    testWidgets('la fila del contacto carga el número sin llamar', (t) async {
      final rig = _Rig();
      rig.telephony.fakeContacts = const [euge];
      await t.pumpWidget(rig.screen);

      await t.tap(find.byTooltip('Contactos'));
      await t.pumpAndSettle();
      await t.tap(find.text('Euge'));
      await t.pumpAndSettle();

      expect(rig.telephony.dialed, isEmpty);
      expect(find.text('+5492364552179'), findsOneWidget);

      await _teardown(t);
    });
  });

  group('el placeholder de "marcando"', () {
    testWidgets('al expirar sin estado re-lee el device y, si figura libre, lo dice',
        (t) async {
      var reloads = 0;
      final tel = _ExpiringTelephony(
        config: _config(),
        socket: SocketService(),
        reloadPhoneDevice: () async {
          reloads++;
          return _phone();
        },
      );

      tel.debugStartDialing('911');
      expect(tel.dialingNumber, '911');
      await t.pump(const Duration(seconds: 29));
      expect(tel.dialingNumber, '911');
      expect(reloads, 0);

      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(tel.dialingNumber, isNull);
      expect(reloads, 1);
      expect(tel.refreshes, 1);
      // No vuelve a reposo en silencio.
      expect(
        tel.actionError,
        'La llamada no se pudo confirmar: el teléfono de la casa figura libre.',
      );
      tel.stop();
    });

    testWidgets('al expirar con la llamada viva en el device, no avisa nada',
        (t) async {
      final tel = _ExpiringTelephony(
        config: _config(),
        socket: SocketService(),
        reloadPhoneDevice: () async => _phone(callState: 'active'),
      );

      tel.debugStartDialing('911');
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(tel.dialingNumber, isNull);
      expect(tel.refreshes, 1);
      expect(tel.actionError, isNull);
      tel.stop();
    });

    testWidgets('si el estado llega a tiempo se retira y no expira', (t) async {
      var reloads = 0;
      final socket = _FakeSocket();
      final tel = _ExpiringTelephony(
        config: _config(),
        socket: socket,
        reloadPhoneDevice: () async {
          reloads++;
          return _phone();
        },
      )..start();

      tel.debugStartDialing('911');
      socket.push(_dialing);
      await t.pump();
      expect(tel.dialingNumber, isNull);

      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(reloads, 0);
      expect(tel.actionError, isNull);
      tel.stop();
    });
  });
}
