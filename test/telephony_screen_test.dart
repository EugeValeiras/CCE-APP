// La pantalla del teléfono como CONJUNTO (CCE#14): qué bloque está en cada
// momento. Los widgets sueltos tienen sus tests (telephony_widgets_test,
// dial_pad_look_test, phone_audio_test); esto fija CUÁNDO se montan, que es
// lo que el rediseño cambió:
//
//  1. En reposo la pantalla es teclado: ni el aviso ni el panel de audio.
//  2. Al tocar el primer dígito aparece el aviso con el botón para traer el
//     audio; con el audio tomado aparece el panel, haya número o no.
//  3. En llamada la card dice por dónde sale la voz, el número discado no se
//     muestra, y el 0 es 0.
//  4. Una entrante no se cuelga: se atiende o se rechaza, y el teclado no
//     disca.
//  5. El acuse de un tono se revierte si el tono no salió.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/phone_audio_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/telephony_service.dart';
import 'package:cce_app/views/telephony/audio_notice.dart';
import 'package:cce_app/views/telephony/call_audio_panel.dart';
import 'package:cce_app/views/telephony/dial_display.dart';
import 'package:cce_app/views/telephony_screen.dart';

/// Audio de mentira: sólo el estado que la pantalla lee.
class _FakeAudio extends PhoneAudioService {
  _FakeAudio({required super.config});

  bool _on = false;
  set on(bool value) {
    _on = value;
    notifyListeners();
  }

  /// Cuántas veces la pantalla pidió tomar el audio.
  int takes = 0;

  @override
  PhoneAudioState get state => _on ? PhoneAudioState.on : PhoneAudioState.off;
  @override
  bool get isOn => _on;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  Future<bool> take() async {
    takes++;
    on = true;
    return true;
  }

  @override
  Future<void> release() async {}
}

/// Telefonía de mentira: estado inyectado, comandos que no salen a la red.
class _FakeTelephony extends TelephonyService {
  _FakeTelephony({required super.config, required super.socket})
      : _audio = _FakeAudio(config: config);

  final _FakeAudio _audio;
  PhoneStatus fakeStatus = PhoneStatus.fromJson({'audioRoute': 'speaker'});
  Map<String, dynamic>? fakeIncoming;

  /// Qué contesta [sendDtmf], y qué tonos le llegaron.
  bool dtmfOk = true;
  final List<String> dtmf = [];

  /// Llamadas que llegaron a [call]: (number, contactId).
  final List<(String?, String?)> dialed = [];

  @override
  _FakeAudio get audio => _audio;
  @override
  PhoneStatus get status => fakeStatus;
  @override
  Map<String, dynamic>? get incoming => fakeIncoming;
  @override
  String? get dialingNumber => null;
  @override
  String? get actionError => null;
  @override
  bool get busy => false;

  @override
  Future<void> refresh() async {}
  @override
  Future<void> loadContacts({bool force = false}) async {}
  @override
  Future<bool> sendDtmf(String digits) async {
    dtmf.add(digits);
    return dtmfOk;
  }

  @override
  Future<bool> call({String? number, String? contactId}) async {
    dialed.add((number, contactId));
    return true;
  }
}

class _FakeDevices extends DevicesService {
  _FakeDevices(this.phone, {required super.config, required super.socket});

  Device phone;

  @override
  Device? byId(String id) => id == phone.id ? phone : null;
  @override
  String displayName(Device d) => 'Teléfono';
}

Device _phone({String? callState, String? dir, String? peer}) => Device(
      id: 'dev_phone',
      name: 'Teléfono',
      type: 'phone',
      capabilities: const ['phone'],
      state: DeviceState(
        callState: callState,
        callDirection: dir,
        peerName: peer,
        lineActive: 'active',
        signalBars: 4,
        networkTech: 'WCDMA',
        networkOperator: 'Personal',
      ),
    );

class _Rig {
  _Rig({Device? device})
      : config = ServerConfig(host: '127.0.0.1', port: 1),
        socket = SocketService() {
    telephony = _FakeTelephony(config: config, socket: socket);
    devices = _FakeDevices(device ?? _phone(), config: config, socket: socket);
  }

  final ServerConfig config;
  final SocketService socket;
  late final _FakeTelephony telephony;
  late final _FakeDevices devices;

  Widget get screen => MaterialApp(
        home: TelephonyScreen(
          device: devices.phone,
          service: devices,
          telephony: telephony,
        ),
      );
}

