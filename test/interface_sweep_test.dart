// CCE#28: barrido de interfaz. Se prueban los CRITERIOS que el barrido fija,
// no los píxeles: que el historial nunca muestre un identificador crudo ni
// el latido del robot, que las medidas de componente nuevas sean las del
// issue (tile destacado 102, tile de luz 78, fila de evento 52) y que el
// metadato temporal de una automatización programada apunte al próximo
// disparo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/theme/components/cce_switch.dart';
import 'package:cce_app/theme/components/featured_tile.dart';
import 'package:cce_app/theme/components/light_card.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/theme/components/section_header.dart';
import 'package:cce_app/theme/components/status_badge.dart';
import 'package:cce_app/utils/time_format.dart';
import 'package:cce_app/views/alarm_view.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';
import 'package:cce_app/views/history/event_grouping.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/history_screen.dart';

int _seq = 0;

EventRecord _ev(String name, Map<String, dynamic> payload, {String? time}) {
  _seq++;
  return EventRecord(
    time: time ??
        '2026-08-27T15:${(59 - _seq ~/ 60).toString().padLeft(2, '0')}:'
            '${(59 - _seq % 60).toString().padLeft(2, '0')}.000Z',
    id: 'e$_seq',
    channel: 'websocket',
    eventName: name,
    payload: payload,
  );
}

/// Latido del robot tal cual lo graba el backend (27/08/2026): estado entero
/// cada ~20 s, misma actividad.
EventRecord _robot(String activity) => _ev('device:state-changed', {
      'deviceId': 'dev_robot',
      'state': {
        'vacuumActivity': activity,
        'fanSpeed': 'Max',
        'fanSpeeds': ['Quiet', 'Max'],
        'rooms': [
          {'id': '1', 'name': 'Kitchen', 'segmentId': 6},
        ],
        'cleanSummary': {'count': 46},
        'consumables': {'filter': 93},
      },
    });

EventRecord _temp(double t) => _ev('device:state-changed', {
      'deviceId': 'dev_thermo',
      'sensor': {'temperature': t},
    });

DevicesService _devices() =>
    DevicesService(config: ServerConfig(), socket: SocketService());

