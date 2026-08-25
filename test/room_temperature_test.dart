// Resolución de "qué temperatura corresponde a esta habitación"
// (RoomTemperature) + la elección de termómetro por room que la alimenta
// (TempSensorPrefs) + el badge del RoomCard que la muestra.
//
// El punto del helper es que la home y el detalle de la habitación no puedan
// divergir: ambos entran por RoomTemperature con la MISMA elección persistida.
// Estos tests fijan las tres reglas que hacen que coincidan — pool, fallback y
// prioridad del termostato — y la invariante de layout del RoomCard (el badge
// se acomoda dentro de kHeight, no la estira).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/room_ref.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/temp_sensor_prefs.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/utils/room_temperature.dart';

/// Termómetro: la lectura viaja en `sensor.temperature`.
Device thermometer(String id, {double? temp, double? humidity}) => Device(
      id: id,
      name: id,
      type: 'ZLLTemperature',
      state: DeviceState(),
      sensor: DeviceSensor(temperature: temp, humidity: humidity),
    );

/// Termostato: la lectura ambiente viaja en `state.currentTemp` (su `sensor`
/// es null).
Device thermostat(String id, {double? currentTemp}) => Device(
      id: id,
      name: id,
      type: 'thermostat',
      capabilities: const ['thermostat'],
      state: DeviceState(currentTemp: currentTemp, targetTemp: 23),
    );

Device bulb(String id) => Device(
      id: id,
      name: id,
      type: 'Extended color light',
      state: DeviceState(),
    );

/// Service sin red ni socket, sembrado con [devices].
DevicesService seeded(List<Device> devices) {
  final service = DevicesService(config: ServerConfig(), socket: SocketService());
  service.debugSeedDevices(devices);
  return service;
}

