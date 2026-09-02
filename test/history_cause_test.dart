// CCE#75 — el historial cuenta HECHOS, no síntomas.
//
// El caso que originó el issue: prender el Hall dejaba doce filas en el
// historial (4 luces × 3 propiedades), todas a la misma hora, y ninguna decía
// quién lo había pedido. Los eventos de acá calcan la forma real que manda el
// backend, incluido el doble reporte de los aparatos con dos bindings
// (hue + matter), que es lo que multiplicaba las filas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/light_group.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/utils/time_format.dart';
import 'package:cce_app/views/history/actor_labels.dart';
import 'package:cce_app/views/history/cause_grouping.dart';
import 'package:cce_app/views/history/event_grouping.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/history_screen.dart';

const _kAutoId = 'auto_mq85ppkv1jqiphvn3fj';
const _kAutoName = 'Prender Living con Living Movimiento';

/// Base de tiempos: los eventos se declaran con un offset en milisegundos.
final _t0 = DateTime.utc(2026, 9, 1, 22, 35, 0);

EventRecord _ev(
  Map<String, dynamic> payload, {
  required int ms,
  String eventName = 'device:state-changed',
}) {
  final t = _t0.add(Duration(milliseconds: ms));
  return EventRecord(
    time: t.toIso8601String(),
    id: 'e$ms-${payload['deviceId']}-${payload.hashCode}',
    channel: 'websocket',
    eventName: eventName,
    source: 'external',
    globalId: payload['deviceId'] as String?,
    provider: null,
    payload: payload,
  );
}

/// Cambio de estado de una luz, con o sin causa.
EventRecord _luz(
  String deviceId,
  Map<String, dynamic> state, {
  required int ms,
  String? correlationId,
  String? actor,
}) =>
    _ev({
      'deviceId': deviceId,
      'state': state,
      'correlationId': ?correlationId,
      'actor': ?actor,
    }, ms: ms);

Device _luzDevice(String id, String name) => Device(
      id: id,
      name: name,
      type: 'light',
      state: DeviceState(),
      capabilities: const ['switch', 'brightness', 'color_temperature'],
    );

DevicesService _devices() {
  final d = DevicesService(config: ServerConfig(), socket: SocketService());
  d.debugSeedDevices([
    for (var i = 1; i <= 4; i++) _luzDevice('dev_h$i', 'Hall $i'),
    _luzDevice('dev_liv', 'Living'),
  ]);
  d.debugSeedConfigNames(automationNames: {_kAutoId: _kAutoName});
  return d;
}

/// El hecho completo del issue: un comando de grupo prendió las cuatro luces
/// del Hall al 56%, y cada una reportó por sus DOS bindings.
///
/// Doce eventos, descendentes como llegan del server:
///   - por luz: el eco del binding que comandó (con causa) y dos del hermano
///     (sin causa: el registry sólo puede etiquetar el que cerró la
///     expectativa — límite conocido de CCE#74).
List<EventRecord> _hallPrendido() {
  final out = <EventRecord>[];
  for (var i = 4; i >= 1; i--) {
    final id = 'dev_h$i';
    final base = i * 100;
    out.add(_luz(id, {'ct': 366}, ms: base + 60));
    out.add(_luz(id, {'bri': 143}, ms: base + 30));
    out.add(_luz(
      id,
      {'on': true, 'bri': 143},
      ms: base,
      correlationId: 'corr-hall',
      actor: 'automation:$_kAutoId',
    ));
  }
  out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return out;
}

List<CauseGroup> _hechos(List<EventRecord> items, DevicesService devices) =>
    groupByCause(groupEvents(items, devices), devices);

