// Borrar una escena capturada de una luz (EugeValeiras/CCE#110).
//
// Desde CCE#100 el dueño captura escenas del Hexagon desde la app, pero no
// podía sacarlas: no existía ni el método en `ApiService` ni el gesto en el
// widget. Esto fija, con la API de mentira (MockClient por `runWithClient`,
// como automations_order_test):
//
//   1. El service hace UN `DELETE /tuya/light-scenes/:id` (item-level) y saca
//      la escena del estado de TODOS los devices que la ofrecían —los dos
//      Hexagon comparten «Cyan» por producto— EN EL LUGAR: el objeto Device es
//      el mismo, así que el `widget.device` del sheet no queda huérfano (la
//      trampa del `refresh()` global que marcó la review de #43). Y sin ningún
//      GET: el backend no reconstruye su store al borrar, un re-fetch traería
//      la escena de vuelta.
//   2. Un 404 («Escena X no encontrada») lanza con ese motivo y no toca nada.
//   3. En el widget, mantener apretado el chip pregunta; cancelar no llama a
//      la API; confirmar borra y el chip desaparece sin cerrar la pantalla; un
//      fallo se muestra y no hay aviso de éxito.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/widgets/light_mode_scenes.dart';

// ── La casa, tal cual la sirve GET /api/devices el 2026-09-04 ───────────────
const cyanId = 'tuyascene_mtnkrsa1';
const auroraId = 'tuyascene_aurora';
const cyan = {'id': cyanId, 'name': 'Cyan'};
const aurora = {'id': auroraId, 'name': 'Aurora', 'icon': '🌅'};
const rightId = 'dev_89a412f6fdcd';
const leftId = 'dev_0ffda611ec74';

Map<String, dynamic> hexagon(
  String id,
  String name,
  String binding, {
  required List<Map<String, String>> scenes,
  String? sceneId,
}) =>
    {
      'id': id,
      'name': name,
      'type': 'Tuya Color Light',
      'capabilities': ['switch', 'brightness', 'color_hsv', 'light_mode', 'scene'],
      'state': {
        'on': true,
        'bri': 254,
        'reachable': true,
        'mode': 'scene',
        'lightModes': ['white', 'colour', 'scene', 'music'],
        'lightScenes': scenes,
        'sceneId': ?sceneId,
      },
      'bindings': [
        {'bindingId': binding, 'provider': 'tuya'},
      ],
    };

/// El Right tiene a Cyan PUESTA; el Left ofrece dos y tiene puesta la otra.
List<Device> casa() => [
      Device.fromJson(hexagon(rightId, 'Hexagon: Right',
          'tuya_eb6e2b320b4143e219gexc',
          scenes: [cyan], sceneId: cyanId)),
      Device.fromJson(hexagon(leftId, 'Hexagon: Left',
          'tuya_eb74bd2ed5a847e806aqtq',
          scenes: [cyan, aurora], sceneId: auroraId)),
    ];

/// La API de mentira: registra todo lo que le llega y contesta el DELETE de
/// una escena como se le indique. Cualquier otra cosa: 404 vacío.
class _Api {
  final requests = <http.Request>[];
  int deleteStatus = 200;
  String deleteBody = '{"success":true}';

