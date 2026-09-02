// EugeValeiras/CCE#79 — el orden de las automatizaciones es la posición en el
// array del servidor, el que el dueño arma arrastrando en el Dashboard. La app
// tiene que RESPETARLO (mostrarlo tal cual, no alfabético) y PRESERVARLO: cada
// escritura es GET fresco → merge → PUT del array entero, y si el merge
// partiera de la lista local, un toggle desde el teléfono desharía el orden
// que el Dashboard acaba de guardar.
//
// La API es de mentira (MockClient por `runWithClient`): el service usa las
// funciones top-level de `package:http`, que miran la zona.
import 'dart:convert';

import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/automations_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/automations/automations_order_page.dart';
import 'package:cce_app/views/automations/automations_view.dart';

Map<String, dynamic> _auto(
  String id,
  String name, {
  String trigger = 'manual',
  bool enabled = true,
}) =>
    {
      'id': id,
      'name': name,
      'icon': '⚡',
      'enabled': enabled,
      'source': 'custom',
      'mode': 'toggle',
      'trigger': {'type': trigger},
      'actions': <Map<String, dynamic>>[],
      // Algo que la app no modela (el lienzo del Dashboard), para ver que
      // viaja intacto.
      'flowLayout': {
        'trigger': {'x': 10, 'y': 20},
      },
    };

List<String> _ids(List<Map<String, dynamic>> list) =>
    [for (final m in list) m['id'] as String];

List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> list) => [
      for (final m in list)
        Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map),
    ];

/// Servidor de mentira: sirve `GET /config/automations` desde [server] y anota
/// cada PUT. Todo lo demás, 404 (el service lo tolera).
class _FakeApi {
  _FakeApi(this.server);

  List<Map<String, dynamic>> server;
  final puts = <List<Map<String, dynamic>>>[];
  bool failPut = false;