void main() {
  group('historial: telemetría del robot', () {
    final devices = _devices();

    test('el latido repetido se descarta y sobrevive el cambio de actividad',
        () {
      // Descendente (más nuevo primero), como llega del server.
      final items = [
        _robot('charging'),
        _temp(22.4),
        _robot('charging'),
        _robot('charging'),
        _temp(22.3),
        _robot('charging'), // ← acá empezó a cargar: es el hecho.
        _robot('returning'),
        _temp(22.1),
        _robot('cleaning'),
      ];
      final kept = stripRepeatedTelemetry(items, devices);
      final robot = kept.where((e) => e.payload?['deviceId'] == 'dev_robot');
      expect(
        robot.map((e) => e.payload!['state']['vacuumActivity']).toList(),
        ['charging', 'returning', 'cleaning'],
      );
      // Los demás aparatos no se tocan.
      expect(kept.where((e) => e.payload?['deviceId'] == 'dev_thermo').length,
          3);
      // Orden cronológico intacto (sigue descendente).
      for (var i = 1; i < kept.length; i++) {
        expect(kept[i - 1].timestamp.isAfter(kept[i].timestamp), isTrue);
      }
    });

    test('adyacentes con la misma actividad colapsan en una fila con ×N', () {
      final items = [_robot('charging'), _robot('charging'), _robot('charging')];
      final groups = groupEvents(items, devices);
      expect(groups.length, 1);
      expect(groups.first.count, 3);
      // Cambiar de actividad abre otro run.
      final mixed = [_robot('charging'), _robot('returning')];
      expect(groupEvents(mixed, devices).length, 2);
    });

    test('se presenta en castellano, nunca el eventName', () {
      final r = presentEvent(_robot('charging'), devices);
      expect(r.title, isNot(contains('device:')));
      expect(r.title, isNot(contains('Evento de')));
      expect(r.title.toLowerCase(), contains('cargando'));
    });
  });

  group('historial: nada crudo', () {
    final devices = _devices();

    test('un cambio de estado sin frase propia dice qué cambió, en castellano',
        () {
      final r = presentEvent(
        _ev('device:state-changed', {
          'deviceId': 'dev_x',
          'state': {'fanSpeed': 'Max', 'reachable': true},
        }),
        devices,
      );
      expect(r.title, isNot(contains('device:')));
      expect(r.title, contains('cambió de estado'));
      expect(r.subtitle, 'potencia');
    });

    test('un acuse de comando con timeout es un hecho; confirmado, no grita',
        () {
      final fail = presentEvent(
        _ev('device:command-result',
            {'deviceId': 'dev_x', 'status': 'timeout'}),
        devices,
      );
      expect(fail.color, CceColors.danger);
      expect(fail.title, isNot(contains('command-result')));
      final ok = presentEvent(
        _ev('device:command-result',
            {'deviceId': 'dev_x', 'status': 'confirmed'}),
        devices,
      );
      expect(ok.color, CceColors.textTertiary);
    });

    test('sólo cambió la conexión', () {
      final r = presentEvent(
        _ev('device:state-changed', {
          'deviceId': 'dev_x',
          'state': {'reachable': false},
        }),
        devices,
      );
      expect(r.title, contains('sin conexión'));
      expect(r.color, CceColors.danger);
    });

    test('un grupo dice desde cuándo, no un rango con la hora repetida', () {
      final a = _ev('device:state-changed', {
        'deviceId': 'dev_m',
        'sensor': {'motion': true},
      }, time: '2026-08-27T15:06:40.000Z');
      final b = _ev('device:state-changed', {
        'deviceId': 'dev_m',
        'sensor': {'motion': true},
      }, time: '2026-08-27T15:02:10.000Z');
      final g = groupEvents([a, b], devices).single;
      final r = presentGroup(g, devices);
      expect(r.subtitle, startsWith('desde '));
      expect(r.subtitle, contains(TimeFormat.hm(b.timestamp)));
    });

    test('el "sin movimiento" doble del sensor es una sola fila', () {
      final a = _ev('device:state-changed', {
        'deviceId': 'dev_m',
        'sensor': {'motion': false, 'battery': 'ok'},
      }, time: '2026-08-27T15:06:41.000Z');
      final b = _ev('device:state-changed', {
        'deviceId': 'dev_m',
        'sensor': {'motion': false},
      }, time: '2026-08-27T15:06:40.000Z');
      expect(groupEvents([a, b], devices).length, 1);
    });

    test('el acuse confirmado de un comando es eco; el timeout queda', () {
      final ok = _ev('device:command-result',
          {'deviceId': 'dev_x', 'status': 'confirmed'});
      final bad = _ev('device:command-result',
          {'deviceId': 'dev_x', 'status': 'timeout'});
      expect(isCommandEcho(ok), isTrue);
      expect(isCommandEcho(bad), isFalse);
      expect(stripRepeatedTelemetry([ok, bad], devices), [bad]);
    });
  });

  group('automatizaciones: próxima ejecución', () {
    AutomationTrigger trigger(Map<String, dynamic> raw) =>
        AutomationTrigger.fromJson(raw);
    // Jueves 27/08/2026 12:00 local.
    final now = DateTime(2026, 8, 27, 12, 0);

    test('hoy si la hora no pasó, mañana si ya pasó', () {
      final t = trigger({'type': 'schedule', 'time': '19:04'});
      expect(nextScheduleRun(t, now: now), DateTime(2026, 8, 27, 19, 4));
      final early = trigger({'type': 'schedule', 'time': '02:00'});
      expect(nextScheduleRun(early, now: now), DateTime(2026, 8, 28, 2, 0));
    });

    test('respeta los días (0=dom..6=sáb)', () {
      // Sólo sábado (6) y domingo (0): desde un jueves, el próximo es sábado.
      final t = trigger({
        'type': 'schedule',
        'time': '07:30',
        'days': [6, 0],
      });
      final next = nextScheduleRun(t, now: now)!;
      expect(next.weekday, DateTime.saturday);
      expect(next.hour, 7);
    });

    test('intervalos, sensores y manuales no tienen próxima', () {
      expect(
        nextScheduleRun(
          trigger({'type': 'schedule', 'scheduleMode': 'interval'}),
          now: now,
        ),
        isNull,
      );
      expect(nextScheduleRun(trigger({'type': 'sensor'}), now: now), isNull);
      expect(nextScheduleRun(trigger({'type': 'manual'}), now: now), isNull);
    });

    test('las frases temporales', () {
      expect(TimeFormat.upcoming(DateTime(2026, 8, 27, 19, 4), now: now),
          'hoy 19:04');
      expect(TimeFormat.upcoming(DateTime(2026, 8, 28, 2, 0), now: now),
          'mañana 02:00');
      expect(TimeFormat.since(DateTime(2026, 8, 27, 8, 2), now: now),
          'desde las 08:02');
      expect(TimeFormat.since(DateTime(2026, 8, 26, 22, 14), now: now),
          'desde ayer 22:14');
      expect(
          TimeFormat.relativeInSentence(DateTime(2026, 8, 27, 8, 2),
              now: now),
          'a las 08:02');
      expect(
          TimeFormat.relativeInSentence(DateTime(2026, 8, 27, 11, 48),
              now: now),
          'hace 12 min');
    });
  });

  group('alarma: qué protege', () {
    Device sensor(String id, String type, {bool? contact, bool? motion,
        int? trigTime}) =>
        Device(
          id: id,
          name: id,
          type: type,
          state: DeviceState(),
          sensor: DeviceSensor(
              contact: contact, motion: motion, trigTime: trigTime),
        );

    test('aperturas abiertas primero, después cerradas, después movimiento',
        () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final list = protectedSensors([
        sensor('Office movement', 'motion', motion: false,
            trigTime: now - 36 * 60000),
        sensor('Puerta de entrada', 'contact', contact: false),
        sensor('Living movement', 'motion', motion: false,
            trigTime: now - 2 * 60000),
        sensor('Ventana del Living', 'contact', contact: true),
        sensor('Termómetro', 'thermometer'),
        Device(
            id: 'oculto', name: 'oculto', type: 'contact', hidden: true,
            state: DeviceState(), sensor: DeviceSensor(contact: true)),
      ]);
      expect(list.map((d) => d.id).toList(), [
        'Ventana del Living', // abierta: lo que va a disparar la alarma
        'Puerta de entrada',
        'Living movement', // el más reciente
        'Office movement',
      ]);
    });
  });

  group('medidas de componente del barrido', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 179, child: child)),
            ),
          ),
        );

    testWidgets('el tile destacado mide 102 con cualquier control',
        (tester) async {
      await pump(
        tester,
        FeaturedTile(
          glyph: const Icon(Icons.tv),
          glyphColor: CceColors.accent,
          title: 'JBL BAR 1000MK2',
          subtitle: 'En espera',
          dotColor: CceColors.textTertiary,
          control: CceSwitch(value: false, onChanged: (_) {}),
        ),
      );
      expect(tester.getSize(find.byType(FeaturedTile)).height,
          FeaturedTile.kHeight);
      expect(FeaturedTile.kHeight, 102);

      await pump(
        tester,
        FeaturedTile(
          glyph: const Icon(Icons.play_arrow),
          glyphColor: CceColors.accent,
          title: 'Roborock Qrevo',
          subtitle: 'Cargando · 100%',
          control: FeaturedTileAction(svg: '<svg/>', onTap: () {}),
        ),
      );
      expect(tester.getSize(find.byType(FeaturedTile)).height, 102);
    });

    testWidgets('el tile compacto de luz mide 86 y muestra el nombre entero',
        (tester) async {
      await pump(
        tester,
        LightCard(
          name: 'Front 3 DOWN',
          iconBuilder: (c) => Icon(Icons.light, color: c),
          on: false,
          compact: true,
          onToggle: (_) {},
        ),
      );
      expect(tester.getSize(find.byType(LightCard)).height,
          LightCard.kCompactHeight);
      // 14 + 30 + 6 + 22 + 14: el dueño pidió el aire (feedback del PR #22).
      expect(LightCard.kCompactHeight, 86);
      expect(find.text('Front 3 DOWN'), findsOneWidget);
      // Sin "Apagada": el switch ya lo dice.
      expect(find.text('Apagada'), findsNothing);
    });

    testWidgets('RoomCard sin luces: el riel del switch, vacío (CCE#59)',
        (tester) async {
      Future<void> pumpRoom({required int lightsTotal, bool enabled = true}) =>
          tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: RoomCard(
                    title: 'Cocina',
                    icon: const Icon(Icons.light),
                    lightsOn: 0,
                    lightsTotal: lightsTotal,
                    anyOn: false,
                    temperature: 20.7,
                    toggleEnabled: enabled,
                    onTap: () {},
                    onToggle: (_) {},
                  ),
                ),
              ),
            ),
          ));

      await pumpRoom(lightsTotal: 3);
      expect(find.byType(CceSwitch), findsOneWidget);
      expect(find.byType(CceSwitchEmptyTrack), findsNothing);
      final withSwitch = tester.getRect(find.byType(CceSwitch));
      final badge = tester.getRect(find.text('20.7°'));

      await pumpRoom(lightsTotal: 0);
      expect(find.byType(CceSwitch), findsNothing);
      // La silueta de la fila NO cambia: el riel vacío ocupa el rectángulo
      // exacto del switch de la fila de arriba, y el badge no se corre.
      expect(tester.getRect(find.byType(CceSwitchEmptyTrack)), withSwitch);
      expect(tester.getRect(find.text('20.7°')), badge);

      // Bloqueado momentáneamente ≠ sin luces: ahí el control sigue.
      await pumpRoom(lightsTotal: 3, enabled: false);
      expect(find.byType(CceSwitch), findsOneWidget);
      expect(find.byType(CceSwitchEmptyTrack), findsNothing);
    });

    testWidgets('RoomCard sin estado centra el nombre; con badges no',
        (tester) async {
      Future<void> pumpRoom({required bool anyOn, bool motion = false}) =>
          tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: RoomCard(
                    title: 'Living',
                    icon: const Icon(Icons.light),
                    lightsOn: anyOn ? 1 : 0,
                    lightsTotal: 3,
                    anyOn: anyOn,
                    motion: motion,
                    onTap: () {},
                    onToggle: (_) {},
                  ),
                ),
              ),
            ),
          ));

      await pumpRoom(anyOn: false);
      final card = tester.getRect(find.byType(RoomCard));
      final title = tester.getRect(find.text('Living'));
      expect(title.center.dy, closeTo(card.center.dy, 1.0));
      expect(find.byType(StatusBadge), findsNothing);

      // Dos estados activos: dos badges, cada uno con lo suyo (CCE#63 — antes
      // acá había dos puntos mudos y el texto se vaciaba).
      await pumpRoom(anyOn: true, motion: true);
      expect(find.byType(StatusBadge), findsNWidgets(2));
      expect(tester.getRect(find.text('Living')).center.dy,
          lessThan(card.center.dy));
    });

    testWidgets('la fila del historial mide 52', (tester) async {
      final devices = _devices();
      final g = groupEvents([_temp(22.4)], devices).single;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EventRow(
            group: g,
            devices: devices,
            expanded: false,
            onToggleExpand: () {},
          ),
        ),
      ));
      // Alto de la fila + hairline inferior.
      expect(tester.getSize(find.byType(EventRow)).height,
          EventRow.kHeight + 1);
      expect(EventRow.kHeight, 52);
    });

    testWidgets('el encabezado de sección lleva el contador a la derecha',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SectionHeader(
              title: 'Habitaciones', counter: '3 de 8 encendidas'),
        ),
      ));
      expect(find.text('HABITACIONES'), findsOneWidget);
      expect(find.text('3 DE 8 ENCENDIDAS'), findsOneWidget);
    });
  });
}
