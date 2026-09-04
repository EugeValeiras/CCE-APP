// Test de contrato del MODO y las ESCENAS de una luz (EugeValeiras/CCE#100).
//
// El Hexagon (Tuya KA-FW03) llegaba a la app sin nada con qué operarlo: el modo
// se leía y no se podía cambiar, el panel que arrancó en modo `scene` ni
// siquiera declaraba `color_hsv` —el mismo producto, con capabilities
// distintas— y sus escenas propias no existían para CCE.
//
// El backend nuevo lo declara con dos capabilities (`light_mode`, `scene`) y lo
// reporta en `state.lightModes` / `state.lightScenes` / `state.sceneId`. Los
// payloads son los REALES de los dos paneles de la casa, medidos contra el
// aparato el 2026-09-04:
//
//   Right  21='colour'  24=0161037603e8  (h=353 s=886 v=1000)
//   Left   21='scene'   24=0129038d000a  (h=297 s=909 v=10)
//
// AISLADO A PROPÓSITO (mismo criterio que detach_toggle_test): importa SÓLO el
// modelo, el registry puro de renderers y los helpers de labels/enums.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/capability.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/unified_device_screen.dart';
import 'package:cce_app/widgets/light_detail_sheet.dart';
import 'package:cce_app/utils/capability_renderers.dart';
import 'package:cce_app/utils/enum_options.dart';
import 'package:cce_app/utils/verb_labels.dart';

const _modes = ['white', 'colour', 'scene', 'music'];

/// Hexagon Right: en modo `colour`, rojo a full.
const rightJson = <String, dynamic>{
  'id': 'dev_89a412f6fdcd',
  'name': 'Hexagon: Right',
  'type': 'Tuya Color Light',
  'productname': 'Smart Hexagon Light: Desktop KA-FW03',
  'modelid': 'f8hcheiefv1nhejd',
  'capabilities': ['switch', 'brightness', 'color_hsv', 'light_mode', 'scene'],
  'state': {
    'on': false,
    'bri': 254,
    'hue': 64261,
    'sat': 225,
    'reachable': true,
    'mode': 'colour',
    'lightModes': _modes,
  },
  'bindings': [
    {'bindingId': 'tuya_eb6e2b320b4143e219gexc', 'provider': 'tuya'},
  ],
};

/// Hexagon Left: en modo `scene`, con dos escenas ya capturadas y una de ellas
/// puesta. Es el panel que salía sin color.
const leftJson = <String, dynamic>{
  'id': 'dev_0ffda611ec74',
  'name': 'Hexagon: Left',
  'type': 'Tuya Color Light',
  'productname': 'Smart Hexagon Light: Desktop KA-FW03',
  'modelid': 'f8hcheiefv1nhejd',
  'capabilities': ['switch', 'brightness', 'color_hsv', 'light_mode', 'scene'],
  'state': {
    'on': false,
    'bri': 1,
    'hue': 54066,
    'sat': 231,
    'reachable': true,
    'mode': 'scene',
    'sceneId': 'tuyascene_a',
    'lightModes': _modes,
    'lightScenes': [
      {'id': 'tuyascene_a', 'name': 'Aurora'},
      {'id': 'tuyascene_b', 'name': 'Living de noche', 'icon': '🌙'},
    ],
  },
  'bindings': [
    {'bindingId': 'tuya_eb74bd2ed5a847e806aqtq', 'provider': 'tuya'},
  ],
};

/// Una luz Hue común: no tiene ni modos ni escenas propias.
const hueJson = <String, dynamic>{
  'id': 'dev_hue',
  'name': 'Luz',
  'type': 'Extended color light',
  'capabilities': ['switch', 'brightness', 'color_temperature', 'color_hsv'],
  'state': {'on': true, 'bri': 200, 'hue': 8000, 'sat': 140, 'reachable': true},
};