  http.Client client() => MockClient((req) async {
        if (req.url.path.endsWith('/config/automations')) {
          if (req.method == 'GET') {
            return http.Response(jsonEncode(server), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.method == 'PUT') {
            if (failPut) return http.Response('{"error":true}', 500);
            final body = [
              for (final m in jsonDecode(req.body) as List)
                Map<String, dynamic>.from(m as Map),
            ];
            puts.add(body);
            server = body;
            return http.Response('{"success":true}', 200);
          }
        }
        return http.Response('', 404);
      });
}

Future<AutomationsService> _loadedService() async {
  final devices = DevicesService(config: ServerConfig(), socket: SocketService());
  final service = AutomationsService(config: ServerConfig(), devices: devices);
  for (var i = 0; i < 200 && service.automations.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(service.automations, isNotEmpty, reason: 'el GET inicial no llegó');
  return service;
}

List<String> _localIds(AutomationsService s) =>
    [for (final a in s.automations) a.id];

void main() {
  group('applyAutomationOrder', () {
    String id(Map<String, dynamic> m) => m['id'] as String;
    final list = [_auto('a', 'A'), _auto('b', 'B'), _auto('c', 'C')];

    test('acomoda la lista entera y no toca los objetos', () {
      final out = applyAutomationOrder(list, ['c', 'a', 'b'], id);
      expect(_ids(out), ['c', 'a', 'b']);
      expect(out.every(list.contains), isTrue, reason: 'misma identidad');
      expect(_ids(list), ['a', 'b', 'c'], reason: 'no muta la entrada');
    });

    test('un subconjunto mueve sólo esos y el resto no se mueve', () {
      expect(_ids(applyAutomationOrder(list, ['c', 'a'], id)), ['c', 'b', 'a']);
    });

    test('ids que el servidor ya no tiene se ignoran; lo que el cliente no vio '
        'conserva su lugar', () {
      final server = [_auto('a', 'A'), _auto('n', 'Nueva'), _auto('c', 'C')];
      expect(
        _ids(applyAutomationOrder(server, ['c', 'b', 'a'], id)),
        ['c', 'n', 'a'],
      );
      expect(_ids(applyAutomationOrder(server, ['zzz'], id)), ['a', 'n', 'c']);
    });
  });

  test('un toggle desde la app no deshace el orden que el Dashboard guardó',
      () async {
    final api = _FakeApi([
      _auto('a', 'Alfa'),
      _auto('b', 'Beta'),
      _auto('c', 'Gamma'),
    ]);
    await http.runWithClient(() async {
      final service = await _loadedService();
      expect(_localIds(service), ['a', 'b', 'c']);

      // Con la lista vieja cargada en el teléfono, el Dashboard reordena.
      api.server = [api.server[2], api.server[0], api.server[1]];
      final original = _copy(api.server);

      final result = await service.setEnabled('a', false);
      expect(result.ok, isTrue);

      final put = api.puts.single;
      expect(_ids(put), ['c', 'a', 'b'],
          reason: 'el PUT lleva el orden del GET fresco, no el local');
      expect(put[0], original[0], reason: 'Gamma intacta');
      expect(put[2], original[2], reason: 'Beta intacta');
      expect(put[1]['enabled'], isFalse);
      expect({...put[1], 'enabled': true}, original[1],
          reason: 'de Alfa cambió sólo enabled');
    }, api.client);
  });

  test('reordenar manda el array fresco en el orden nuevo, sin perder lo que '
      'la app no vio', () async {
    final api = _FakeApi([
      _auto('a', 'Alfa'),
      _auto('b', 'Beta'),
      _auto('c', 'Gamma'),
    ]);
    await http.runWithClient(() async {
      final service = await _loadedService();
      // Entre el GET de la app y el drop, el Dashboard creó una.
      api.server = [...api.server, _auto('n', 'Nueva')];
      final original = _copy(api.server);

      final result = await service.reorder(['c', 'a', 'b']);
      expect(result.ok, isTrue);

      final put = api.puts.single;
      expect(_ids(put), ['c', 'a', 'b', 'n']);
      for (final sent in put) {
        final before = original.singleWhere((m) => m['id'] == sent['id']);
        expect(sent, before, reason: '${sent['name']} byte a byte');
      }
      // Y la lista local ya está en ese orden (optimista).
      expect(_localIds(service), ['c', 'a', 'b']);
    }, api.client);
  });

  test('si el PUT falla, la lista vuelve a como estaba y se avisa', () async {
    final api = _FakeApi([_auto('a', 'Alfa'), _auto('b', 'Beta')]);
    await http.runWithClient(() async {
      final service = await _loadedService();
      api.failPut = true;
      final result = await service.reorder(['b', 'a']);
      expect(result.ok, isFalse);
      expect(result.message, 'No se pudo guardar el orden');
      expect(_localIds(service), ['a', 'b']);
    }, api.client);
  });

  testWidgets('la lista muestra el orden del servidor, no el alfabético',
      (tester) async {
    // Pantalla de teléfono: una sola columna, así el orden es vertical.
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _FakeApi([_auto('z', 'Zeta'), _auto('a', 'Alfa')]);
    await http.runWithClient(() async {
      final devices =
          DevicesService(config: ServerConfig(), socket: SocketService());
      await tester.pumpWidget(MaterialApp(
        home: AutomationsView(devices: devices, config: ServerConfig()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Zeta'), findsOneWidget);
      expect(find.text('Alfa'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zeta')).dy,
        lessThan(tester.getTopLeft(find.text('Alfa')).dy),
        reason: 'Zeta va primera porque el servidor la tiene primera',
      );
      expect(find.byTooltip('Reordenar'), findsOneWidget);
      // Desmonta la vista (tiene un ticker de 30 s).
      await tester.pumpWidget(const SizedBox());
    }, api.client);
  });

  testWidgets('arrastrar desde el asa en «Ordenar» guarda el orden nuevo',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _FakeApi([
      _auto('a', 'Alfa'),
      _auto('b', 'Beta', trigger: 'sensor'),
      _auto('c', 'Gamma', enabled: false),
    ]);
    await http.runWithClient(() async {
      final devices =
          DevicesService(config: ServerConfig(), socket: SocketService());
      final service =
          AutomationsService(config: ServerConfig(), devices: devices);
      await tester.pumpWidget(MaterialApp(
        home: AutomationsOrderPage(service: service),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Alfa'), findsOneWidget);
      expect(find.text('Por sensor'), findsOneWidget);
      expect(find.text('Manual · desactivada'), findsOneWidget);

      final alfaY = tester.getTopLeft(find.text('Alfa')).dy;
      final betaY = tester.getTopLeft(find.text('Beta')).dy;
      final rowStep = betaY - alfaY;

      // Alfa, desde su asa, hasta debajo de Beta. Tres cuartos de fila: el
      // SliverReorderableList decide el hueco cuando el final de la fila que
      // viaja entra en la mitad inferior de Beta (una fila entera ya la pasa
      // de largo).
      final handle = find.byIcon(Icons.drag_handle_rounded).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(kPressTimeout);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(Offset(0, rowStep * 0.75 - 20));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(api.puts, hasLength(1));
      expect(_ids(api.puts.single), ['b', 'a', 'c']);
      expect(
        tester.getTopLeft(find.text('Beta')).dy,
        lessThan(tester.getTopLeft(find.text('Alfa')).dy),
      );
      await tester.pumpWidget(const SizedBox());
    }, api.client);
  });
}
