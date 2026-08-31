// CCE#60: cada ícono del plano tiene su GIRO y su TAMAÑO, acomodados desde el
// dashboard, y la app los refleja.
//
// Acá no hay edición: el plano de la app dibuja lo que el dashboard acomodó. Lo
// que este test protege es justamente eso — que un ícono girado y agrandado en
// el dashboard se vea igual en la app, porque si no se toca, el mismo plano se
// vería distinto en cada pantalla, que es peor que no tener la función.
//
// Y protege lo otro, que importa más: una posición VIEJA (sin los campos
// nuevos) se dibuja exactamente como se dibujaba antes. Cuando esto se escribió
// había 59 guardadas en la casa y ninguna los tenía.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/floor_plan.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/jbl_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/tv_service.dart';
import 'package:cce_app/services/ui_settings_service.dart';
import 'package:cce_app/theme/cce_icons.dart';
import 'package:cce_app/views/floor_plan_tab.dart';

const _living = 'edafc1f9-f85e-4a73-a08d-1de662cd89a7';

Device _light(String id) => Device(
      id: id,
      name: id,
      type: 'Extended color light',
      capabilities: const ['switch', 'brightness'],
      state: DeviceState(on: true, bri: 254),
    );

Device _jbl() => Device(
      id: 'dev_jbl',
      name: 'JBL Bar',
      type: 'speaker',
      capabilities: const ['switch', 'volume'],
      state: DeviceState(on: true),
    );

FloorPlan _plan({double? markerScale}) => FloorPlan(
      id: _living,
      name: 'Living',
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"></svg>',
      markerScale: markerScale,
    );

DevicesService _service({
  required List<Device> devices,
  Map<String, Map<String, LightPosition>> positions = const {},
  Map<String, dynamic> jbl = const {},
  double? markerScale,
}) {
  final service = DevicesService(config: ServerConfig(), socket: SocketService());
  service.debugSeedDevices(devices);
  service.debugSeedFloorPlans(FloorPlansData(
    plans: [_plan(markerScale: markerScale)],
    activePlanId: _living,
    positions: positions,
    jblPositions: DedicatedPositions.fromJson(jbl),
    tvPositions: DedicatedPositions.empty,
  ));
  return service;
}

Widget _canvas(DevicesService service) => MaterialApp(
      home: Scaffold(
        body: FloorPlanPanel(
          service: service,
          ui: UiSettingsService(),
          planId: _living,
          showPlanChips: false,
          tv: TvService(config: ServerConfig(), socket: SocketService()),
          jbl: JblService(config: ServerConfig(), socket: SocketService()),
        ),
      ),
    );