void main() {
  group('CCE#75 · un comando es un hecho', () {
    test('las doce filas del Hall son UNA, con las cuatro luces y su causa',
        () {
      final devices = _devices();
      final items = _hallPrendido();
      expect(items.length, 12);

      final hechos = _hechos(items, devices);
      expect(hechos.length, 1, reason: 'un comando, una fila');
      final h = hechos.single;
      expect(h.deviceCount, 4);
      expect(h.correlationId, 'corr-hall');
      expect(h.actor, 'automation:$_kAutoId');
      // Nada se pierde: la fila despliega los doce cambios individuales.
      expect(h.eventCount, 12);
      expect(h.events.length, 12);
      expect(h.expandable, isTrue);
    });

    test('la fila dice qué pasó y con qué brillo', () {
      final devices = _devices();
      final h = _hechos(_hallPrendido(), devices).single;
      final r = presentCause(h, devices);
      // «Hall» sale del prefijo común de Hall 1..4, no de un id.
      expect(r.title, 'Hall se encendió');
      expect(r.subtitle, 'al 56%');
      expect(r.title, isNot(contains('dev_')));
    });

    test('si el hecho cae justo sobre un grupo, lo nombra el grupo', () {
      final devices = _devices();
      devices.debugSeedConfigNames(
        groups: [
          LightGroup(
            id: 'g1',
            name: 'Hall',
            lightIds: const ['dev_h1', 'dev_h2', 'dev_h3', 'dev_h4'],
          ),
        ],
      );
      final h = _hechos(_hallPrendido(), devices).single;
      expect(causeSubject(h, devices).text, 'Hall');
    });

    test('dos causas distintas al mismo tiempo son dos hechos', () {
      final devices = _devices();
      final items = [
        _luz('dev_liv', {'on': false},
            ms: 200, correlationId: 'corr-b', actor: 'alexa'),
        _luz('dev_h1', {'on': true},
            ms: 100, correlationId: 'corr-a', actor: 'user:app'),
      ];
      final hechos = _hechos(items, devices);
      expect(hechos.length, 2);
      expect(hechos.map((h) => h.correlationId), ['corr-b', 'corr-a']);
    });

    test('el eco del binding hermano se absorbe sólo si el aparato ya está',
        () {
      final devices = _devices();
      final items = [
        // Un aparato que NO participó del comando y cambió al mismo tiempo:
        // es un hecho aparte, no se le cuelga la causa ajena.
        _luz('dev_liv', {'on': true}, ms: 300),
        // El eco hermano de una luz que SÍ está en el grupo.
        _luz('dev_h1', {'ct': 366}, ms: 200),
        _luz('dev_h1', {'on': true, 'bri': 143},
            ms: 100, correlationId: 'corr-x', actor: 'user:app'),
      ];
      final hechos = _hechos(items, devices);
      expect(hechos.length, 2);
      final conCausa = hechos.firstWhere((h) => h.correlationId == 'corr-x');
      expect(conCausa.eventCount, 2, reason: 'el hermano entra al hecho');
      expect(conCausa.deviceCount, 1);
      final solo = hechos.firstWhere((h) => h.correlationId == null);
      expect(solo.deviceIds, {'dev_liv'});
    });

    test('un eco lejano no se absorbe: pasados 2 s ya es otro hecho', () {
      final devices = _devices();
      final items = [
        _luz('dev_h1', {'ct': 366}, ms: 5000),
        _luz('dev_h1', {'on': true, 'bri': 143},
            ms: 0, correlationId: 'corr-x', actor: 'user:app'),
      ];
      expect(_hechos(items, devices).length, 2);
    });
  });

  group('CCE#75 · el fallback, que es todo el historial viejo', () {
    test('tres cambios del mismo aparato en el mismo instante son una línea',
        () {
      final devices = _devices();
      // Sin correlationId: exactamente lo que hay persistido de antes.
      final items = [
        _luz('dev_h4', {'ct': 366}, ms: 60),
        _luz('dev_h4', {'bri': 143}, ms: 30),
        _luz('dev_h4', {'on': true, 'bri': 143}, ms: 0),
      ];
      final hechos = _hechos(items, devices);
      expect(hechos.length, 1);
      expect(hechos.single.correlationId, isNull);
      expect(
        presentCause(hechos.single, devices).title,
        'Hall 4: se encendió · al 56% · temp. de color',
      );
    });

    test('encendió y apagó NO se juntan aunque caigan en la misma ventana', () {
      final devices = _devices();
      final items = [
        _luz('dev_h4', {'on': false}, ms: 1000),
        _luz('dev_h4', {'on': true}, ms: 0),
      ];
      expect(_hechos(items, devices).length, 2);
    });

    test('sin nombre común, el sujeto cuenta y el verbo concuerda', () {
      final devices = _devices();
      // El caso real del Living: «TV right light», «Living left»… no comparten
      // prefijo, así que el hecho se cuenta — y en plural.
      devices.debugSeedDevices([
        _luzDevice('dev_a', 'TV right light'),
        _luzDevice('dev_b', 'Living left'),
        _luzDevice('dev_c', 'Living LED Left'),
      ]);
      final items = [
        for (var i = 0; i < 3; i++)
          _luz(['dev_a', 'dev_b', 'dev_c'][i], {'on': false},
              ms: i * 10, correlationId: 'corr-liv', actor: 'alexa'),
      ];
      final h = _hechos(items, devices).single;
      final sujeto = causeSubject(h, devices);
      expect(sujeto.text, '3 luces');
      expect(sujeto.plural, isTrue);
      expect(presentCause(h, devices).title, '3 luces se apagaron');
    });

    test('dos aparatos distintos sin causa no se mezclan', () {
      final devices = _devices();
      final items = [
        _luz('dev_liv', {'on': true}, ms: 100),
        _luz('dev_h1', {'on': true}, ms: 0),
      ];
      expect(_hechos(items, devices).length, 2);
    });

    test('ningún evento se pierde en el camino', () {
      final devices = _devices();
      final items = [
        ..._hallPrendido(),
        _luz('dev_liv', {'on': false}, ms: 9000),
        _ev({
          'deviceId': 'dev_h1',
          'sensor': {'motion': true},
        }, ms: 12000),
      ];
      final total = _hechos(items, devices)
          .fold<int>(0, (n, h) => n + h.eventCount);
      expect(total, items.length);
    });
  });

  group('CCE#75 · quién lo hizo', () {
    test('una automatización se muestra por su nombre, nunca por su id', () {
      final devices = _devices();
      final label = actorLabel('automation:$_kAutoId', devices);
      expect(label, 'por «$_kAutoName»');
      expect(label, isNot(contains('automation:')));
      expect(label, isNot(contains('auto_mq')));
    });

    test('una automatización borrada no filtra el id crudo', () {
      final devices = _devices();
      expect(actorLabel('automation:auto_borrada', devices),
          'por una automatización');
    });

    test('las personas y los asistentes se dicen en castellano', () {
      final devices = _devices();
      expect(actorLabel('user:app', devices), 'desde la app');
      expect(actorLabel('user:dashboard', devices), 'desde el panel');
      expect(actorLabel('user:cli', devices), 'desde la terminal');
      expect(actorLabel('alexa', devices), 'por Alexa');
      expect(actorLabel('system:power-restore', devices), 'por el sistema');
    });

    test('sin actor no se dice nada: el cambio pasó solo', () {
      final devices = _devices();
      expect(actorLabel(null, devices), isNull);
      expect(actorLabel('', devices), isNull);
    });

    test('sólo una automatización enlaza', () {
      expect(automationIdOfActor('automation:$_kAutoId'), _kAutoId);
      expect(automationIdOfActor('user:app'), isNull);
      expect(automationIdOfActor(null), isNull);
      expect(automationIdOfActor('automation:'), isNull);
    });
  });

  group('CCE#75 · la fila', () {
    Future<CauseGroup> pumpHall(WidgetTester tester,
        {void Function(String)? onOpen}) async {
      final devices = _devices();
      final h = _hechos(_hallPrendido(), devices).single;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EventRow(
            group: h,
            devices: devices,
            expanded: false,
            onToggleExpand: () {},
            onOpenAutomation: onOpen,
          ),
        ),
      ));
      return h;
    }

    testWidgets('muestra «4 luces» y quién lo pidió', (tester) async {
      await pumpHall(tester);
      expect(find.text('Hall se encendió'), findsOneWidget);
      expect(find.text('4 luces'), findsOneWidget);
      expect(find.text('por «$_kAutoName»'), findsOneWidget);
    });

    testWidgets('tocar el actor abre la automatización', (tester) async {
      String? abierta;
      await pumpHall(tester, onOpen: (id) => abierta = id);
      await tester.tap(find.text('por «$_kAutoName»'));
      await tester.pump();
      expect(abierta, _kAutoId);
    });

    testWidgets('expandida muestra los doce cambios', (tester) async {
      final devices = _devices();
      final h = _hechos(_hallPrendido(), devices).single;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventRow(
              group: h,
              devices: devices,
              expanded: true,
              onToggleExpand: () {},
            ),
          ),
        ),
      ));
      // Una línea por cambio individual, con su hora (los doce caen en el
      // mismo segundo: es el punto del issue).
      expect(
        find.text(TimeFormat.hms(h.events.first.timestamp)),
        findsNWidgets(12),
      );
    });

    testWidgets('un hecho sin causa no inventa una línea de actor',
        (tester) async {
      final devices = _devices();
      final h = _hechos(
        [_luz('dev_h4', {'on': true, 'bri': 143}, ms: 0)],
        devices,
      ).single;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EventRow(
            group: h,
            devices: devices,
            expanded: false,
            onToggleExpand: () {},
          ),
        ),
      ));
      expect(find.textContaining('por '), findsNothing);
      expect(find.textContaining('desde '), findsNothing);
    });
  });
}
