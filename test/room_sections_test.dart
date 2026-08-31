// CCE#67: el detalle de la habitación separa lo que se OPERA de lo que se LEE.
//
// Antes había UNA grilla llamada "Dispositivos" que nació como "Sensores" y se
// le fueron colgando aparatos: una puerta que sólo informa quedaba al lado de
// un televisor que se comanda, dibujados igual. Lo que fijan estos tests:
//
//   1. Son dos secciones distintas — "Dispositivos" (TV, JBL) y "Sensores"
//      (puertas, movimiento, botones) — y cada una se auto-oculta sin
//      elementos.
//   2. El termostato y la aspiradora NO son tiles de ninguna lista: viven en el
//      header (clima con +/−) y en "Limpiar esta habitación".
//   3. El orden de secciones guardado por la versión anterior (tres claves) no
//      valida contra las cuatro de ahora: cae al default y la pantalla se
//      dibuja igual, sin perder ninguna sección.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/room_ref.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/jbl_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/tv_service.dart';
import 'package:cce_app/theme/components/section_header.dart';
import 'package:cce_app/views/room_detail_screen.dart';
import 'package:cce_app/widgets/media_device_tile.dart';
import 'package:cce_app/widgets/sensor_tile.dart';
import 'package:cce_app/widgets/thermostat_tile.dart';
import 'package:cce_app/widgets/vacuum_tile.dart';

Device _bulb(String id) => Device(
      id: id,
      name: id,
      type: 'Extended color light',
      state: DeviceState(on: true, bri: 200),
    );

/// Samsung tal cual lo trae /devices/merged: `type: 'tv'` + capabilities de AV.
Device _tv(String id, String name) => Device(
      id: id,
      name: name,
      type: 'tv',
      capabilities: const ['volume', 'media_playback'],
      state: DeviceState(on: true, reachable: true),
    );

/// Barra JBL: `type: 'speaker'`.
Device _jbl(String id, String name) => Device(
      id: id,
      name: name,
      type: 'speaker',
      capabilities: const ['volume', 'media_playback'],
      state: DeviceState(on: false, reachable: true),
    );

Device _contact(String id) => Device(
      id: id,
      name: id,
      type: 'ZLLContact',
      state: DeviceState(),
      sensor: DeviceSensor(contact: false),
    );

Device _motion(String id) => Device(
      id: id,
      name: id,
      type: 'ZLLPresence',
      state: DeviceState(),
      sensor: DeviceSensor(motion: false),
    );

Device _thermostat(String id) => Device(
      id: id,
      name: id,
      type: 'thermostat',
      capabilities: const ['thermostat'],
      state: DeviceState(currentTemp: 22, targetTemp: 23),
    );

Device _vacuum(String id) => Device(
      id: id,
      name: id,
      type: 'vacuum',
      capabilities: const ['vacuum'],
      state: DeviceState(vacuumActivity: 'docked'),
    );

/// El Living de la casa: luces, un Samsung, la barra, dos sensores y un botón,
/// más el termostato y el robot que YA NO deberían salir en ninguna grilla.
const _livingIds = [
  'l1',
  'l2',
  'dev_tv',
  'dev_jbl',
  'contacto',
  'movimiento',
  'dev_thermostat',
  'dev_robot',
];

List<Device> _house() => [
      _bulb('l1'),
      _bulb('l2'),
      _tv('dev_tv', '65" OLED'),
      _jbl('dev_jbl', 'JBL Bar'),
      _contact('contacto'),
      _motion('movimiento'),
      _thermostat('dev_thermostat'),
      _vacuum('dev_robot'),
    ];

DevicesService _seeded(List<Device> devices) {
  final service =
      DevicesService(config: ServerConfig(), socket: SocketService());
  service.debugSeedDevices(devices);
  return service;
}

/// Monta el detalle con los services dedicados (sin red: ninguno arranca
/// polling) y espera a que `_loadOrder` resuelva de SharedPreferences.
///
/// La ventana es ALTA a propósito: el contenido son slivers perezosos, así que
/// en una pantalla de teléfono las secciones de abajo ni se construyen y un
/// `findsNothing` no probaría nada.
Future<DevicesService> _pumpRoom(
  WidgetTester tester, {
  required List<Device> house,
  required List<String> deviceIds,
  bool withMedia = true,
}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final service = _seeded(house);
  final socket = SocketService();
  await tester.pumpWidget(MaterialApp(
    home: RoomDetailScreen(
      title: 'Living',
      deviceIds: deviceIds,
      service: service,
      room: RoomRef(id: 'living', name: 'Living', deviceIds: deviceIds),
      tv: withMedia ? TvService(config: ServerConfig(), socket: socket) : null,
      jbl: withMedia ? JblService(config: ServerConfig(), socket: socket) : null,
    ),
  ));
  await tester.pump();
  await tester.pump();
  return service;
}