/// El catálogo tal como lo sirve el backend: los enums de la luz viajan VACÍOS
/// a propósito (son por-device), y es lo que los selectores tienen que superar.
const _catalog = CapabilityCatalog(
  baseStateFields: ['reachable', 'mode'],
  capabilities: {
    'switch': CapabilitySpec(capability: 'switch', stateFields: ['on']),
    'brightness': CapabilitySpec(capability: 'brightness', stateFields: ['bri']),
    'color_hsv':
        CapabilitySpec(capability: 'color_hsv', stateFields: ['hue', 'sat']),
    'light_mode': CapabilitySpec(
      capability: 'light_mode',
      stateFields: ['lightModes'],
      actions: [
        CatalogActionSpec(
          verb: 'setMode',
          args: [
            CatalogArgSpec(
                name: 'mode', type: 'string', enumRef: 'LIGHT_MODES'),
          ],
          affects: ['mode'],
        ),
      ],
    ),
    'scene': CapabilitySpec(
      capability: 'scene',
      stateFields: ['sceneId', 'lightScenes'],
      actions: [
        CatalogActionSpec(
          verb: 'setScene',
          args: [
            CatalogArgSpec(
                name: 'sceneId', type: 'string', enumRef: 'LIGHT_SCENES'),
          ],
          affects: ['sceneId', 'mode'],
        ),
      ],
    ),
  },
  enums: {'LIGHT_MODES': [], 'LIGHT_SCENES': []},
);

DevicesService _service(List<Device> devices) {
  final s = DevicesService(config: ServerConfig(), socket: SocketService());
  s.debugSeedDevices(devices);
  s.debugSeedCapabilityCatalog(_catalog);
  return s;
}

