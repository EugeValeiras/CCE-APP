// El audio de la llamada en el celular (CCE#12).
//
// Lo que se puede probar sin un iPhone y sin la línea 4G es TODO menos el audio
// mismo: el transporte, el estado y los textos. El motor de iOS
// (`AVAudioSession`/`AVAudioEngine`, la cancelación de eco, el jitter buffer)
// vive en Swift y sólo se puede verificar con la app instalada en un teléfono —
// eso está dicho en el PR, no simulado acá.
//
// Lo que sí se cubre, que es donde estaban los criterios de aceptación:
//
//  1. NEGAR EL MICRÓFONO deja la llamada viva y lo explica.
//  2. Tomar el audio conecta el WebSocket **y** mueve el ruteo del módem a
//     'web': sin lo segundo el módem no manda PCM y no se escucha nada.
//  3. EL DESALOJO ("gana el último") llega con su motivo y no se lee como una
//     falla de la app.
//  4. Los medidores se mueven en las dos direcciones.
//  5. El micrófono llega al socket como PCM crudo.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/phone_audio_service.dart';
import 'package:cce_app/utils/pcm_level.dart';
import 'package:cce_app/views/telephony/call_audio_panel.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 380, child: child)),
    );

/// Gateway de mentira: hace de `/api/phone/audio` (WebSocket binario) y de
/// `/api/phone/audio-route` (el POST que prende el PCM del módem).
class _FakeGateway {
  _FakeGateway(this._server) {
    _server.listen(_onRequest);
  }

  final HttpServer _server;

  /// Sockets aceptados, en orden.
  final List<WebSocket> sockets = [];
  /// Frames binarios que mandó el cliente (el micrófono).
  final List<List<int>> uplink = [];
  /// Cuerpos de los POST REST que llegaron, por path.
  final List<({String path, Map<String, dynamic> body})> posts = [];

  final _connected = Completer<WebSocket>();
  Future<WebSocket> get firstSocket => _connected.future;

  int get port => _server.port;

  Future<void> _onRequest(HttpRequest req) async {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((data) {
        if (data is List<int>) uplink.add(data);
      }, onDone: () {}, onError: (_) {});
      // El servidor real saluda con el formato del audio.
      ws.add(jsonEncode({
        'type': 'ready',
        'sessionId': 'audio-test',
        'client': 'app',
        'format': {'encoding': 'pcm_s16le', 'sampleRate': 8000, 'channels': 1},
      }));
      if (!_connected.isCompleted) _connected.complete(ws);
      return;
    }

    final raw = await utf8.decodeStream(req);
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Un POST sin body no es un problema para este doble.
    }
    posts.add((path: req.uri.path, body: body));
    req.response.statusCode = 201;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({'success': true, 'route': body['route']}));
    await req.response.close();
  }

  Future<void> close() async {
    for (final ws in sockets) {
      await ws.close();
    }
    await _server.close(force: true);
  }
}

/// Doble del canal nativo de iOS. Devuelve lo que el plugin devolvería.
class _FakeNative {
  /// Arranca con el permiso CONCEDIDO; los tests que prueban la negativa lo
  /// bajan antes de llamar a `take()`.
  bool granted = true;
  final List<MethodCall> calls = [];
  String output = 'receiver';

  static const _control = MethodChannel('com.cce.phoneaudio');
  static const _events = 'com.cce.phoneaudio/events';

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_control, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'permissionStatus':
          return granted ? 'granted' : 'denied';
        case 'start':
          return granted
              ? {'granted': true, 'permission': 'granted', 'output': output}
              : {'granted': false, 'permission': 'denied'};
        case 'setSpeaker':
          output = (call.arguments as Map)['speaker'] == true
              ? 'speaker'
              : 'receiver';
          return output;
        default:
          return null;
      }
    });
    // El EventChannel contesta al `listen` para que la suscripción prospere.
    messenger.setMockMessageHandler(_events, (message) async {
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
  }

  void remove() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_control, null);
    messenger.setMockMessageHandler(_events, null);
  }

  /// Simula un frame del micrófono subiendo por el EventChannel.
  Future<void> emitFrame(Uint8List pcm) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      _events,
      const StandardMethodCodec().encodeSuccessEnvelope(pcm),
      (_) {},
    );
  }

  /// Simula un evento de control del motor nativo.
  Future<void> emitEvent(Map<String, Object?> event) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      _events,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  bool called(String method) => calls.any((c) => c.method == method);
}