  http.Client client() => MockClient((req) async {
        requests.add(req);
        if (req.method == 'DELETE' &&
            req.url.path.contains('/tuya/light-scenes/')) {
          return http.Response(deleteBody, deleteStatus,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('', 404);
      });

  List<String> get deletes =>
      [for (final r in requests) if (r.method == 'DELETE') r.url.path];
  int get gets => requests.where((r) => r.method == 'GET').length;
}

DevicesService _service(List<Device> devices) {
  final s = DevicesService(
    config: ServerConfig(host: '127.0.0.1', port: 1),
    socket: SocketService(),
  );
  s.debugSeedDevices(devices);
  return s;
}

List<String> _scenesOf(DevicesService s, String id) =>
    [for (final sc in s.byId(id)!.state.lightScenes ?? const <LightScene>[]) sc.name];

void main() {
  group('DevicesService.removeLightScene', () {
    test('borra por DELETE item-level y la saca de los dos Hexagon EN EL LUGAR',
        () async {
      final api = _Api();
      await http.runWithClient(() async {
        final s = _service(casa());
        final right = s.byId(rightId)!;
        final left = s.byId(leftId)!;
        expect(_scenesOf(s, rightId), ['Cyan']);
        expect(_scenesOf(s, leftId), ['Cyan', 'Aurora']);
        final getsAntes = api.gets;
        var avisos = 0;
        s.addListener(() => avisos++);

        await s.removeLightScene(cyanId);

        expect(api.deletes, hasLength(1), reason: 'UN solo DELETE');
        expect(api.deletes.single, endsWith('/tuya/light-scenes/$cyanId'));
        expect(api.gets, getsAntes,
            reason: 'ningún GET: un re-fetch traería la escena de vuelta '
                '(el backend no reconstruye su store al borrar)');
        expect(_scenesOf(s, rightId), isEmpty, reason: 'el Right ya no la ofrece');
        expect(_scenesOf(s, leftId), ['Aurora'],
            reason: 'el Left tampoco, y conserva Aurora');
        expect(identical(s.byId(rightId), right), isTrue,
            reason: 'el MISMO objeto Device: el widget.device del sheet sigue vivo');
        expect(identical(s.byId(leftId), left), isTrue);
        expect(right.state.lightScenes, isEmpty,
            reason: 'y ese objeto ya ve el estado nuevo');
        expect(left.state.sceneId, auroraId,
            reason: 'la puesta del Left era Aurora: sigue puesta');
        expect(avisos, 1, reason: 'un solo notifyListeners');
      }, api.client);
    });

    test('un 404 lanza con el motivo del backend y no toca nada', () async {
      final api = _Api()
        ..deleteStatus = 404
        ..deleteBody = '{"error":"Escena $cyanId no encontrada"}';
      await http.runWithClient(() async {
        final s = _service(casa());
        var avisos = 0;
        s.addListener(() => avisos++);
        await expectLater(
          s.removeLightScene(cyanId),
          throwsA(predicate<Object>(
              (e) => e.toString().contains('Escena $cyanId no encontrada'))),
        );
        expect(api.deletes, hasLength(1), reason: 'se intentó');
        expect(_scenesOf(s, rightId), ['Cyan'], reason: 'y la grilla no se toca');
        expect(_scenesOf(s, leftId), ['Cyan', 'Aurora']);
        expect(avisos, 0);
      }, api.client);
    });

    test('un 200 con success:false tampoco es un éxito', () async {
      final api = _Api()..deleteBody = '{"success":false}';
      await http.runWithClient(() async {
        final s = _service(casa());
        await expectLater(s.removeLightScene(cyanId), throwsA(isA<Exception>()));
        expect(_scenesOf(s, rightId), ['Cyan']);
      }, api.client);
    });

    test('una escena que ningún device ofrece no avisa a nadie', () async {
      final api = _Api();
      await http.runWithClient(() async {
        final s = _service(casa());
        var avisos = 0;
        s.addListener(() => avisos++);
        await s.removeLightScene('tuyascene_de_otro_producto');
        expect(api.deletes, hasLength(1));
        expect(avisos, 0);
      }, api.client);
    });
  });

  group('LightModeScenesSection: mantener apretado borra', () {
    Future<Device> abrir(WidgetTester tester, DevicesService s, String id) async {
      final d = s.byId(id)!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LightModeScenesSection(device: d, service: s),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return d;
    }

    testWidgets('pregunta; cancelar no llama a la API y el chip se queda',
        (tester) async {
      final api = _Api();
      await http.runWithClient(() async {
        final s = _service(casa());
        await abrir(tester, s, leftId);
        expect(find.text('Cyan'), findsOneWidget);
        expect(find.textContaining('Mantené apretada una escena'), findsOneWidget,
            reason: 'el gesto se explica: un long-press no se descubre solo');

        await tester.longPress(find.text('Cyan'));
        await tester.pumpAndSettle();
        expect(find.text('Borrar «Cyan»'), findsOneWidget, reason: 'pregunta');
        expect(find.textContaining('No se puede deshacer'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(api.deletes, isEmpty, reason: 'cancelar: NINGUNA llamada');
        expect(find.text('Cyan'), findsOneWidget, reason: 'y el chip sigue');
      }, api.client);
    });

    testWidgets('confirmar borra y el chip desaparece sin cerrar la pantalla',
        (tester) async {
      final api = _Api();
      await http.runWithClient(() async {
        final s = _service(casa());
        final d = await abrir(tester, s, leftId);

        await tester.longPress(find.text('Cyan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Borrar'));
        await tester.pumpAndSettle();

        expect(api.deletes, hasLength(1));
        expect(api.deletes.single, endsWith('/tuya/light-scenes/$cyanId'));
        expect(find.text('Cyan'), findsNothing, reason: 'el chip se fue');
        // «Aurora» aparece dos veces: el chip y el rótulo de la escena PUESTA.
        expect(find.widgetWithText(LightChoiceChip, 'Aurora'), findsOneWidget,
            reason: 'la otra sigue');
        expect(find.text('Escena «Cyan» borrada'), findsOneWidget,
            reason: 'el aviso de éxito, sólo porque ocurrió');
        expect(identical(s.byId(leftId), d), isTrue,
            reason: 'el device del widget es el mismo objeto: sin refresh global');
        expect(d.state.lightScenes!.map((sc) => sc.name), ['Aurora']);
      }, api.client);
    });

    testWidgets('si la API falla se muestra el motivo y no hay aviso de éxito',
        (tester) async {
      final api = _Api()
        ..deleteStatus = 404
        ..deleteBody = '{"error":"Escena $cyanId no encontrada"}';
      await http.runWithClient(() async {
        final s = _service(casa());
        await abrir(tester, s, leftId);

        await tester.longPress(find.text('Cyan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Borrar'));
        await tester.pumpAndSettle();

        expect(api.deletes, hasLength(1));
        expect(find.text('Cyan'), findsOneWidget, reason: 'el chip se queda');
        expect(find.text('Escena $cyanId no encontrada'), findsOneWidget,
            reason: 'con el motivo del backend');
        expect(find.textContaining('borrada'), findsNothing,
            reason: 'ningún aviso de éxito sobre un borrado que no ocurrió');
      }, api.client);
    });

    testWidgets('sin escenas no se explica un gesto que no existe',
        (tester) async {
      final api = _Api();
      await http.runWithClient(() async {
        final s = _service([
          Device.fromJson(hexagon(rightId, 'Hexagon: Right', 'tuya_x',
              scenes: const [])),
        ]);
        await abrir(tester, s, rightId);
        expect(find.textContaining('Todavía no hay ninguna guardada'),
            findsOneWidget);
        expect(find.textContaining('Mantené apretada'), findsNothing);
      }, api.client);
    });
  });

  test('el DELETE que manda la app es el que espera el backend', () async {
    // Sin cuerpo: la baja es por id en la URL. Lo único que viaja es el token.
    final api = _Api();
    await http.runWithClient(() async {
      final s = _service(casa());
      await s.removeLightScene(cyanId);
      final req = api.requests.singleWhere((r) => r.method == 'DELETE');
      expect(req.body, isEmpty);
      expect(req.url.path, endsWith('/tuya/light-scenes/$cyanId'));
      expect(jsonDecode(api.deleteBody)['success'], isTrue);
    }, api.client);
  });
}
