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
import 'package:cce_app/views/light_color_screen.dart';
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

/// Service de test SIEMPRE contra un backend inalcanzable.
///
/// El `ServerConfig()` por default apunta a la CASA REAL, y estos tests usan
/// los ids reales de los dos Hexagon: un test que mande un comando por ese
/// config le escribe a la luz del living de una persona. El puerto 1 de
/// loopback rechaza la conexión al instante, así que además el revert se
/// ejercita en milisegundos (sin esperar el timeout de 10 s del cliente).
DevicesService _service(List<Device> devices) {
  final s = DevicesService(
    config: ServerConfig(host: '127.0.0.1', port: 1),
    socket: SocketService(),
  );
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

  // ── Bloqueantes del code-review ─────────────────────────────────────────
  group('review #1 — un evento WS no borra la feature', () {
    // ÉSTE es el que rompía el happy path: `_applyDeviceEvent` re-arma el
    // DeviceState desde una whitelist de campos, y sin los tres nuevos un push
    // trivial los dejaba en null. O sea: tocabas un chip de modo, el backend
    // confirmaba por WS, y el selector que acabás de usar desaparecía.
    DevicesService conElLeft() => _service([
          Device.fromJson(Map<String, dynamic>.from(leftJson)),
        ]);

    test('un push trivial {on:false} conserva los modos', () {
      final s = conElLeft();
      s.debugApplyDeviceEvent(
        DeviceStateEvent(deviceId: left.id, state: const {'on': false}),
      );
      final d = s.byId(left.id)!;
      expect(d.state.lightModes, _modes, reason: 'los modos sobreviven');
      expect(d.state.lightScenes?.length, 2, reason: 'y las escenas guardadas');
      expect(d.state.mode, 'scene', reason: 'y el modo activo');
      expect(d.state.sceneId, 'tuyascene_a', reason: 'y cuál está puesta');
    });

    test('el eco del propio setMode no borra el selector', () {
      // La secuencia real: el usuario toca «Color», el backend lo aplica y
      // ecoa `{mode: 'colour'}`.
      final s = conElLeft();
      s.debugApplyDeviceEvent(
        DeviceStateEvent(deviceId: left.id, state: const {'mode': 'colour'}),
      );
      final d = s.byId(left.id)!;
      expect(d.state.mode, 'colour', reason: 'el modo nuevo se aplica');
      expect(d.state.lightModes, _modes, reason: 'y el selector SIGUE ahí');
      expect(d.state.lightScenes?.length, 2);
    });

    test('al salir de escena, el sceneId se limpia', () {
      // Conservarlo dejaría un chip de escena marcado con la luz en color.
      final s = conElLeft();
      s.debugApplyDeviceEvent(
        DeviceStateEvent(deviceId: left.id, state: const {'mode': 'colour'}),
      );
      expect(s.byId(left.id)!.state.sceneId, isNull);
    });

    test('y en modo escena se conserva', () {
      final s = conElLeft();
      s.debugApplyDeviceEvent(
        DeviceStateEvent(deviceId: left.id, state: const {'bri': 100}),
      );
      expect(s.byId(left.id)!.state.sceneId, 'tuyascene_a');
    });

    test('un evento que TRAE los campos los aplica', () {
      final s = conElLeft();
      s.debugApplyDeviceEvent(DeviceStateEvent(
        deviceId: left.id,
        state: const {
          'mode': 'scene',
          'sceneId': 'tuyascene_b',
          'lightModes': ['white', 'colour'],
        },
      ));
      final d = s.byId(left.id)!;
      expect(d.state.sceneId, 'tuyascene_b');
      expect(d.state.lightModes, ['white', 'colour']);
    });

    test('varios eventos seguidos no la degradan', () {
      // El bug se veía al PRIMER evento; esto fija que tampoco se pierda de a
      // poco (el copyWith de lightScenes es el que lo sostiene).
      final s = conElLeft();
      for (var i = 0; i < 5; i++) {
        s.debugApplyDeviceEvent(
          DeviceStateEvent(deviceId: left.id, state: {'bri': 10 + i}),
        );
      }
      final d = s.byId(left.id)!;
      expect(d.state.lightModes, _modes);
      expect(d.state.lightScenes?.length, 2);
    });

    test('una luz sin la feature no gana campos de la nada', () {
      final s = _service([Device.fromJson(Map<String, dynamic>.from(hueJson))]);
      s.debugApplyDeviceEvent(
        DeviceStateEvent(deviceId: 'dev_hue', state: const {'on': false}),
      );
      final d = s.byId('dev_hue')!;
      expect(d.state.lightModes, isNull);
      expect(d.state.lightScenes, isNull);
    });
  });

  group('review #2 — la feature se alcanza por el camino NORMAL', () {
    // El UI estaba sólo en LightDetailSheet, que se abre ÚNICAMENTE con
    // long-press en el floor plan del teléfono. Tocar la luz en la lista, en
    // una card o en el floor plan de tablet abre LightColorScreen: por ahí la
    // feature no existía.
    Future<void> abrirColorScreen(WidgetTester tester, Device d) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final service = _service([d]);
      await tester.pumpWidget(MaterialApp(
        home: LightColorScreen(device: d, service: service),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('LightColorScreen muestra el modo y las escenas',
        (tester) async {
      await abrirColorScreen(tester, left);
      expect(find.text('MODO'), findsOneWidget);
      expect(find.text('ESCENAS'), findsOneWidget);
      // Las escenas por NOMBRE, no por id.
      expect(find.text('Aurora'), findsWidgets);
      expect(find.text('tuyascene_a'), findsNothing);
      expect(find.text('Guardar como escena'), findsOneWidget);
    });

    testWidgets('y una luz común no ve nada de eso', (tester) async {
      await abrirColorScreen(tester, hue);
      expect(find.text('MODO'), findsNothing);
      expect(find.text('ESCENAS'), findsNothing);
      expect(find.text('Guardar como escena'), findsNothing);
    });
  });

  group('review #3 — el revert de un comando fallido restaura', () {
    // `copyWith` no puede volver un campo a null (su parámetro nulo significa
    // «no lo toques»), así que revertir con copyWith sobre un device que no
    // tenía modo dejaba el modo puesto igual. El idioma correcto es el
    // snapshot completo, como en toggleLight.
    test('setLightMode sobre una luz sin modo previo revierte a sin modo',
        () async {
      final sinModo = Device.fromJson({
        ...Map<String, dynamic>.from(rightJson),
        'state': {'on': true, 'bri': 254, 'reachable': true},
      });
      final s = _service([sinModo]);
      await s.setLightMode(sinModo, 'colour');
      expect(sinModo.state.mode, isNull,
          reason: 'el modo optimista se DESHACE (copyWith no podía)');
    });

    test('setLightScene revierte el sceneId Y el modo', () async {
      // El optimismo mueve DOS campos; el revert viejo no restauraba ninguno y
      // dejaba la luz diciendo «modo escena» con una escena que nunca se activó.
      final enColor = Device.fromJson({
        ...Map<String, dynamic>.from(rightJson),
        'state': {'on': true, 'bri': 254, 'reachable': true, 'mode': 'colour'},
      });
      final s = _service([enColor]);
      await s.setLightScene(enColor, 'tuyascene_a');
      expect(enColor.state.sceneId, isNull, reason: 'la escena se deshace');
      expect(enColor.state.mode, 'colour', reason: 'y el modo vuelve a color');
    });

    test('el estado optimista se aplica ANTES de la respuesta', () async {
      // El chip tiene que moverse al toque, no cuando el backend contesta.
      final d = Device.fromJson(Map<String, dynamic>.from(rightJson));
      final s = _service([d]);
      final pendiente = s.setLightMode(d, 'scene');
      expect(d.state.mode, 'scene', reason: 'optimista, ya aplicado');
      expect(d.state.lightModes, _modes, reason: 'y sin perder el selector');
      await pendiente; // el backend no existe → revierte
      expect(d.state.mode, 'colour', reason: 'y al fallar vuelve a lo que era');
      expect(d.state.lightModes, _modes, reason: 'el revert no borra el selector');
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
