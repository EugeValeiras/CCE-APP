// CCE#112: el detalle de un sensor con lux. La fila del historial es una
// función pura (sensor_event_row.dart) y el metric well se prueba renderizado:
// el screen no tenía ninguna cobertura y la vuelta anterior lo encontró roto
// dos veces.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_icons.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/views/sensor_detail_screen.dart';
import 'package:cce_app/views/sensor_event_row.dart';

const pasillo = 'dev_a4c13819aaa6ffff';

EventRecord ev(Map<String, dynamic> sensor) => EventRecord(
      time: '2026-09-05T12:05:00.000Z',
      id: 'x',
      channel: 'internal',
      eventName: 'device:state-changed',
      globalId: pasillo,
      payload: {'deviceId': pasillo, 'sensor': sensor},
    );

const motionSpec = SensorEventRowSpec(
  activeLabel: 'Movimiento',
  idleLabel: 'Sin movimiento',
  activeGlyph: CceIcons.personStanding,
  idleGlyph: CceIcons.footprints,
  activeColor: CceColors.motion,
);

Device pr2({int? lux, String? brightness}) => Device.fromJson({
      'id': pasillo,
      'name': 'Movimiento pasillo',
      'type': 'eWeLink Motion Sensor',
      'capabilities': ['sensor', 'motion', 'illuminance'],
      'state': {'on': false, 'bri': 1, 'reachable': true},
      'sensor': {
        'battery': '100',
        'motion': false,
        'lux': ?lux,
        'brightness': ?brightness,
      },
    });

void main() {
  group('la fila del historial (sensorEventRow)', () {
    test('movimiento con lux acumulado dice las dos cosas', () {
      final r = sensorEventRow(ev({'motion': false, 'lux': 17, 'brightness': 'darker'}), isContact: false, spec: motionSpec);
      expect(r.label, 'Sin movimiento · 17 lx');
      expect(r.glyph, CceIcons.footprints);
      expect(r.active, isFalse);
    });

    test('movimiento activo sin lux: como siempre', () {
      final r = sensorEventRow(ev({'motion': true}), isContact: false, spec: motionSpec);
      expect(r.label, 'Movimiento');
      expect(r.glyph, CceIcons.personStanding);
      expect(r.active, isTrue);
      expect(r.color, CceColors.motion);
    });

    test('una lectura de luz sola: el valor y el glifo de luz, no las huellas', () {
      final r = sensorEventRow(ev({'lux': 300, 'brightness': 'brighter'}), isContact: false, spec: motionSpec);
      expect(r.label, '300 lx');
      expect(r.glyph, CceIcons.sunMedium);
      expect(r.active, isFalse);
    });

    test('sin nada reconocible: «Actualización»', () {
      final r = sensorEventRow(ev({'battery': '100'}), isContact: false, spec: motionSpec);
      expect(r.label, 'Actualización');
      expect(r.glyph, CceIcons.footprints);
    });

    test('un contacto lee contact, no motion', () {
      const spec = SensorEventRowSpec(
        activeLabel: 'Abierta',
        idleLabel: 'Cerrada',
        activeGlyph: CceIcons.doorOpen,
        idleGlyph: CceIcons.doorClosed,
        activeColor: CceColors.contact,
      );
      final r = sensorEventRow(ev({'contact': true, 'motion': false}), isContact: true, spec: spec);
      expect(r.label, 'Abierta');
      expect(r.active, isTrue);
    });
  });

  group('el metric well del detalle', () {
    Future<void> pump(WidgetTester tester, Device d) async {
      final service = DevicesService(
        config: ServerConfig(host: '127.0.0.1', port: 1),
        socket: SocketService(),
      );
      service.debugSeedDevices([d]);
      await tester.pumpWidget(MaterialApp(home: SensorDetailScreen(device: d, service: service)));
      await tester.pump();
    }

    testWidgets('con lux y binario: «17 lx» con el rótulo OSCURO', (tester) async {
      await pump(tester, pr2(lux: 17, brightness: 'darker'));
      expect(find.text('17 lx'), findsOneWidget);
      expect(find.text('OSCURO'), findsOneWidget);
      expect(find.text('AMBIENTE'), findsNothing);
    });

    testWidgets('con lux y sin binario: el rótulo es LUZ, no OSCURO sobre 800 lx', (tester) async {
      await pump(tester, pr2(lux: 800));
      expect(find.text('800 lx'), findsOneWidget);
      expect(find.text('LUZ'), findsOneWidget);
      expect(find.text('OSCURO'), findsNothing);
    });

    testWidgets('sin lux (el 03P viejo): el binario de siempre', (tester) async {
      await pump(tester, pr2(brightness: 'brighter'));
      expect(find.text('Con luz'), findsOneWidget);
      expect(find.text('AMBIENTE'), findsOneWidget);
      expect(find.textContaining(' lx'), findsNothing);
    });
  });
}
