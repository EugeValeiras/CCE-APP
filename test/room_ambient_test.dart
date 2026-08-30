// CCE#57: chips de sensores en las habitaciones SIN luces.
//
// Dos capas y una frontera: RoomAmbient decide QUÉ se muestra (y es puro:
// service + room → chips) y RoomCard decide CÓMO, sin saber de sensores. Los
// tests fijan esa frontera y las invariantes que el issue pide sostener: la
// card sigue midiendo 88, las filas CON luces no cambian, y el chip de
// temperatura respeta el termómetro elegido por el usuario.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/room_ref.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/theme/components/cce_switch.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/theme/components/sensor_chip.dart';
import 'package:cce_app/utils/room_ambient.dart';

Device thermometer(String id, {double? temp, double? humidity}) => Device(
      id: id,
      name: id,
      type: 'eWeLink Sensor',
      capabilities: const ['sensor'],
      state: DeviceState(),
      sensor: DeviceSensor(temperature: temp, humidity: humidity),
    );

Device contact(String id, {bool open = false}) => Device(
      id: id,
      name: id,
      type: 'eWeLink Contact Sensor',
      capabilities: const ['sensor', 'contact'],
      state: DeviceState(),
      sensor: DeviceSensor(contact: open, battery: '100'),
    );

Device motion(String id, {bool active = false}) => Device(
      id: id,
      name: id,
      type: 'eWeLink Motion Sensor',
      capabilities: const ['sensor', 'motion'],
      state: DeviceState(),
      sensor: DeviceSensor(motion: active, battery: '100'),
    );

/// Mando a pilas (el "Kitchen 4-Button" real: un aparato, cuatro teclas).
Device remote(String id, {int outlets = 1}) => Device(
      id: id,
      name: id,
      type: 'eWeLink Button',
      capabilities: const ['sensor', 'button'],
      state: DeviceState(),
      sensor: DeviceSensor(outlets: outlets, battery: '100'),
    );

/// Relé-pulsador de pared (ZBMINIR2 en detach): switch + button a la vez.
Device buttonRelay(String id) => Device(
      id: id,
      name: id,
      type: 'eWeLink Switch Button',
      capabilities: const ['switch', 'button'],
      state: DeviceState(),
    );

Device bulb(String id) => Device(
      id: id,
      name: id,
      type: 'Extended color light',
      capabilities: const ['switch', 'brightness'],
      state: DeviceState(),
    );

/// Dispositivo dedicado (JBL/TV). Con CCE#54 estos entran a `room.deviceIds`
/// de la habitación donde están ubicados: el helper tiene que ignorarlos.
Device speaker(String id) => Device(
      id: id,
      name: id,
      type: 'JBL Soundbar',
      capabilities: const ['volume', 'media_playback'],
      state: DeviceState(),
    );

DevicesService seeded(List<Device> devices) {
  final service =
      DevicesService(config: ServerConfig(), socket: SocketService());
  service.debugSeedDevices(devices);
  return service;
}

RoomRef room(String id, List<String> deviceIds) =>
    RoomRef(id: id, name: id, deviceIds: deviceIds);

