// Una card de la home POR SAMSUNG, y el control sin selector
// (EugeValeiras/CCE#130).
//
// La home tenía una única card "TV" que no nombraba aparato: abría el que
// hubiera quedado elegido desde otra pantalla, y desde ahí no había forma de
// llegar al segundo Samsung salvo por los tabs de adentro del control. Lo que
// fijan estos tests:
//
//   1. Hay una card por aparato, con SU nombre.
//   2. Cada card muestra SU estado. Con dos cards leyendo el estado global,
//      las dos decían siempre lo mismo (el del aparato elegido).
//   3. Tocar una card abre el control DE ESE aparato, ya seleccionado.
//   4. El control no ofrece cambiar de aparato: no hay rastro del otro Samsung
//      en la pantalla.
//   5. Quien ya tenía la card "TV" destacada sigue teniendo cards de TV
//      después de actualizar, y lo migrado queda guardado.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/featured_item.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/models/tv_status.dart';
import 'package:cce_app/services/api_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/tv_service.dart';
import 'package:cce_app/views/rooms_list_screen.dart';
import 'package:cce_app/views/tv/tv_home_card.dart';
import 'package:cce_app/views/tv/tv_screen.dart';

const _televisorName = '65" OLED';
const _monitorName = '49" Odyssey OLED G9';
// Ids REALES de la casa: el televisor dejó de ser `dev_tv` cuando pasó a
// `dev_tv-1ca02124` (CCE#47), así que el id histórico no existe en /merged y
// las cards no pueden depender de él.
const _televisorDevice = 'dev_tv-1ca02124';
const _monitorDevice = 'dev_tv-ce588d39';

/// Samsung tal cual lo trae /devices/merged: `type: 'tv'` + capabilities de AV.
Device _samsung(String id, String name, {required bool on}) => Device(
      id: id,
      name: name,
      type: 'tv',
      capabilities: const ['volume', 'media_playback'],
      state: DeviceState(on: on, reachable: true),
    );

TvSummary _televisor() => TvSummary.fromJson(const {
      'id': 'tv-1ca02124',
      'name': _televisorName,
      'kind': 'tv',
      'paired': true,
      'isDefault': true,
    });

TvSummary _monitor() => TvSummary.fromJson(const {
      'id': 'tv-ce588d39',
      'name': _monitorName,
      'kind': 'monitor',
      'paired': true,
    });

/// API de mentira: la lista de Samsung sin red. Sin esto el `loadTvs()` de las
/// cards pisaría con [] la lista sembrada.
class _FakeApi extends ApiService {
  _FakeApi(this.tvs, {this.gate}) : super(ServerConfig());
  final List<TvSummary> tvs;

  /// Si está, GET /tv/tvs no responde hasta completarlo: sirve para separar el
  /// momento en que resuelven las prefs del momento en que llega la lista.
  final Completer<void>? gate;

  @override
  Future<List<TvSummary>> getTvs() async {
    if (gate != null) await gate!.future;
    return tvs;
  }

  @override
  Future<TvStatus> getTvStatus({String? tvId}) async =>
      const TvStatus(online: true, power: 'on', volume: 12);
}

DevicesService _devices(List<Device> house) {
  final s = DevicesService(config: ServerConfig(), socket: SocketService());
  s.debugSeedDevices(house);
  return s;
}

TvService _tvService({List<TvSummary> tvs = const []}) {
  final s = TvService(
    config: ServerConfig(),
    socket: SocketService(),
    api: _FakeApi(tvs),
  );
  if (tvs.isNotEmpty) s.debugSeed(tvs: tvs);
  return s;
}

/// Monta la home (sin red: ningún service arranca polling) y deja resolver las
/// prefs y el post-frame de las cards.
Future<void> _pumpHome(
  WidgetTester tester, {
  required DevicesService devices,
  required TvService tv,
}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: RoomsListScreen(service: devices, tv: tv),
  ));
  await tester.pump();
  await tester.pump();
}