/// La pantalla tiene un `Timer.periodic` para el cronómetro: hay que
/// desmontarla al final o el test termina con un timer pendiente.
Future<void> _teardown(WidgetTester t) => t.pumpWidget(const SizedBox());

/// El aviso entra y sale con un `AnimatedSize`: darle tiempo a terminar.
Future<void> _settle(WidgetTester t) => t.pump(const Duration(milliseconds: 300));

void main() {
  group('en reposo', () {
    testWidgets('la pantalla es teclado: ni aviso ni panel de audio', (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);

      expect(find.byType(DialDisplay), findsOneWidget);
      for (final k in ['1', '5', '0', '*', '#']) {
        expect(find.text(k), findsOneWidget, reason: 'falta la tecla $k');
      }
      expect(find.byType(AudioRouteNotice), findsNothing,
          reason: 'en reposo el aviso no ocupa la mitad de arriba');
      expect(find.byType(CallAudioPanel), findsNothing,
          reason: 'en reposo el panel no ocupa la mitad de arriba');
      expect(find.textContaining('no vas a escuchar'), findsNothing);

      await _teardown(t);
    });

    testWidgets('al tocar el primer dígito aparece el aviso, con el botón',
        (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);

      await t.tap(find.text('5'));
      await _settle(t);

      // El aviso del #10/#12, sin suavizar, con la acción al lado.
      expect(find.text('El audio se queda en la casa'), findsOneWidget);
      expect(find.textContaining('no vas a escuchar ni hablar'), findsOneWidget);
      expect(find.text('Escuchar acá'), findsOneWidget);
      // Y NO el panel: dos carteles para lo mismo era el problema.
      expect(find.byType(CallAudioPanel), findsNothing);

      // Al borrar el último dígito, vuelve a ser teclado.
      await t.tap(find.byIcon(Icons.backspace_outlined));
      await _settle(t);
      expect(find.byType(AudioRouteNotice), findsNothing);

      await _teardown(t);
    });

    testWidgets('con el audio tomado aparece el panel, haya número o no',
        (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);

      // Un micrófono abierto no se esconde, aunque el teclado esté vacío.
      rig.telephony.audio.on = true;
      await _settle(t);

      expect(find.byType(CallAudioPanel), findsOneWidget);
      expect(find.text('Hablás por el celular'), findsOneWidget);
      expect(find.text('Soltar'), findsOneWidget);
      // El aviso no se repite: el panel ya dice que se escucha por acá.
      expect(find.byType(AudioRouteNotice), findsNothing);
      expect(find.textContaining('no vas a escuchar'), findsNothing);

      // Con un dígito sigue siendo el panel el que manda.
      await t.tap(find.text('5'));
      await _settle(t);
      expect(find.byType(CallAudioPanel), findsOneWidget);
      expect(find.byType(AudioRouteNotice), findsNothing);

      await _teardown(t);
    });
  });

  group('al llamar', () {
    Future<void> typeAndCall(WidgetTester t) async {
      for (final k in ['9', '1', '1']) {
        await t.tap(find.text(k));
      }
      await _settle(t);
      await t.tap(find.byTooltip('Llamar'));
      await t.pumpAndSettle();
    }

    testWidgets('con el audio en la casa avisa ANTES y no disca hasta elegir',
        (t) async {
      // Espejo de CCE#15: la llamada saldría, el destino sonaría, y el
      // usuario no escucharía nada. Se entera acá, no con la llamada en curso.
      final rig = _Rig();
      await t.pumpWidget(rig.screen);
      await typeAndCall(t);

      expect(find.text('El audio se queda en la casa'), findsWidgets);
      expect(find.text('Escuchar acá y llamar'), findsOneWidget);
      expect(find.text('Llamar igual'), findsOneWidget);
      expect(rig.telephony.dialed, isEmpty,
          reason: 'sin elegir, la llamada no sale');

      // "Llamar igual" disca sin tocar el audio.
      await t.tap(find.text('Llamar igual'));
      await t.pumpAndSettle();
      expect(rig.telephony.dialed, [('911', null)]);
      expect(rig.telephony.audio.takes, 0);

      await _teardown(t);
    });

    testWidgets('"Escuchar acá y llamar" toma el audio y DESPUÉS disca',
        (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);
      await typeAndCall(t);

      await t.tap(find.text('Escuchar acá y llamar'));
      await t.pumpAndSettle();
      expect(rig.telephony.audio.takes, 1);
      expect(rig.telephony.dialed, [('911', null)]);

      await _teardown(t);
    });

    testWidgets('cerrar el aviso sin elegir no disca nada', (t) async {
      final rig = _Rig();
      await t.pumpWidget(rig.screen);
      await typeAndCall(t);

      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(rig.telephony.dialed, isEmpty);
      expect(rig.telephony.audio.takes, 0);

      await _teardown(t);
    });

    testWidgets('con el audio ya en este celular no pregunta nada', (t) async {
      // El caso normal no gana ningún toque (criterio de CCE#15).
      final rig = _Rig();
      await t.pumpWidget(rig.screen);
      rig.telephony.audio.on = true;
      await _settle(t);
      await typeAndCall(t);

      expect(find.text('Llamar igual'), findsNothing);
      expect(rig.telephony.dialed, [('911', null)]);

      await _teardown(t);
    });
  });

  group('en llamada', () {
    testWidgets('la card dice por dónde sale la voz y el 0 es 0', (t) async {
      final rig = _Rig(
        device: _phone(callState: 'active', dir: 'out', peer: 'Porton'),
      );
      await t.pumpWidget(rig.screen);

      expect(find.text('Porton'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      // EL aviso, en la dirección "en la casa"...
      expect(find.textContaining('no vas a escuchar ni hablar'), findsOneWidget);
      expect(find.textContaining(rig.telephony.status.audioRouteLabel),
          findsOneWidget);
      // ...con la acción para traerlo, en la misma card.
      expect(find.text('Escuchar acá'), findsOneWidget);
      // El número discado no tiene lugar en una llamada.
      expect(find.byType(DialDisplay), findsNothing);
      // Un '+' no es un tono.
      expect(find.text('+'), findsNothing);

      // ...y en la dirección "en el celular", con los controles.
      rig.telephony.audio.on = true;
      await _settle(t);
      expect(find.textContaining('Estás hablando por el celular'), findsOneWidget);
      expect(find.textContaining('no vas a escuchar'), findsNothing);
      expect(find.text('Tu voz'), findsOneWidget);
      expect(find.text('Altavoz'), findsOneWidget);
      expect(find.text('Soltar'), findsOneWidget);

      await _teardown(t);
    });

    testWidgets('los tonos se acusan, y el acuse se revierte si no salió',
        (t) async {
      final rig = _Rig(
        device: _phone(callState: 'active', dir: 'out', peer: 'Porton'),
      );
      await t.pumpWidget(rig.screen);

      await t.tap(find.text('5'));
      await t.pump();
      expect(rig.telephony.dtmf, ['5']);
      // La tecla y el acuse.
      expect(find.text('5'), findsNWidgets(2));

      rig.telephony.dtmfOk = false;
      await t.tap(find.text('7'));
      await t.pump();
      // Salió el tono → mientras viaja se acusa...
      expect(rig.telephony.dtmf, ['5', '7']);
      await t.pump();
      // ...y al fallar se retira: la pantalla no miente sobre lo que recibió
      // el menú de voz del otro lado.
      expect(find.text('57'), findsNothing);
      expect(find.text('5'), findsNWidgets(2));

      await _teardown(t);
    });
  });

  group('con una entrante', () {
    testWidgets('no se cuelga: se atiende o se rechaza, y el teclado no disca',
        (t) async {
      final rig = _Rig(
        device: _phone(callState: 'ringing', dir: 'in', peer: 'Cami'),
      );
      rig.telephony.fakeIncoming = {'number': '+5492616110154', 'contactName': 'Cami'};
      await t.pumpWidget(rig.screen);

      expect(find.text('Cami'), findsOneWidget);
      expect(find.byTooltip('Atender'), findsOneWidget);
      expect(find.byTooltip('Rechazar'), findsOneWidget);
      expect(find.byTooltip('Colgar'), findsNothing);
      expect(find.byTooltip('Llamar'), findsNothing);

      // Avisa ANTES de atender, y ofrece traer el audio ahí mismo.
      expect(find.textContaining('hablás por el teléfono de la casa'),
          findsOneWidget);
      expect(find.text('Escuchar acá'), findsOneWidget);

      // El teclado está, pero apagado: no manda tonos a una llamada que no
      // existe todavía.
      await t.tap(find.text('5'));
      await t.pump();
      expect(rig.telephony.dtmf, isEmpty);

      // Con el audio ya tomado, el aviso se da vuelta.
      rig.telephony.audio.on = true;
      await _settle(t);
      expect(find.textContaining('hablás y escuchás por el celular'),
          findsOneWidget);
      expect(find.textContaining('hablás por el teléfono de la casa'),
          findsNothing);

      await _teardown(t);
    });
  });
}