RoomRef room(String id, List<String> deviceIds) =>
    RoomRef(id: id, name: id, deviceIds: deviceIds);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoomTemperature.forRoom', () {
    test('room con termómetro devuelve su lectura', () {
      final service = seeded([thermometer('s1', temp: 22.5), bulb('l1')]);
      expect(
        RoomTemperature.forRoom(service, room('living', ['s1', 'l1'])),
        22.5,
      );
    });

    test('room SIN sensor de temperatura devuelve null (badge oculto)', () {
      final service = seeded([bulb('l1'), thermometer('s1', temp: 22.5)]);
      // 's1' existe en la casa pero NO pertenece a esta room.
      expect(RoomTemperature.forRoom(service, room('cuarto', ['l1'])), isNull);
    });

    test('termómetro que solo reporta humedad no cuenta como temperatura', () {
      final service = seeded([thermometer('s1', humidity: 48)]);
      expect(RoomTemperature.forRoom(service, room('baño', ['s1'])), isNull);
    });

    test('sin elección previa gana el PRIMER termómetro de la room', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermometer('s2', temp: 25.1),
      ]);
      expect(RoomTemperature.forRoom(service, room('cuarto', ['s1', 's2'])),
          19.8);
    });

    test('respeta el termómetro elegido por el usuario para esa room', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermometer('s2', temp: 25.1),
      ]);
      expect(
        RoomTemperature.forRoom(
          service,
          room('cuarto', ['s1', 's2']),
          selectedSensorId: 's2',
        ),
        25.1,
      );
    });

    test('elección que apunta a un sensor que ya no existe cae al primero', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermometer('s2', temp: 25.1),
      ]);
      expect(
        RoomTemperature.forRoom(
          service,
          room('cuarto', ['s1', 's2']),
          selectedSensorId: 'sensor_borrado',
        ),
        19.8,
      );
    });

    test('room con termostato: lectura unificada desde state.currentTemp', () {
      final service = seeded([thermostat('t1', currentTemp: 21.4)]);
      expect(RoomTemperature.forRoom(service, room('living', ['t1'])), 21.4);
    });

    test(
        'sin elección, el termostato de la room gana — es lo que muestra el '
        'header al abrirla', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermostat('t1', currentTemp: 21.4),
      ]);
      final living = room('living', ['s1', 't1']);
      // El header monta ThermostatHeaderCard en este caso: el badge tiene que
      // decir lo mismo que ese control, no la lectura del termómetro.
      expect(RoomTemperature.thermostat(service, living)?.id, 't1');
      expect(RoomTemperature.forRoom(service, living), 21.4);
    });

    test('si el usuario eligió el termómetro, el termostato deja de ganar', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermostat('t1', currentTemp: 21.4),
      ]);
      final living = room('living', ['s1', 't1']);
      expect(
        RoomTemperature.thermostat(service, living, selectedSensorId: 's1'),
        isNull,
      );
      expect(
        RoomTemperature.forRoom(service, living, selectedSensorId: 's1'),
        19.8,
      );
    });

    test('termostato sin lectura ambiente cae al termómetro de la room', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermostat('t1'), // currentTemp == null
      ]);
      expect(RoomTemperature.forRoom(service, room('living', ['s1', 't1'])),
          19.8);
    });

    test('scope "toda la casa" (room null) usa el pool completo', () {
      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermometer('s2', temp: 25.1),
      ]);
      expect(RoomTemperature.forRoom(service, null), 19.8);
      expect(RoomTemperature.forRoom(service, null, selectedSensorId: 's2'),
          25.1);
    });

    test('el pool pone los termómetros primero y los termostatos al final', () {
      final service = seeded([
        thermostat('t1', currentTemp: 21.4),
        thermometer('s1', temp: 19.8),
      ]);
      final ids = RoomTemperature.pool(service, room('living', ['s1', 't1']))
          .map((d) => d.id)
          .toList();
      expect(ids, ['s1', 't1']);
    });

    test('la lectura sigue a los eventos de sensor, sin refresh manual', () {
      final sensor = thermometer('s1', temp: 19.8);
      final service = seeded([sensor]);
      final living = room('cuarto', ['s1']);
      expect(RoomTemperature.forRoom(service, living), 19.8);
      // Lo que hace DevicesService al aplicar un WS device:state-changed.
      sensor.sensor = DeviceSensor(temperature: 20.6);
      expect(RoomTemperature.forRoom(service, living), 20.6);
    });
  });

  group('TempSensorPrefs', () {
    setUp(() => TempSensorPrefs.instance.debugReset());

    test('la key por room es la histórica del picker', () {
      expect(TempSensorPrefs.keyFor('living'), 'home.tempSensorId.living');
      // Toda la casa: la key sin sufijo que comparten phone y tablet.
      expect(TempSensorPrefs.keyFor(null), 'home.tempSensorId');
    });

    test('cachea la elección persistida de cada room', () async {
      SharedPreferences.setMockInitialValues({
        'home.tempSensorId': 's_casa',
        'home.tempSensorId.living': 's2',
        'otra.pref': 'no',
      });
      final prefs = TempSensorPrefs.instance;
      await prefs.ensureLoaded();

      expect(prefs.idFor('living'), 's2');
      expect(prefs.idFor(null), 's_casa');
      expect(prefs.idFor('cuarto'), isNull, reason: 'room sin elección');
    });

    test('elegir un termómetro notifica y persiste en la key de la room',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = TempSensorPrefs.instance;
      await prefs.ensureLoaded();

      var notificaciones = 0;
      void listener() => notificaciones++;
      prefs.addListener(listener);
      addTearDown(() => prefs.removeListener(listener));

      await prefs.select('living', 's2');
      expect(notificaciones, 1, reason: 'el badge de la home se entera');
      expect(prefs.idFor('living'), 's2');
      expect(
        (await SharedPreferences.getInstance())
            .getString('home.tempSensorId.living'),
        's2',
      );
    });

    test('la elección cacheada alimenta la resolución de la room', () async {
      SharedPreferences.setMockInitialValues(
          {'home.tempSensorId.cuarto': 's2'});
      final prefs = TempSensorPrefs.instance;
      await prefs.ensureLoaded();

      final service = seeded([
        thermometer('s1', temp: 19.8),
        thermometer('s2', temp: 25.1),
      ]);
      final cuarto = room('cuarto', ['s1', 's2']);
      expect(
        RoomTemperature.forRoom(
          service,
          cuarto,
          selectedSensorId: prefs.idFor(cuarto.id),
        ),
        25.1,
      );
    });
  });

  group('badge del RoomCard', () {
    Future<double> pumpCard(
      WidgetTester tester, {
      double? temperature,
      double? brightness,
      String title = 'Living',
      double width = 360,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: RoomCard(
                title: title,
                icon: const Icon(Icons.light),
                lightsOn: 1,
                lightsTotal: 3,
                anyOn: true,
                brightness: brightness,
                temperature: temperature,
                onTap: () {},
                onToggle: (_) {},
              ),
            ),
          ),
        ),
      ));
      return tester.getSize(find.byType(RoomCard)).height;
    }

    testWidgets('el badge NO altera la altura uniforme de la card',
        (tester) async {
      final sinBadge = await pumpCard(tester);
      final conBadge = await pumpCard(tester, temperature: 22.5);
      final sinBadgeSlider = await pumpCard(tester, brightness: 0.5);
      final conBadgeSlider =
          await pumpCard(tester, temperature: 22.5, brightness: 0.5);

      expect(conBadge, sinBadge);
      expect(conBadgeSlider, sinBadgeSlider);
      // La altura es única (con slider y sin él): la lista no debe "saltar".
      expect(conBadge, sinBadgeSlider);

      // …y el badge vive DENTRO de esa caja: si la estirara (o se recortara),
      // el Row habría desbordado y este pump ya habría explotado.
      await pumpCard(tester, temperature: 22.5);
      final card = tester.getRect(find.byType(RoomCard));
      final badge = tester.getRect(find.text('22.5°'));
      expect(badge.top, greaterThanOrEqualTo(card.top));
      expect(badge.bottom, lessThanOrEqualTo(card.bottom));
    });

    testWidgets('sin temperatura no se renderiza nada', (tester) async {
      await pumpCard(tester);
      expect(find.textContaining('°'), findsNothing);
    });

    testWidgets('muestra la lectura con un decimal', (tester) async {
      await pumpCard(tester, temperature: 22.5);
      expect(find.text('22.5°'), findsOneWidget);
    });

    testWidgets('un nombre largo trunca el título, nunca el badge',
        (tester) async {
      // Peor caso: nombre interminable + lectura de 6 caracteres en la card
      // más angosta (phone chico).
      await pumpCard(
        tester,
        temperature: -10.5,
        title: 'Habitación de huéspedes del fondo a la izquierda',
        width: 320,
      );
      expect(tester.takeException(), isNull, reason: 'sin overflow del Row');

      final badge = find.text('-10.5°');
      expect(badge, findsOneWidget);
      final titulo =
          tester.widget<Text>(find.text('Habitación de huéspedes del fondo a la izquierda'));
      expect(titulo.overflow, TextOverflow.ellipsis);
      expect(titulo.maxLines, 1);
      // El badge entra completo: su ancho es el del texto sin recortar.
      final painter = TextPainter(
        text: TextSpan(
          text: '-10.5°',
          style: tester.widget<Text>(badge).style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(tester.getSize(badge).width,
          greaterThanOrEqualTo(painter.width - 0.5));
    });
  });
}