List<String> labels(List<SensorChipData> chips) =>
    chips.map((c) => c.label).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoomAmbient.forRoom', () {
    test('Guest: termómetro con humedad ⇒ dos chips de lectura', () {
      final service = seeded([thermometer('s1', temp: 20.1, humidity: 34)]);
      expect(labels(RoomAmbient.forRoom(service, room('guest', ['s1']))),
          ['20.1°', '34%']);
    });

    test('Guest Bathroom: una puerta cerrada ⇒ un chip', () {
      final service = seeded([contact('c1')]);
      expect(labels(RoomAmbient.forRoom(service, room('baño', ['c1']))),
          ['Cerrada']);
    });

    test('Cocina: puerta + mando de 4 teclas ⇒ "Cerrada" y "1 mando"', () {
      final service = seeded([contact('c1'), remote('b1', outlets: 4)]);
      expect(
        labels(RoomAmbient.forRoom(service, room('cocina', ['c1', 'b1']))),
        ['Cerrada', '1 mando'],
      );
    });

    test('habitación sin sensores legibles ⇒ ningún chip', () {
      final service = seeded([bulb('l1')]);
      expect(RoomAmbient.forRoom(service, room('vacía', ['l1'])), isEmpty);
    });

    test('los devices dedicados (JBL/TV) no son sensores y se ignoran', () {
      // CCE#54 mete el parlante en deviceIds; el chip no tiene qué leerle.
      final service = seeded([speaker('dev_jbl'), contact('c1')]);
      expect(
        labels(RoomAmbient.forRoom(service, room('living', ['dev_jbl', 'c1']))),
        ['Cerrada'],
      );
    });

    test('sólo se leen los devices DE esta habitación', () {
      final service = seeded([contact('c1'), thermometer('s1', temp: 20.1)]);
      expect(labels(RoomAmbient.forRoom(service, room('baño', ['c1']))),
          ['Cerrada']);
    });

    group('contacto', () {
      test('abierta se anuncia en el naranja del StatusDot', () {
        final service = seeded([contact('c1', open: true)]);
        final chip = RoomAmbient.forRoom(service, room('hall', ['c1'])).single;
        expect(chip.label, 'Abierta');
        expect(chip.glyphColor, CceColors.contact);
      });

      test('cerrada no lleva color propio', () {
        final service = seeded([contact('c1')]);
        expect(
          RoomAmbient.forRoom(service, room('hall', ['c1'])).single.glyphColor,
          isNull,
        );
      });

      test('varias puertas se resumen en un solo chip', () {
        final service = seeded([contact('c1'), contact('c2'), contact('c3')]);
        final ids = ['c1', 'c2', 'c3'];
        expect(labels(RoomAmbient.forRoom(service, room('living', ids))),
            ['3 cerradas']);

        service.all.firstWhere((d) => d.id == 'c2').sensor =
            DeviceSensor(contact: true);
        expect(labels(RoomAmbient.forRoom(service, room('living', ids))),
            ['Abierta']);
      });
    });

    group('mandos', () {
      test('se cuentan aparatos, no teclas', () {
        final service = seeded([remote('b1', outlets: 4), remote('b2')]);
        expect(labels(RoomAmbient.forRoom(service, room('cocina', ['b1', 'b2']))),
            ['2 mandos']);
      });

      test('el relé-pulsador de pared NO es un mando', () {
        final service = seeded([buttonRelay('r1')]);
        expect(RoomAmbient.forRoom(service, room('cocina', ['r1'])), isEmpty);
      });
    });

    test('el movimiento aparece SÓLO cuando lo hay', () {
      final sensor = motion('m1');
      final service = seeded([sensor]);
      final pasillo = room('pasillo', ['m1']);
      expect(RoomAmbient.forRoom(service, pasillo), isEmpty);

      // Lo que hace DevicesService al aplicar un WS device:state-changed.
      sensor.sensor = DeviceSensor(motion: true);
      final chip = RoomAmbient.forRoom(service, pasillo).single;
      expect(chip.label, 'Movimiento');
      expect(chip.glyphColor, CceColors.motion);
    });

    test('el orden es por tipo de dato y no baila entre refrescos', () {
      final door = contact('c1');
      final service = seeded([remote('b1'), door, thermometer('s1', temp: 21.0)]);
      final ids = ['b1', 'c1', 's1'];
      expect(labels(RoomAmbient.forRoom(service, room('cocina', ids))),
          ['21.0°', 'Cerrada', '1 mando']);

      door.sensor = DeviceSensor(contact: true);
      expect(labels(RoomAmbient.forRoom(service, room('cocina', ids))),
          ['21.0°', 'Abierta', '1 mando']);
    });

    test('nunca más de maxChips por fila: el nombre no puede perder', () {
      final service = seeded([
        thermometer('s1', temp: 21.0, humidity: 40),
        contact('c1'),
        remote('b1'),
      ]);
      final chips =
          RoomAmbient.forRoom(service, room('todo', ['s1', 'c1', 'b1']));
      expect(chips.length, RoomAmbient.maxChips);
      expect(labels(chips), ['21.0°', '40%', 'Cerrada']);
    });

    group('elección de termómetro', () {
      test('el chip respeta el sensor elegido para esa habitación', () {
        final service = seeded([
          thermometer('s1', temp: 19.8, humidity: 30),
          thermometer('s2', temp: 25.1, humidity: 55),
        ]);
        final cuarto = room('cuarto', ['s1', 's2']);
        expect(labels(RoomAmbient.forRoom(service, cuarto)), ['19.8°', '30%']);
        expect(
          labels(RoomAmbient.forRoom(service, cuarto, selectedSensorId: 's2')),
          ['25.1°', '55%'],
        );
      });

      test('la humedad sale del MISMO aparato que la temperatura', () {
        // Si eligiera por su cuenta mostraría 19.8° con 55%: dos lecturas de
        // dos lugares distintos presentadas como una.
        final service = seeded([
          thermometer('s1', temp: 19.8, humidity: 30),
          thermometer('s2', temp: 25.1, humidity: 55),
        ]);
        final chips = RoomAmbient.forRoom(service, room('cuarto', ['s1', 's2']));
        expect(labels(chips), ['19.8°', '30%']);
      });

      test('un higrómetro sin temperatura igual aporta su humedad', () {
        final service = seeded([thermometer('s1', humidity: 61)]);
        expect(labels(RoomAmbient.forRoom(service, room('baño', ['s1']))),
            ['61%']);
      });
    });
  });

  group('RoomCard con chips', () {
    const chips = [
      SensorChipData(glyph: '', label: '20.1°'),
      SensorChipData(glyph: '', label: '34%'),
    ];

    Future<void> pumpCard(
      WidgetTester tester, {
      required int lightsTotal,
      List<SensorChipData> cardChips = chips,
      double? temperature,
      String title = 'Guest',
      double width = 360,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: RoomCard(
                  title: title,
                  icon: const Icon(Icons.light),
                  lightsOn: 0,
                  lightsTotal: lightsTotal,
                  anyOn: false,
                  temperature: temperature,
                  chips: cardChips,
                  onTap: () {},
                  onToggle: (_) {},
                ),
              ),
            ),
          ),
        ));

    testWidgets('sin luces muestra los chips y el chevron, no el switch',
        (tester) async {
      await pumpCard(tester, lightsTotal: 0);
      expect(find.byType(SensorChip), findsNWidgets(2));
      expect(find.text('20.1°'), findsOneWidget);
      expect(find.text('34%'), findsOneWidget);
      expect(find.byType(CceSwitch), findsNothing);
    });

    testWidgets('con luces la fila NO cambia: switch sí, chips no',
        (tester) async {
      await pumpCard(tester, lightsTotal: 3, temperature: 23.4);
      expect(find.byType(SensorChip), findsNothing);
      expect(find.byType(CceSwitch), findsOneWidget);
      // El badge de temperatura sigue en su lugar.
      expect(find.text('23.4°'), findsOneWidget);
    });

    testWidgets('la temperatura no se dice dos veces', (tester) async {
      // El call-site pasa las dos cosas (la card decide); con chips gana el
      // chip y el badge de la derecha no se dibuja.
      await pumpCard(tester, lightsTotal: 0, temperature: 20.1);
      expect(find.text('20.1°'), findsOneWidget);
    });

    testWidgets('la card mide 88 con chips, sin chips y con luces',
        (tester) async {
      // 88 = la altura única de la fila (padding 12 + contenido 44 + slider
      // 20 + 12). Los chips entran en el alto que ya estaba reservado.
      double height() => tester.getSize(find.byType(RoomCard)).height;

      await pumpCard(tester, lightsTotal: 0);
      expect(height(), 88);
      await pumpCard(tester, lightsTotal: 0, cardChips: const []);
      expect(height(), 88);
      await pumpCard(tester, lightsTotal: 3, temperature: 23.4);
      expect(height(), 88);
    });

    testWidgets('sin chips y sin luces la fila queda como estaba',
        (tester) async {
      // El badge vuelve a aparecer (y en su columna): una habitación sin
      // sensores legibles no debe quedar peor que antes del cambio.
      await pumpCard(tester,
          lightsTotal: 0, cardChips: const [], temperature: 20.7);
      expect(find.byType(SensorChip), findsNothing);
      expect(find.text('20.7°'), findsOneWidget);
    });

    testWidgets('un nombre largo trunca el título, los chips no desbordan',
        (tester) async {
      // Peor caso: nombre interminable + tres chips en la card más angosta.
      await pumpCard(
        tester,
        lightsTotal: 0,
        width: 300,
        title: 'Habitación de huéspedes del fondo a la izquierda',
        cardChips: const [
          SensorChipData(glyph: '', label: '20.1°'),
          SensorChipData(glyph: '', label: '34%'),
          SensorChipData(glyph: '', label: '2 mandos'),
        ],
      );
      // Un overflow habría hecho explotar el pump; además los chips viven
      // DENTRO de la caja de la card.
      final card = tester.getRect(find.byType(RoomCard));
      for (final chip in tester.widgetList(find.byType(SensorChip))) {
        final rect = tester.getRect(find.byWidget(chip));
        expect(rect.top, greaterThanOrEqualTo(card.top));
        expect(rect.bottom, lessThanOrEqualTo(card.bottom));
        expect(rect.right, lessThanOrEqualTo(card.right));
      }
    });
  });
}