/// PCM de prueba: un tono cuadrado de amplitud [amp] (0-1).
Uint8List tone(int samples, double amp) {
  final data = ByteData(samples * 2);
  final value = (amp * 32767).round();
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? value : -value, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Espera a que [check] se cumpla, empujando el event loop. Sin esto, cada test
/// tendría un `Future.delayed` inventado y sería flaky en el CI.
Future<void> waitFor(bool Function() check, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'la condición no se cumplió a tiempo');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pcmLevel', () {
    test('el silencio mide cero y la señal plena mide uno', () {
      expect(pcmLevel(Uint8List(320)), 0);
      expect(pcmLevel(tone(160, 1)), closeTo(1, 0.01));
      expect(pcmLevel(tone(160, 0.5)), closeTo(0.5, 0.01));
    });

    test('un bloque vacío o de un byte suelto no rompe nada', () {
      // El byte huérfano es medio sample: se ignora en vez de desalinear todo
      // lo que sigue, que es lo que hace que un PCM suene a ruido blanco.
      expect(pcmLevel(Uint8List(0)), 0);
      expect(pcmLevel(Uint8List.fromList([0x42])), 0);
    });
  });

  group('LevelMeter', () {
    test('promedia la ventana y CAE cuando deja de llegar audio', () {
      // Un medidor congelado en un valor alto es peor que no tener medidor:
      // afirma que hay señal cuando la llamada ya terminó.
      final meter = LevelMeter();
      meter.add(tone(160, 1));
      meter.tick();
      expect(meter.value, closeTo(1, 0.01));

      meter.tick();
      expect(meter.value, lessThan(1));
      for (var i = 0; i < 20; i++) {
        meter.tick();
      }
      expect(meter.value, 0);
    });
  });

  group('describeAudioClose', () {
    test('el desalojo NO es un error, y llega con el motivo del servidor', () {
      final v = describeAudioClose(
        kAudioCloseEvicted,
        'Te sacaron el audio desde el dashboard. La llamada sigue.',
      );
      expect(v.state, PhoneAudioState.evicted);
      expect(v.message, contains('desde el dashboard'));
    });

    test('sin motivo, el desalojo igual se explica', () {
      final v = describeAudioClose(kAudioCloseEvicted, '');
      expect(v.state, PhoneAudioState.evicted);
      expect(v.message, contains('La llamada sigue'));
    });

    test('un cierre normal no deja ningún cartel', () {
      for (final code in [kAudioCloseEnded, 1000, null]) {
        final v = describeAudioClose(code, null);
        expect(v.state, PhoneAudioState.off);
        expect(v.message, isNull);
      }
    });

    test('el token rechazado y el corte se distinguen', () {
      expect(
        describeAudioClose(kAudioCloseUnauthorized, '').state,
        PhoneAudioState.error,
      );
      expect(
        describeAudioClose(kAudioCloseUnauthorized, '').message,
        contains('token'),
      );
      final cut = describeAudioClose(-1, 'Se cortó el audio: boom');
      expect(cut.state, PhoneAudioState.error);
      expect(cut.message, contains('boom'));
    });
  });

  group('PhoneAudioService', () {
    late _FakeGateway gateway;
    late _FakeNative native;
    late PhoneAudioService audio;

    setUp(() async {
      // `TestWidgetsFlutterBinding` mockea `HttpClient` y devuelve 400 a todo:
      // con eso, el POST que mueve el ruteo del módem nunca saldría y no se
      // podría verificar la mitad de lo que hace `take()`. Acá hace falta el
      // cliente de verdad, contra un servidor local.
      HttpOverrides.global = null;
      gateway = _FakeGateway(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );
      native = _FakeNative()..install();
      audio = PhoneAudioService(
        config: ServerConfig(host: '127.0.0.1', port: gateway.port),
      );
    });

    tearDown(() async {
      audio.dispose();
      native.remove();
      await gateway.close();
    });

    test('la URL del audio es la del gateway, sobre ws', () {
      expect(audio.wsUri.scheme, 'ws');
      expect(audio.wsUri.path, '/api/phone/audio');
      expect(audio.wsUri.port, gateway.port);
    });

    test('negar el micrófono deja la llamada viva y lo EXPLICA', () async {
      // Criterio de aceptación: sin micrófono la llamada sigue con el audio en
      // la casa, y la app dice por qué en vez de mostrar "error".
      native.granted = false;

      final ok = await audio.take();

      expect(ok, isFalse);
      expect(audio.state, PhoneAudioState.denied);
      expect(audio.error, contains('permiso'));
      expect(audio.error, contains('teléfono de la casa'));
      // Y no se abrió ningún socket ni se movió el ruteo del módem: negar el
      // micrófono no puede dejar la llamada ruteada a un celular que no habla.
      expect(gateway.sockets, isEmpty);
      expect(gateway.posts, isEmpty);
    });

    test('tomar el audio conecta el socket Y manda el ruteo a web', () async {
      final ok = await audio.take();

      expect(ok, isTrue);
      expect(audio.isOn, isTrue);
      expect(native.called('start'), isTrue);
      expect(gateway.sockets, hasLength(1));
      // Sin este POST el módem no manda PCM por USB y no se escucha nada,
      // aunque el WebSocket esté impecable.
      expect(gateway.posts, hasLength(1));
      expect(gateway.posts.first.path, '/api/phone/audio-route');
      expect(gateway.posts.first.body['route'], 'web');
    });

    test('el downlink de la línea mueve el medidor de salida', () async {
      await audio.take();
      final ws = await gateway.firstSocket;

      ws.add(tone(160, 0.8));
      await waitFor(() => audio.outputLevel > 0,
          reason: 'el medidor de salida no se movió con audio de la línea');

      expect(audio.outputLevel, greaterThan(0.1));
    });

    test('el micrófono sube al socket como PCM crudo', () async {
      await audio.take();
      await gateway.firstSocket;

      await native.emitFrame(tone(160, 0.5));
      await waitFor(() => gateway.uplink.isNotEmpty,
          reason: 'el frame del micrófono no llegó al servidor');

      expect(gateway.uplink.first, hasLength(320));
      expect(audio.inputLevel, greaterThanOrEqualTo(0));
    });

    test('el desalojo deja el motivo a la vista y suelta el audio', () async {
      // "Gana el último": si el dashboard reclama el audio, este celular lo
      // pierde. Lo que NO puede pasar es quedar diciendo que se escucha por acá.
      await audio.take();
      final ws = await gateway.firstSocket;

      await ws.close(
        kAudioCloseEvicted,
        'Te sacaron el audio desde el dashboard. La llamada sigue.',
      );
      await waitFor(() => audio.state == PhoneAudioState.evicted,
          reason: 'el desalojo no cambió el estado');

      expect(audio.isOn, isFalse);
      expect(audio.error, contains('desde el dashboard'));
      // Y el micrófono se apagó: dejar el punto naranja prendido después de
      // perder el audio sería inaceptable.
      expect(native.called('stop'), isTrue);

      audio.clearError();
      expect(audio.state, PhoneAudioState.off);
      expect(audio.error, isNull);
    });

    test('el altavoz y el mudo llegan al motor nativo', () async {
      await audio.take();

      await audio.setSpeaker(true);
      expect(audio.speakerOn, isTrue);
      expect(audio.output, PhoneAudioOutput.speaker);

      await audio.setMuted(true);
      expect(audio.muted, isTrue);
      expect(native.called('setMuted'), isTrue);
    });

    test('enchufar auriculares se refleja sin pedir nada', () async {
      await audio.take();

      await native.emitEvent({'type': 'output', 'value': 'headphones'});
      await waitFor(() => audio.output == PhoneAudioOutput.headphones,
          reason: 'el cambio de salida del sistema no llegó a la UI');

      expect(audio.speakerOn, isFalse);
    });

    test('una interrupción del sistema se explica en vez de quedar muda',
        () async {
      // Una llamada telefónica de verdad al celular se lleva el audio. La app
      // no puede evitarlo, pero sí puede no quedar mintiendo.
      await audio.take();

      await native.emitEvent(
          {'type': 'interruption', 'began': true, 'resumed': false});
      await waitFor(() => audio.error != null,
          reason: 'la interrupción no dijo nada');
      expect(audio.error, contains('teléfono de la casa'));

      await native.emitEvent(
          {'type': 'interruption', 'began': false, 'resumed': true});
      await waitFor(() => audio.error == null,
          reason: 'al volver de la interrupción quedó el cartel viejo');
      expect(audio.isOn, isTrue);
    });

    test('soltar el audio cierra el socket y apaga el micrófono', () async {
      await audio.take();
      await gateway.firstSocket;

      await audio.release();

      expect(audio.state, PhoneAudioState.off);
      expect(native.called('stop'), isTrue);
      await waitFor(
        () => gateway.sockets.first.readyState == WebSocket.closed,
        reason: 'el socket quedó abierto después de soltar el audio',
      );
    });

    test('cuando la llamada TERMINA, el audio se suelta solo', () async {
      // En el dashboard la sesión queda tomada entre llamadas; en un celular,
      // dejar el micrófono abierto después de colgar es otra cosa.
      await audio.take();
      audio.syncWithCall(true);
      audio.syncWithCall(false);

      await waitFor(() => audio.state == PhoneAudioState.off,
          reason: 'el audio no se soltó al terminar la llamada');
      expect(native.called('stop'), isTrue);
    });

    testWidgets('el panel dice dónde está el audio y ofrece traerlo', (t) async {
      // El botón es LA acción de esta tarea, y el estado tiene que leerse sin
      // entrar a ningún menú.
      await t.pumpWidget(_host(CallAudioPanel(audio: audio)));

      expect(find.text('El audio está en la casa'), findsOneWidget);
      expect(find.text('Escuchar acá'), findsOneWidget);
      // Sin el audio tomado no hay medidores que mostrar: no hay nada que medir.
      expect(find.text('Tu voz'), findsNothing);

      // `runAsync` porque acá hay red de verdad (el gateway local): el reloj
      // falso de `pumpWidget` no la haría avanzar nunca.
      await t.runAsync(() => audio.take());
      await t.pumpWidget(_host(CallAudioPanel(audio: audio)));

      expect(find.text('Hablás por el celular'), findsOneWidget);
      expect(find.text('Soltar'), findsOneWidget);
      expect(find.text('Por el auricular del celular'), findsWidgets);
      // Los medidores: sin ellos "no escucho nada" es indebuggeable.
      expect(find.text('Tu voz'), findsOneWidget);
      expect(find.text('La línea'), findsOneWidget);
      expect(find.text('Altavoz'), findsOneWidget);
      expect(find.text('Silenciar'), findsOneWidget);

      await t.runAsync(() => audio.release());
    });

    testWidgets('con auriculares puestos el panel no ofrece el altavoz',
        (t) async {
      // Forzar el parlante con los auriculares puestos es sacarle el audio de
      // la oreja al usuario sin que lo haya pedido.
      await t.runAsync(() => audio.take());
      await t.runAsync(
          () => native.emitEvent({'type': 'output', 'value': 'headphones'}));
      await t.pumpWidget(_host(CallAudioPanel(audio: audio)));

      expect(find.text('Altavoz'), findsNothing);
      expect(find.text('Por los auriculares'), findsWidgets);

      await t.runAsync(() => audio.release());
    });

    testWidgets('el desalojo se ve, y no se pinta como una falla', (t) async {
      await t.runAsync(() => audio.take());
      final ws = await t.runAsync(() => gateway.firstSocket);
      await t.runAsync(() async {
        await ws!.close(kAudioCloseEvicted, 'Te sacaron el audio desde el dashboard.');
        await waitFor(() => audio.state == PhoneAudioState.evicted);
      });
      await t.pumpWidget(_host(CallAudioPanel(audio: audio)));

      expect(find.textContaining('desde el dashboard'), findsOneWidget);
      // El icono del desalojo NO es el de error: es un intercambio.
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // Y se puede volver a traer.
      expect(find.text('Escuchar acá'), findsOneWidget);
    });

    test('sin el plugin nativo, la app lo dice en vez de romperse', () async {
      // Una app vieja contra un servidor nuevo, o un build sin el código de
      // iOS: la llamada tiene que seguir funcionando igual.
      native.remove();

      final ok = await audio.take();

      expect(ok, isFalse);
      expect(audio.state, PhoneAudioState.error);
      expect(audio.error, isNotNull);
      expect(gateway.sockets, isEmpty);
    });
  });
}