Finder _header(String title) => find.byWidgetPredicate(
    (w) => w is SectionHeader && w.title == title,
    description: 'SectionHeader("$title")');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('el Living separa Dispositivos de Sensores', (tester) async {
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    expect(_header('Luces'), findsOneWidget);
    expect(_header('Dispositivos'), findsOneWidget);
    expect(_header('Sensores'), findsOneWidget);

    // Lo que se opera: el Samsung y la barra, uno por aparato.
    expect(find.byType(TvDeviceTile), findsOneWidget);
    expect(find.byType(JblDeviceTile), findsOneWidget);
    // Lo que se lee: contacto y movimiento, y NADA más.
    expect(find.byType(SensorTile), findsNWidgets(2));

    // "Dispositivos" va antes que "Sensores" en el orden por defecto: primero
    // lo que se comanda, después lo que informa.
    expect(tester.getTopLeft(_header('Dispositivos')).dy,
        lessThan(tester.getTopLeft(_header('Sensores')).dy));
  });

  testWidgets('el termostato y la aspiradora no son tiles de ninguna grilla',
      (tester) async {
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    expect(find.byType(ThermostatTile), findsNothing,
        reason: 'el termostato vive en el header de clima, con +/−');
    expect(find.byType(VacuumTile), findsNothing,
        reason: 'el robot vive en "Limpiar esta habitación"');
  });

  testWidgets('una habitación sin TV ni JBL no dibuja Dispositivos',
      (tester) async {
    // Guest: una luz y una puerta.
    await _pumpRoom(tester,
        house: [_bulb('l1'), _contact('puerta')],
        deviceIds: ['l1', 'puerta']);

    expect(_header('Luces'), findsOneWidget);
    expect(_header('Sensores'), findsOneWidget);
    expect(_header('Dispositivos'), findsNothing);
  });

  testWidgets('una habitación sin sensores no dibuja Sensores',
      (tester) async {
    await _pumpRoom(tester,
        house: [_bulb('l1'), _tv('dev_tv', '65" OLED')],
        deviceIds: ['l1', 'dev_tv']);

    expect(_header('Dispositivos'), findsOneWidget);
    expect(_header('Sensores'), findsNothing);
  });

  testWidgets('sin los services de TV/JBL los aparatos no arman la sección',
      (tester) async {
    // La pantalla se puede montar sin TvService/JblService (vistas sin sala):
    // sin ellos no hay tile que dibujar, así que tampoco sección.
    await _pumpRoom(tester,
        house: _house(), deviceIds: _livingIds, withMedia: false);

    expect(_header('Dispositivos'), findsNothing);
    expect(_header('Sensores'), findsOneWidget);
  });

  testWidgets('un orden de secciones viejo (3 claves) cae al default',
      (tester) async {
    // Lo que quedó guardado por la versión anterior, con la sección mezclada
    // arriba de todo. Tiene tres claves: ya no valida.
    SharedPreferences.setMockInitialValues({
      'room.sectionOrder': ['sensors', 'lights', 'scenes'],
    });
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    // Ninguna sección se pierde y el orden es el nuevo default.
    expect(_header('Luces'), findsOneWidget);
    expect(_header('Dispositivos'), findsOneWidget);
    expect(_header('Sensores'), findsOneWidget);
    expect(tester.getTopLeft(_header('Luces')).dy,
        lessThan(tester.getTopLeft(_header('Dispositivos')).dy));
  });

  testWidgets('un orden de secciones de 4 claves sí se respeta',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'room.sectionOrder': ['sensors', 'devices', 'lights', 'scenes'],
    });
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    expect(tester.getTopLeft(_header('Sensores')).dy,
        lessThan(tester.getTopLeft(_header('Dispositivos')).dy));
    expect(tester.getTopLeft(_header('Dispositivos')).dy,
        lessThan(tester.getTopLeft(_header('Luces')).dy));
  });

  testWidgets('el menú de secciones ofrece las cuatro', (tester) async {
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reordenar secciones'));
    await tester.pumpAndSettle();

    // Sin la nueva en la lista, "Dispositivos" no se podría mover.
    for (final label in ['Escenas', 'Luces', 'Dispositivos', 'Sensores']) {
      expect(find.text(label), findsOneWidget, reason: 'falta $label');
    }
  });

  testWidgets('Dispositivos se puede reordenar como Luces y Sensores',
      (tester) async {
    // Ya no van "de prestado" al final de la grilla de sensores: tienen su
    // propia sección y su propio orden persistido.
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reordenar elementos'));
    await tester.pumpAndSettle();

    // Dentro del sheet: los SectionHeader de la pantalla de atrás también
    // dicen "LUCES" y compañía.
    Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet), matching: find.text(text));
    expect(inSheet('LUCES'), findsOneWidget);
    expect(inSheet('DISPOSITIVOS'), findsOneWidget);
    expect(inSheet('SENSORES'), findsOneWidget);
    // El Samsung y la barra son filas arrastrables de "Dispositivos".
    expect(inSheet('65" OLED'), findsOneWidget);
    expect(inSheet('JBL Bar'), findsOneWidget);
    // El termostato y el robot no se reordenan: no están en ninguna lista.
    expect(inSheet('dev_thermostat'), findsNothing);
    expect(inSheet('dev_robot'), findsNothing);
  });

  testWidgets('el sensorOrder viejo con ids de TV/JBL no rompe el orden',
      (tester) async {
    // Así quedó la clave cuando la grilla era una sola: primero un sensor,
    // después los aparatos que ahora viven en otra sección.
    SharedPreferences.setMockInitialValues({
      'room.living.sensorOrder': ['movimiento', 'dev_tv', 'dev_jbl', 'contacto'],
    });
    await _pumpRoom(tester, house: _house(), deviceIds: _livingIds);

    // Los ids que ya no son sensores se ignoran; los que sí, mandan.
    final tiles = tester.widgetList<SensorTile>(find.byType(SensorTile));
    expect(tiles.map((t) => t.device.id).toList(), ['movimiento', 'contacto']);
  });
}