void main() {
  group('LightPosition.fromJson: los campos nuevos', () {
    test('los lee cuando vienen', () {
      final p = LightPosition.fromJson({
        'x': 26,
        'y': 110,
        'rotation': 90,
        'scale': 1.5,
      });
      expect(p.rotation, 90);
      expect(p.scale, 1.5);
      expect(p.rotationRadians, closeTo(math.pi / 2, 1e-9));
      expect(p.scaleFactor, 1.5);
    });

    test('una posición VIEJA vale rotation 0 y scale 1', () {
      // El contrato que comparten la API, el dashboard y la app.
      final p = LightPosition.fromJson({'x': 33, 'y': 110});
      expect(p.rotation, isNull);
      expect(p.scale, isNull);
      expect(p.rotationRadians, 0);
      expect(p.scaleFactor, 1);
    });

    test('valores rotos se descartan en vez de romper el dibujo', () {
      // Un NaN en un Transform no lanza: pinta un marcador INVISIBLE, que es
      // muchísimo peor que ignorar el campo.
      final p = LightPosition.fromJson({
        'x': 1,
        'y': 2,
        'rotation': double.nan,
        'scale': double.infinity,
      });
      expect(p.rotation, isNull);
      expect(p.scale, isNull);
      expect(p.rotationRadians, 0);
      expect(p.scaleFactor, 1);

      final texto = LightPosition.fromJson({'x': 1, 'y': 2, 'rotation': '90'});
      expect(texto.rotation, isNull);
    });

    test('el constructor sigue aceptando sólo x e y', () {
      // Lo que ya usaban los otros tests y el resto de la app.
      final p = LightPosition(3, 4);
      expect(p.rotationRadians, 0);
      expect(p.scaleFactor, 1);
    });

    test('los campos nuevos viajan también por la clave COMPUESTA', () {
      // `samsungTvPositions` tiene dos formas de clave conviviendo y los campos
      // nuevos aplican igual a las dos (CCE#46 + CCE#60).
      final p = DedicatedPositions.fromJson({
        '$_living::tv-ce588d39': {'x': 95, 'y': 43, 'rotation': 45, 'scale': 2},
      });
      final pos = p.inPlan(_living)['tv-ce588d39']!;
      expect(pos.rotation, 45);
      expect(pos.scaleFactor, 2);
    });
  });

  group('el plano dibuja lo que el dashboard acomodó', () {
    /// La caja que ocupa la píldora del aparato EN PANTALLA, ya con su giro
    /// aplicado (`getRect` pasa por `localToGlobal`, así que a 90° el ancho y
    /// el alto salen intercambiados). Se mide el resultado visible y no el
    /// widget del `Transform`: lo que el issue pide es que el marcador se VEA
    /// parado o acostado.
    Rect cajaDeLaPildora(WidgetTester tester) {
      final pildora = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border != null &&
          (w.decoration! as BoxDecoration).borderRadius != null);
      return tester.getRect(pildora.first);
    }

    /// Cuánto mide de lado a lado el dot del ÚNICO device del plano: el
    /// diámetro del círculo con el que se dibuja, que es `dotSize` — el tamaño
    /// del plano por el del ícono.
    double anchoDelMarcador(WidgetTester tester) {
      final circulo = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle);
      return tester.getSize(circulo.first).width;
    }

    final jblGlyph =
        find.byWidgetPredicate((w) => w is CceIcon && w.svg == CceIcons.jbl);

    testWidgets('el soundbar arranca girado 90°, como se vio siempre',
        (tester) async {
      // Los 90° que la migración de la API le escribió a lo que ya estaba
      // ubicado: el marcador tiene que verse EXACTAMENTE como antes del #60,
      // cuando la píldora se dibujaba vertical por construcción.
      await tester.pumpWidget(_canvas(_service(
        devices: [_jbl()],
        jbl: {
          _living: {'x': 33, 'y': 110, 'rotation': 90},
        },
      )));
      await tester.pump();

      expect(jblGlyph, findsOneWidget);
      final caja = cajaDeLaPildora(tester);
      expect(caja.height, greaterThan(caja.width * 2),
          reason: 'con 90° la barra se ve PARADA, como antes del #60');
    });

    testWidgets('sin giro guardado, el soundbar queda acostado',
        (tester) async {
      // La otra mitad de la función: con `rotation: 0` la barra se ve
      // horizontal. Antes del #60 esto era imposible — estaba en el dibujo.
      await tester.pumpWidget(_canvas(_service(
        devices: [_jbl()],
        jbl: {
          _living: {'x': 33, 'y': 110, 'rotation': 0},
        },
      )));
      await tester.pump();

      final caja = cajaDeLaPildora(tester);
      expect(caja.width, greaterThan(caja.height * 2),
          reason: 'con 0° la barra se ve ACOSTADA');
    });

    testWidgets('el tamaño de un ícono MULTIPLICA el del plano',
        (tester) async {
      final sinAjuste = _service(
        devices: [_light('dev_a')],
        markerScale: 1.0,
        positions: {
          _living: {'dev_a': LightPosition(50, 50)},
        },
      );
      await tester.pumpWidget(_canvas(sinAjuste));
      await tester.pump();
      final base = anchoDelMarcador(tester);

      final alDoble = _service(
        devices: [_light('dev_a')],
        markerScale: 1.0,
        positions: {
          _living: {'dev_a': LightPosition(50, 50, scale: 2)},
        },
      );
      await tester.pumpWidget(_canvas(alDoble));
      await tester.pump();
      expect(
        anchoDelMarcador(tester),
        closeTo(base * 2, 0.01),
        reason: 'scale: 2 sobre el mismo markerScale es el doble de ancho',
      );

      // Y subir el tamaño del PLANO agranda lo ajustado a mano en la misma
      // proporción, en vez de reemplazarlo.
      final planoMasGrande = _service(
        devices: [_light('dev_a')],
        markerScale: 1.5,
        positions: {
          _living: {'dev_a': LightPosition(50, 50, scale: 2)},
        },
      );
      await tester.pumpWidget(_canvas(planoMasGrande));
      await tester.pump();
      expect(
        anchoDelMarcador(tester),
        closeTo(base * 3, 0.01),
        reason: 'markerScale 1.5 × scale 2 = 3 veces el tamaño base',
      );
    });
  });
}
