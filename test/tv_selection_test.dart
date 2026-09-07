// El control abre el aparato que se TOCÓ (EugeValeiras/CCE#130).
//
// Antes de esto, qué Samsung controlaba la pantalla lo decidía el estado global
// del servicio —el último elegido desde cualquier pantalla— y el parche era una
// fila de tabs adentro del control. Lo que fija este test es lo que reemplaza a
// esos tabs: quien abre el control NOMBRA el aparato, y esa selección tiene que
// estar hecha antes de que la pantalla se construya para que no haya un frame
// con el aparato anterior.
//
//   1. `selectDevice` es SÍNCRONO en lo que decide qué se ve: al volver, ya
//      cambió el aparato y ya descartó el estado del otro.
//   2. Pedir el aparato que YA se está mostrando no descarta su estado (eso era
//      un spinner por nada al abrir el control desde la home).
//   3. Un pedido que llega antes que GET /tv/tvs no se pierde: queda pendiente
//      y lo aplica la lista al llegar. Antes era un no-op silencioso y el
//      control abría el otro Samsung, con su estado y sus teclas.
//   4. La respuesta de un GET /tv/status en vuelo NO pisa la pantalla si
//      mientras tanto se cambió de aparato.
//   5. El switch de una card de la home comanda SU aparato sin llevarse el
//      control de la otra.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/models/tv_status.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/tv_service.dart';

/// Lo que devuelve GET /tv/tvs para esta casa (shape real del backend).
const _televisorJson = {
  'id': 'tv',
  'name': '65" OLED',
  'kind': 'tv',
  'deviceId': '1ca02124-d3af-710f-0ccf-921590094a86',
  'paired': true,
  'isDefault': true,
};

const _monitorJson = {
  'id': 'tv-ce588d39',
  'name': '49" Odyssey OLED G9',
  'kind': 'monitor',
  'deviceId': 'ce588d39-95fc-b700-fcce-813bb6c58284',
  'paired': false,
  'isDefault': false,
  // Un monitor sin sintonizador: sin esto el fixture no distingue features y
  // la aserción del rocker de canales no probaría nada.
  'features': {
    'power': true, 'volume': true, 'mute': true, 'channel': false,
    'input': true, 'playback': true, 'tracks': true, 'apps': false,
    'remote': true, 'pictureMode': true, 'soundMode': true, 'ambient': false,
  },
};

TvSummary _televisor() =>
    TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson));
TvSummary _monitor() =>
    TvSummary.fromJson(Map<String, dynamic>.from(_monitorJson));

const _encendido = TvStatus(online: true, power: 'on', volume: 42);
const _apagado = TvStatus(online: true, power: 'off', volume: 7);

/// API de mentira: registra qué `?tv=` pidió cada llamada y deja controlar
/// CUÁNDO responde cada GET /tv/status, que es lo que hace falta para provocar
/// la carrera entre dos aparatos.
class _FakeApi extends ApiService {
  _FakeApi() : super(ServerConfig());

  List<TvSummary> tvs = const [];
  int tvsCalls = 0;

  /// tvId pedido → estado a devolver.
  final Map<String?, TvStatus> statuses = {};

  /// tvId pedido, en orden, por cada getTvStatus.
  final List<String?> statusCalls = [];

  /// (tvId, on) de cada PUT /tv/power.
  final List<(String?, bool)> powerCalls = [];

  /// Si está, getTvStatus espera a que se complete antes de responder.
  Completer<void>? gate;

  @override
  Future<List<TvSummary>> getTvs() async {
    tvsCalls++;
    return tvs;
  }

  @override
  Future<TvStatus> getTvStatus({String? tvId}) async {
    statusCalls.add(tvId);
    final g = gate;
    if (g != null) await g.future;
    return statuses[tvId] ?? const TvStatus(online: false, power: 'off');
  }

  @override
  Future<String> setTvPower(bool on, {String? tvId}) async {
    powerCalls.add((tvId, on));
    return on ? 'on' : 'off';
  }
}