/// El subtítulo de estado que muestra la card de [name].
String _estadoDe(WidgetTester tester, String name) {
  final card = find.ancestor(
    of: find.text(name),
    matching: find.byType(TvHomeCard),
  );
  expect(card, findsOneWidget, reason: 'no hay card para $name');
  final textos = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return textos.firstWhere((t) => t != name, orElse: () => '(sin estado)')!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la home muestra una card por Samsung, con su nombre',
      (tester) async {
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: _tvService(tvs: [_televisor(), _monitor()]),
    );

    expect(find.byType(TvHomeCard), findsNWidgets(2));
    expect(find.text(_televisorName), findsOneWidget);
    expect(find.text(_monitorName), findsOneWidget);
  });

  testWidgets('cada card muestra el estado de SU aparato', (tester) async {
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: _tvService(tvs: [_televisor(), _monitor()]),
    );

    expect(_estadoDe(tester, _televisorName), 'Encendido');
    expect(_estadoDe(tester, _monitorName), 'En espera',
        reason: 'con las dos cards leyendo el estado global decían lo mismo: '
            'el del aparato que estuviera elegido');
  });

  testWidgets('un evento del monitor no toca la card del televisor',
      (tester) async {
    final devices = _devices([
      _samsung(_televisorDevice, _televisorName, on: true),
      _samsung(_monitorDevice, _monitorName, on: true),
    ]);
    await _pumpHome(
        tester, devices: devices, tv: _tvService(tvs: [_televisor(), _monitor()]));
    expect(_estadoDe(tester, _televisorName), 'Encendido');

    devices.debugApplyDeviceEvent(DeviceStateEvent(
      deviceId: _monitorDevice,
      state: const {'on': false},
    ));
    await tester.pump();

    expect(_estadoDe(tester, _monitorName), 'En espera');
    expect(_estadoDe(tester, _televisorName), 'Encendido',
        reason: 'el monitor apagándose no puede apagar al televisor en la home');
  });

  testWidgets('tocar la card del monitor abre el control del monitor',
      (tester) async {
    final tv = _tvService(tvs: [_televisor(), _monitor()]);
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: tv,
    );
    expect(tv.selectedDeviceId, _televisorDevice,
        reason: 'se arranca en el principal, como siempre');

    await tester.tap(find.text(_monitorName));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final screen = tester.widget<TvScreen>(find.byType(TvScreen));
    expect(screen.deviceId, _monitorDevice,
        reason: 'la pantalla sabe qué aparato le pidieron');
    expect(tv.selectedDeviceId, _monitorDevice,
        reason: 'y la selección ya estaba hecha antes de construirla');
  });

  testWidgets('el control no ofrece cambiar de aparato', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tv = _tvService(tvs: [_televisor(), _monitor()])
      ..debugSeed(status: const TvStatus(online: true, power: 'on', volume: 12));

    await tester.pumpWidget(MaterialApp(
      home: TvScreen(service: tv, deviceId: _televisorDevice),
    ));
    await tester.pump();

    expect(find.text(_monitorName), findsNothing,
        reason: 'los tabs eran una forma de terminar apretando teclas en el '
            'aparato equivocado');
    expect(find.text(_televisorName), findsNothing,
        reason: 'sin selector no queda media fila de tabs tampoco');
  });

  testWidgets('quien tenía la card "TV" destacada no se queda sin card',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'home.featured': <String>['tv', 'jbl'],
    });
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: _tvService(tvs: [_televisor(), _monitor()]),
    );

    expect(find.byType(TvHomeCard), findsNWidgets(2),
        reason: 'el `tv` viejo se abrió en una card por aparato');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('home.featured'),
      ['tv:$_televisorDevice', 'tv:$_monitorDevice', 'jbl'],
      reason: 'y quedó guardado, en el lugar donde estaba el `tv`',
    );
  });

  testWidgets('la migración espera a la lista, que llega después del 1er frame',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'home.featured': <String>['tv'],
    });
    // SIN debugSeed y con GET /tv/tvs retenido: la home se dibuja con los
    // destacados ya leídos de prefs y la lista de aparatos todavía vacía, que
    // es lo que pasa de verdad en cada arranque. Si la migración se diera por
    // hecha en ese primer build, no ocurriría NUNCA.
    final gate = Completer<void>();
    final tv = TvService(
      config: ServerConfig(),
      socket: SocketService(),
      api: _FakeApi([_televisor(), _monitor()], gate: gate),
    );

    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: tv,
    );
    // Los destacados ya se leyeron; la lista de Samsung todavía no llegó.
    expect(tv.tvs, isEmpty);
    expect(find.byType(TvHomeCard), findsOneWidget,
        reason: 'la card histórica se muestra igual mientras tanto');

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(tv.tvs, hasLength(2), reason: 'ahora sí llegó la lista');
    expect(find.byType(TvHomeCard), findsNWidgets(2),
        reason: 'y recién ahí se migra: una card por aparato');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('home.featured'),
        ['tv:$_televisorDevice', 'tv:$_monitorDevice']);
  });

  testWidgets('con un backend sin lista de aparatos la home queda igual',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'home.featured': <String>['tv'],
    });
    await _pumpHome(
      tester,
      devices: _devices([_samsung(_televisorDevice, _televisorName, on: true)]),
      // Sin GET /tv/tvs: la lista vuelve vacía.
      tv: _tvService(),
    );

    expect(find.byType(TvHomeCard), findsOneWidget,
        reason: 'la card histórica sigue ahí: migrar sin lista la borraría');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('home.featured'), ['tv'],
        reason: 'y no se tocó lo guardado');
    expect(
      FeaturedItem.decodeList(prefs.getStringList('home.featured')),
      const [FeaturedItem(FeaturedKind.tv)],
    );
  });
}