void main() {
  final right = Device.fromJson(Map<String, dynamic>.from(rightJson));
  final left = Device.fromJson(Map<String, dynamic>.from(leftJson));
  final hue = Device.fromJson(Map<String, dynamic>.from(hueJson));

  List<CapabilityRendererKind> kinds(Device d) =>
      capabilityRenderersFor(d.capabilities).map((e) => e.kind).toList();

  group('los dos paneles se ven IGUAL', () {
    // La regresión que motiva el issue: mismo producto, capabilities distintas
    // según el modo en que estuvieran al arrancar.
    test('mismas capabilities', () {
      expect(left.capabilities..sort(), right.capabilities..sort());
    });

    test('mismos renderers, en el mismo orden', () {
      expect(kinds(left), kinds(right));
    });

    test('y el orden pone el modo y las escenas después del color', () {
      expect(kinds(left), [
        CapabilityRendererKind.onoff,
        CapabilityRendererKind.brightness,
        CapabilityRendererKind.colorHsv,
        CapabilityRendererKind.lightMode,
        CapabilityRendererKind.scene,
      ]);
    });

    test('aunque las capabilities lleguen desordenadas', () {
      expect(
        capabilityRenderersFor(['scene', 'light_mode', 'color_hsv', 'switch'])
            .map((e) => e.kind)
            .toList(),
        [
          CapabilityRendererKind.onoff,
          CapabilityRendererKind.colorHsv,
          CapabilityRendererKind.lightMode,
          CapabilityRendererKind.scene,
        ],
      );
    });
  });

  group('el estado se parsea', () {
    test('los modos del producto', () {
      expect(left.state.lightModes, _modes);
      expect(right.state.lightModes, _modes);
    });

    test('el modo activo', () {
      expect(left.state.mode, 'scene');
      expect(right.state.mode, 'colour');
    });

    test('el color, TAMBIÉN en modo escena', () {
      // Esto es la otra mitad del bug: el Left conserva su colour_data estando
      // en `scene`, y el backend viejo no lo reportaba.
      expect(left.state.hue, 54066);
      expect(left.state.sat, 231);
    });

    test('las escenas guardadas, con su id y su nombre', () {
      expect(left.state.lightScenes, isNotNull);
      expect(left.state.lightScenes!.length, 2);
      expect(left.state.lightScenes!.first.id, 'tuyascene_a');
      expect(left.state.lightScenes!.first.name, 'Aurora');
      expect(left.state.lightScenes![1].icon, '🌙');
    });

    test('y cuál está puesta', () {
      expect(left.state.sceneId, 'tuyascene_a');
      // El Right no está en escena: no reporta ninguna.
      expect(right.state.sceneId, isNull);
      expect(right.state.lightScenes, isNull);
    });

    test('copyWith conserva los campos nuevos', () {
      final movido = left.state.copyWith(mode: 'colour');
      expect(movido.mode, 'colour');
      expect(movido.lightModes, _modes);
      expect(movido.lightScenes!.length, 2);
    });

    test('un device sin los campos no los inventa', () {
      expect(hue.state.lightModes, isNull);
      expect(hue.state.lightScenes, isNull);
      expect(hue.state.sceneId, isNull);
    });
  });

  group('opciones de los selectores', () {
    // Los enums del catálogo viajan VACÍOS a propósito: sus valores son del
    // aparato (los modos de su producto) y de la config (las escenas). Si el
    // selector dependiera del catálogo, saldría sin opciones.
    List<String> vacio(String _) => const [];

    test('los modos: valor del aparato, etiqueta en castellano', () {
      final opts = resolveEnumOptions('LIGHT_MODES', left.state, vacio);
      expect(opts.map((o) => o.value).toList(), _modes);
      expect(opts.map((o) => o.label).toList(),
          ['Blanco', 'Color', 'Escena', 'Música']);
    });

    test('las escenas: viajan por ID y se leen por NOMBRE', () {
      // Que el id sea el que viaja es lo que permite renombrar una escena sin
      // romper las automatizaciones que la usan.
      final opts = resolveEnumOptions('LIGHT_SCENES', left.state, vacio);
      expect(opts.map((o) => o.value).toList(),
          ['tuyascene_a', 'tuyascene_b']);
      expect(opts.map((o) => o.label).toList(),
          ['Aurora', 'Living de noche']);
    });

    test('sin escenas guardadas, el selector queda vacío', () {
      expect(resolveEnumOptions('LIGHT_SCENES', right.state, vacio), isEmpty);
    });

    test('sin modos reportados, no se inventan', () {
      expect(resolveEnumOptions('LIGHT_MODES', hue.state, vacio), isEmpty);
    });

    test('los enums de siempre no cambian (etiqueta = valor)', () {
      final robot = DeviceState(cleanModes: const ['Auto', 'Deep']);
      final opts = resolveEnumOptions('VACUUM_CLEAN_MODES', robot, vacio);
      expect(opts.map((o) => o.value).toList(), ['Auto', 'Deep']);
      expect(opts.map((o) => o.label).toList(), ['Auto', 'Deep']);
    });

    test('un enum estático sigue saliendo del catálogo', () {
      expect(
        resolveEnumOptions('PLAYBACK_ACTIONS', hue.state, (_) => ['play'])
            .single
            .value,
        'play',
      );
    });
  });

  group('etiquetas', () {
    test('los cuatro modos, en castellano', () {
      expect(lightModeLabel('white'), 'Blanco');
      expect(lightModeLabel('colour'), 'Color');
      expect(lightModeLabel('scene'), 'Escena');
      expect(lightModeLabel('music'), 'Música');
    });

    test('un modo que no conocemos se muestra crudo', () {
      // Forward-compat: un producto con un modo nuevo no puede quedar con el
      // chip en blanco.
      expect(lightModeLabel('rhythm'), 'rhythm');
    });

    test('los verbos tienen etiqueta legible', () {
      expect(verbLabel('setMode'), 'Modo');
      expect(verbLabel('setScene'), 'Escena');
    });

    test('el nombre de una escena guardada se resuelve para el resumen', () {
      expect(
        enumOptionLabel('LIGHT_SCENES', 'tuyascene_b', left.state),
        'Living de noche',
      );
    });

    test('una escena BORRADA se muestra cruda, no en blanco', () {
      expect(
        enumOptionLabel('LIGHT_SCENES', 'tuyascene_vieja', left.state),
        'tuyascene_vieja',
      );
    });
  });

  group('nada de esto le toca a una luz común', () {
    test('sin light_mode ni scene no gana renderers', () {
      expect(kinds(hue), [
        CapabilityRendererKind.onoff,
        CapabilityRendererKind.brightness,
        CapabilityRendererKind.colorTemperature,
        CapabilityRendererKind.colorHsv,
      ]);
    });

    test('las dos capabilities son independientes', () {
      expect(capabilityRenderersFor(['switch', 'light_mode']).map((e) => e.kind),
          [CapabilityRendererKind.onoff, CapabilityRendererKind.lightMode]);
      expect(capabilityRenderersFor(['switch', 'scene']).map((e) => e.kind),
          [CapabilityRendererKind.onoff, CapabilityRendererKind.scene]);
    });
  });

  group('la vista unificada RENDERIZA los controles', () {
    testWidgets('los chips de modo, con el puesto marcado', (tester) async {
      final service = _service([left]);
      await tester.pumpWidget(MaterialApp(
        home: UnifiedDeviceScreen(device: left, service: service),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Modo de la luz'), findsOneWidget);
      // Etiquetas en castellano, no los valores del aparato.
      for (final label in ['Blanco', 'Color', 'Escena', 'Música']) {
        expect(find.text(label), findsWidgets, reason: 'falta el modo $label');
      }
      expect(find.text('colour'), findsNothing);
    });

    testWidgets('las escenas por NOMBRE, no por id', (tester) async {
      final service = _service([left]);
      await tester.pumpWidget(MaterialApp(
        home: UnifiedDeviceScreen(device: left, service: service),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Escenas'), findsOneWidget);
      expect(find.text('Aurora'), findsOneWidget);
      expect(find.text('Living de noche'), findsOneWidget);
      expect(find.text('tuyascene_a'), findsNothing);
    });

    testWidgets('sin escenas guardadas no se promete un selector vacío',
        (tester) async {
      final service = _service([right]);
      await tester.pumpWidget(MaterialApp(
        home: UnifiedDeviceScreen(device: right, service: service),
      ));
      await tester.pumpAndSettle();

      // El modo sí (lo declara el producto); las escenas todavía no hay.
      expect(find.text('Modo de la luz'), findsOneWidget);
      expect(find.text('Aurora'), findsNothing);
    });
  });

  group('el sheet de la luz RENDERIZA modo y escenas', () {
    /// Abre el sheet y lo desplaza hasta el fondo: el modo y las escenas van
    /// DESPUÉS del color, y el ListView del sheet es lazy — sin el scroll no
    /// llegan a construirse y el test no vería lo que el dueño sí ve.
    Future<void> abrir(WidgetTester tester, Device d) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = _service([d]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LightDetailSheet(device: d, service: service)),
      ));
      await tester.pumpAndSettle();
      // Hasta el fondo, en varios tirones (el picker de color se come alto).
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(ListView).first,
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('el selector de modo y el aviso del brillo en escena',
        (tester) async {
      await abrir(tester, left);
      expect(find.text('MODO'), findsOneWidget);
      expect(find.text('Escena'), findsWidgets);
      // El aviso es la consecuencia real de que este producto no tenga DP de
      // brillo: cambiarlo en escena saca la luz de la escena.
      expect(
        find.textContaining('la luz pasa a modo Color'),
        findsOneWidget,
      );
    });

    testWidgets('las escenas guardadas y el botón de guardar', (tester) async {
      await abrir(tester, left);
      expect(find.text('ESCENAS'), findsOneWidget);
      expect(find.text('Aurora'), findsWidgets);
      expect(find.text('Guardar como escena'), findsOneWidget);
    });

    testWidgets('sin ninguna guardada, explica cómo guardar la primera',
        (tester) async {
      await abrir(tester, right);
      expect(find.textContaining('Todavía no hay ninguna guardada'),
          findsOneWidget);
      expect(find.text('Guardar como escena'), findsOneWidget);
    });

    testWidgets('una luz común no muestra nada de esto', (tester) async {
      await abrir(tester, hue);
      expect(find.text('MODO'), findsNothing);
      expect(find.text('ESCENAS'), findsNothing);
      expect(find.text('Guardar como escena'), findsNothing);
    });
  });

  group('el binding Tuya, que es por donde se captura la escena', () {
    // El payload de la escena es un dato del protocolo del aparato, no del
    // modelo unificado: sólo el provider que lo lee puede capturarlo.
    test('el Hexagon lo tiene', () {
      expect(left.bindingIds.where((b) => b.startsWith('tuya_')).length, 1);
    });

    test('una luz Hue no', () {
      expect(hue.bindingIds.where((b) => b.startsWith('tuya_')), isEmpty);
    });
  });
}