TvService _service(_FakeApi api) =>
    TvService(config: ServerConfig(), socket: SocketService(), api: api);

void main() {
  group('selectDevice: el aparato lo nombra quien abre el control', () {
    test('cambia de aparato SIN esperar la red', () {
      final api = _FakeApi();
      final s = _service(api)
        ..debugSeed(tvs: [_televisor(), _monitor()], status: _encendido);

      // Sin await: es lo que hace el tile de la habitación antes de navegar.
      s.selectDevice('dev_tv-ce588d39');

      // Al volver de la llamada la pantalla que se construya YA ve el monitor.
      expect(s.selectedTvId, 'tv-ce588d39', reason: 'es lo que viaja en ?tv=');
      expect(s.selectedDeviceId, 'dev_tv-ce588d39');
      expect(s.displayName, '49" Odyssey OLED G9');
      expect(s.features.channel, isFalse);
      expect(s.status, isNull,
          reason: 'el estado del televisor NO se muestra como si fuera el del '
              'monitor: ese frame es el parpadeo que hay que evitar');
      expect(s.loading, isTrue, reason: 'y mientras tanto se ve "cargando"');
    });

    test('pedir el que YA se está mostrando no lo manda al spinner', () {
      final api = _FakeApi();
      // Nadie eligió nada: se está mostrando el principal por defecto.
      final s = _service(api)
        ..debugSeed(tvs: [_televisor(), _monitor()], status: _encendido);
      expect(s.selectedDeviceId, 'dev_tv');

      s.selectDevice('dev_tv');

      expect(s.status, same(_encendido),
          reason: 'abrir el control del televisor desde la home no puede '
              'borrar su estado y mostrar un spinner por nada');
      expect(s.loading, isFalse);
      expect(api.statusCalls, isEmpty, reason: 'ni pedirlo de nuevo');
      expect(s.selectedTvId, 'tv',
          reason: 'igual queda fijado: deja de depender del default');
    });

    test('un pedido que llega antes que la lista NO se pierde', () async {
      final api = _FakeApi()..tvs = [_televisor(), _monitor()];
      api.statuses['tv-ce588d39'] = _apagado;
      // Estado del televisor ya cargado, lista de aparatos todavía no: es la
      // app recién abierta, cuando GET /tv/tvs no volvió.
      final s = _service(api)..debugSeed(status: _encendido);

      s.selectDevice('dev_tv-ce588d39');

      expect(s.status, isNull,
          reason: 'sin poder resolver el aparato no se sigue mostrando el '
              'estado del televisor como si fuera el del monitor');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.selectedTvId, 'tv-ce588d39',
          reason: 'la lista llegó y aplicó el pedido que había quedado '
              'anotado; antes se descartaba en silencio y el control abría '
              'el televisor');
      expect(s.selectedDeviceId, 'dev_tv-ce588d39');
      expect(s.isOn, isFalse, reason: 'y el estado que se ve es el del monitor');
      expect(api.statusCalls, contains('tv-ce588d39'));
    });

    test('sin GET /tv/tvs el pedido se suelta y no deja la pantalla colgada',
        () async {
      // Backend viejo: la lista vuelve SIEMPRE vacía.
      final api = _FakeApi();
      api.statuses[null] = _encendido;
      final s = _service(api);

      s.selectDevice('dev_tv-ce588d39');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.selectedTvId, isNull,
          reason: 'sin lista los comandos van sin ?tv= y los resuelve el '
              'backend con su aparato por defecto — como cuando había uno');
      expect(s.status, isNotNull, reason: 'y la pantalla termina con estado');
      expect(s.loading, isFalse);
    });

    test('con el aparato sin resolver, un refresh NO trae el del default',
        () async {
      final api = _FakeApi()..tvs = [_televisor(), _monitor()];
      api.statuses[null] = _encendido; // lo que responde /tv/status sin ?tv=
      api.statuses['tv-ce588d39'] = _apagado;
      final s = _service(api)..debugSeed(status: _encendido);

      // Se abre el control del monitor antes de que llegue GET /tv/tvs, y la
      // pantalla pide el estado en su post-frame, como hace siempre.
      s.selectDevice('dev_tv-ce588d39');
      unawaited(s.refresh());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.selectedDeviceId, 'dev_tv-ce588d39');
      expect(api.statusCalls, isNot(contains(null)),
          reason: 'un GET sin ?tv= lo resuelve el backend con SU aparato por '
              'defecto: sería pedir el estado del televisor para la pantalla '
              'del monitor');
      expect(s.volume, 7, reason: 'y lo que se ve es el estado del monitor');
    });

    test('el televisor histórico sin lista cargada ya es el que se muestra',
        () {
      final api = _FakeApi();
      final s = _service(api)..debugSeed(status: _encendido);

      s.selectDevice('dev_tv');

      expect(s.status, same(_encendido),
          reason: 'con un solo Samsung la pantalla queda igual que siempre');
    });
  });

  group('refresh: el estado que llega es el del aparato que se muestra', () {
    test('la respuesta del aparato anterior NO pisa al nuevo', () async {
      final api = _FakeApi();
      api.statuses['tv'] = _encendido;
      api.statuses['tv-ce588d39'] = _apagado;
      final s = _service(api)..debugSeed(tvs: [_televisor(), _monitor()]);

      // GET /tv/status del televisor EN VUELO...
      final gate = Completer<void>();
      api.gate = gate;
      unawaited(s.refresh());
      expect(api.statusCalls, ['tv']);

      // ...y mientras vuela se abre el control del monitor.
      s.selectDevice('dev_tv-ce588d39');
      api.gate = null;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(s.selectedDeviceId, 'dev_tv-ce588d39');
      expect(s.volume, 7,
          reason: 'el estado que quedó es el del MONITOR: la respuesta del '
              'televisor llegó tarde y ya no era la de esta pantalla');
      expect(api.statusCalls, contains('tv-ce588d39'),
          reason: 'y el pedido del monitor no se descartó por haber caído '
              'encima de uno en vuelo');
    });
  });

  group('el switch de una card no le roba el control a la otra', () {
    test('setPowerOf manda al aparato pedido y deja el elegido donde estaba',
        () async {
      final api = _FakeApi();
      final s = _service(api)
        ..debugSeed(tvs: [_televisor(), _monitor()], status: _encendido);

      final ok = await s.setPowerOf('dev_tv-ce588d39', false);

      expect(ok, isTrue);
      expect(api.powerCalls, [('tv-ce588d39', false)],
          reason: 'el comando lleva el ?tv= del aparato de la card');
      expect(s.selectedDeviceId, 'dev_tv',
          reason: 'tocar el switch del monitor no cambia lo que controla la '
              'pantalla del control');
      expect(s.isOn, isTrue,
          reason: 'ni toca el estado que se muestra del televisor');
    });

    test('el optimismo aplica cuando la card ES la del aparato mostrado',
        () async {
      final api = _FakeApi();
      final s = _service(api)
        ..debugSeed(tvs: [_televisor(), _monitor()], status: _encendido);

      final future = s.setPowerOf('dev_tv', false);
      expect(s.isOn, isFalse, reason: 'el switch se mueve al toque');
      await future;
      expect(api.powerCalls, [('tv', false)]);
    });

    test('sin poder resolver el aparato NO manda nada', () async {
      final api = _FakeApi();
      // Lista cargada, pero la card apunta a uno que el backend ya no lista.
      final s = _service(api)..debugSeed(tvs: [_televisor()]);

      expect(await s.setPowerOf('dev_tv-borrado', false), isFalse);
      expect(api.powerCalls, isEmpty,
          reason: 'sin ?tv= el backend usa SU aparato por defecto: mandarlo '
              'sería apagar el televisor cuando se tocó el monitor');
    });
  });
}
