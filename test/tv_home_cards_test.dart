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
import 'package:cce_app/widgets/media_device_tile.dart';

const _televisorName = '65" OLED';
const _monitorName = '49" Odyssey OLED G9';
// Ids REALES de la casa: el televisor dejó de ser `dev_tv` cuando pasó a
// `dev_tv-1ca02124` (CCE#47), así que el id histórico no existe en /merged y
// las cards no pueden depender de él.
const _televisorDevice = 'dev_tv-1ca02124';
const _monitorDevice = 'dev_tv-ce588d39';

/// Una luz cualquiera, para que la casa no esté vacía.
Device _luz() => Device(
      id: 'dev_luz',
      name: 'Luz',
      type: 'Extended color light',
      state: DeviceState(on: true, bri: 200),
    );

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

  int tvsCalls = 0;
  int statusCalls = 0;

  /// Si está, getTvStatus espera: le da al GET una latencia realista.
  Completer<void>? statusGate;

  /// Si está, GET /tv/tvs no responde hasta completarlo: sirve para separar el
  /// momento en que resuelven las prefs del momento en que llega la lista.
  final Completer<void>? gate;

  @override
  Future<List<TvSummary>?> getTvs() async {
    tvsCalls++;
    if (gate != null) await gate!.future;
    return tvs;
  }

  @override
  Future<TvStatus> getTvStatus({String? tvId}) async {
    statusCalls++;
    final g = statusGate;
    if (g != null) await g.future;
    return const TvStatus(online: true, power: 'on', volume: 12);
  }
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

  testWidgets('el control dice qué aparato comanda y no deja cambiarlo',
      (tester) async {
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
        reason: 'el otro Samsung no está en pantalla: los tabs eran una forma '
            'de terminar apretando teclas en el aparato equivocado');
    expect(find.text(_televisorName), findsOneWidget,
        reason: 'pero el que SÍ se comanda tiene que decir su nombre: la '
            'pantalla no tiene AppBar y sin esto el primer aviso de estar en '
            'el aparato equivocado es el aparato equivocado reaccionando');
  });

  testWidgets('el rótulo del aparato no es un selector', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tv = _tvService(tvs: [_televisor(), _monitor()])
      ..debugSeed(status: const TvStatus(online: true, power: 'on', volume: 12));

    await tester.pumpWidget(MaterialApp(
      home: TvScreen(service: tv, deviceId: _televisorDevice),
    ));
    await tester.pump();
    await tester.tap(find.text(_televisorName));
    await tester.pump();

    expect(tv.selectedDeviceId, _televisorDevice,
        reason: 'tocarlo no abre ningún selector ni cambia de aparato');
    expect(find.text(_monitorName), findsNothing);
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

  // Review de CCE-APP#48: cuando el aparato de un widget no se puede resolver,
  // caer al estado o al nombre del aparato SELECCIONADO es peor que no decir
  // nada — la card queda honesta sobre el estado y mentirosa sobre cuál es.
  testWidgets('la card sin nombre resoluble no se rotula con el del elegido',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // El aparato de la card no está ni en el inventario ni en GET /tv/tvs; el
    // elegido es el televisor y se llama '65" OLED'.
    final tv = _tvService(tvs: [_televisor()]);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: TvHomeCard(
          service: tv,
          deviceId: _monitorDevice,
          devices: _devices([_samsung(_televisorDevice, _televisorName, on: true)]),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text(_televisorName), findsNothing,
        reason: 'rotular la card del monitor con el nombre del televisor es '
            'exactamente el error que este issue viene a arreglar');
    expect(find.text('Samsung TV'), findsOneWidget);
  });

  testWidgets('el tile de la habitación tampoco copia el estado del elegido',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // El elegido (el televisor) está ENCENDIDO; el aparato del tile no está en
    // el inventario, así que de él no se sabe nada.
    final tv = _tvService(tvs: [_televisor(), _monitor()])
      ..debugSeed(status: const TvStatus(online: true, power: 'on', volume: 3));
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: SizedBox(
          height: 200,
          child: TvDeviceTile(
            service: tv,
            devices: _devices(
                [_samsung(_televisorDevice, _televisorName, on: true)]),
            deviceId: _monitorDevice,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Encendido'), findsNothing,
        reason: 'el tile del monitor decía "Encendido" copiándole al televisor');
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('la home no pide la lista de Samsung una vez por card',
      (tester) async {
    final api = _FakeApi([_televisor(), _monitor()]);
    final tv = TvService(
      config: ServerConfig(),
      socket: SocketService(),
      api: api,
    )..debugSeed(tvs: [_televisor(), _monitor()]);
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: tv,
    );

    expect(find.byType(TvHomeCard), findsNWidgets(2));
    expect(api.tvsCalls, 1,
        reason: 'dos cards montándose eran dos GET /tv/tvs concurrentes, y esa '
            'concurrencia es lo que hacía que una respuesta vieja se llevara '
            'puesta la selección');
  });

  testWidgets('reabrir el control del mismo aparato SÍ relee su estado',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _FakeApi([_televisor(), _monitor()]);
    final tv = TvService(
      config: ServerConfig(),
      socket: SocketService(),
      api: api,
    )..debugSeed(
        tvs: [_televisor(), _monitor()],
        selectedId: 'tv-1ca02124',
        status: const TvStatus(online: true, power: 'on', volume: 12));
    api.statusCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: TvScreen(service: tv, deviceId: _televisorDevice),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.statusCalls, 1,
        reason: 'el seed trae los campos que el socket NO emite (fuentes, '
            'nombre de canal, modos, disabled) y reabrir el control es el '
            'momento de refrescarlos: saltearlo por tener ya un estado los '
            'dejaba viejos sin forma de forzar la lectura');
  });

  testWidgets('en el arranque no se lee el estado del aparato elegido por card',
      (tester) async {
    final api = _FakeApi([_televisor(), _monitor()]);
    final tv = TvService(
      config: ServerConfig(),
      socket: SocketService(),
      api: api,
    )..debugSeed(tvs: [_televisor(), _monitor()]);
    // La casa cargó, pero los Samsung NO están todavía en /devices/merged: es
    // el arranque en frío, con las cards ya montadas y sin poder resolver su
    // device. (Con el inventario del todo vacío la home muestra el splash y las
    // cards ni se construyen, así que el test no probaría nada.)
    await _pumpHome(tester, devices: _devices([_luz()]), tv: tv);
    expect(find.byType(TvHomeCard), findsNWidgets(2),
        reason: 'las cards TIENEN que estar montadas para que esto pruebe algo');

    expect(api.statusCalls, 0,
        reason: 'cada card pedía el estado del aparato ELEGIDO al no encontrar '
            'el suyo en el inventario: dos lecturas que ninguna card iba a '
            'mirar, y del aparato equivocado');
  });

  testWidgets('abrir un control cuesta UN solo GET /tv/status', (tester) async {
    final api = _FakeApi([_televisor(), _monitor()]);
    final tv = TvService(
      config: ServerConfig(),
      socket: SocketService(),
      api: api,
    )..debugSeed(tvs: [_televisor(), _monitor()]);
    await _pumpHome(
      tester,
      devices: _devices([
        _samsung(_televisorDevice, _televisorName, on: true),
        _samsung(_monitorDevice, _monitorName, on: false),
      ]),
      tv: tv,
    );
    api.statusCalls = 0;
    // El GET tarda, como en la vida real: respondiendo instantáneo el test
    // mediría un artefacto del fake y no lo que pasa en el teléfono.
    final lento = Completer<void>();
    api.statusGate = lento;

    await tester.tap(find.text(_monitorName));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.statusCalls, 1,
        reason: 'elegir el aparato ya pide su estado; el refresh de cortesía '
            'de la pantalla lo pedía una segunda vez del mismo aparato');
    api.statusGate = null;
    lento.complete();
    await tester.pump();
  });

  test('el revert del switch no pisa lo que llegó por el socket', () {
    // El Samsung va por /tv/power?tv=…, no por /devices/:id/state, así que el
    // optimismo de su card lo aplica el inventario a mano. Si el comando falla
    // mientras tanto pudo llegar un device:state-changed con datos nuevos.
    final devices = _devices([
      _samsung(_televisorDevice, _televisorName, on: true),
    ]);
    final prev = devices.applyLocalOn(_televisorDevice, false)!;
    expect(prev.on, isTrue);

    // El PUT falla y se revierte, sin que nadie haya tocado nada en el medio.
    devices.restoreLocalOn(_televisorDevice, prev.on, prev.applied);
    expect(devices.byId(_televisorDevice)!.state.on, isTrue,
        reason: 'el `on` vuelve a donde estaba');
  });

  test('el revert NO pisa lo que llegó por el socket mientras tanto', () {
    final devices = _devices([
      _samsung(_televisorDevice, _televisorName, on: false),
    ]);
    final prev = devices.applyLocalOn(_televisorDevice, true)!;

    // Mientras el PUT viaja, alguien prende el aparato con el control físico y
    // el backend lo empuja por el socket.
    devices.debugApplyDeviceEvent(DeviceStateEvent(
      deviceId: _televisorDevice,
      state: const {'on': true, 'reachable': false},
    ));

    // El PUT falla: revertir a ciegas escribiría el `false` viejo encima.
    devices.restoreLocalOn(_televisorDevice, prev.on, prev.applied);

    expect(devices.byId(_televisorDevice)!.state.on, isTrue,
        reason: 'el estado que llegó por el socket es más fresco que el que '
            'este comando había escrito: el revert no puede pisarlo');
    expect(devices.byId(_televisorDevice)!.state.reachable, isFalse);
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
