// CCE#54: los dispositivos DEDICADOS (Samsung TV / JBL) no caen en
// "Sin ubicación" cuando el plano los ubica.
//
// Su posición no vive en `positions` con las luces sino en un mapa propio, y
// la clave de ese mapa tiene DOS formatos conviviendo en la casa:
//
//   "edafc1f9-…"              → el aparato por defecto de la familia (legacy)
//   "733a3c72-…::tv-ce588d39" → un aparato concreto → device dev_tv-ce588d39
//
// La app leía sólo la primera y `rooms` ni miraba el mapa: el JBL estaba
// dibujado en el plano del Living y a la vez listado en "Sin ubicación", y el
// monitor del Office no aparecía en ningún lado.
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

// Ids reales de la casa (post CCE#47: el televisor histórico ya no es dev_tv).
const _living = 'edafc1f9-f85e-4a73-a08d-1de662cd89a7';
const _office = '733a3c72-6a36-433d-a6bb-53e6761a6946';
const _televisor = 'dev_tv-1ca02124';
const _monitor = 'dev_tv-ce588d39';

Device _light(String id, {bool on = true, int bri = 254, bool hidden = false}) =>
    Device(
      id: id,
      name: id,
      type: 'Extended color light',
      capabilities: const ['switch', 'brightness'],
      hidden: hidden,
      state: DeviceState(on: on, bri: bri),
    );

Device _tv(String id, {String name = 'Samsung', bool hidden = false}) => Device(
      id: id,
      name: name,
      type: 'tv',
      capabilities: const ['switch', 'volume', 'media_playback'],
      hidden: hidden,
      state: DeviceState(on: true),
    );

Device _jbl({bool hidden = false}) => Device(
      id: 'dev_jbl',
      name: 'JBL Bar',
      type: 'speaker',
      capabilities: const ['switch', 'volume'],
      hidden: hidden,
      state: DeviceState(),
    );

FloorPlan _plan(String id, String name) => FloorPlan(
      id: id,
      name: name,
      svg: '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 200 200"></svg>',
    );

/// El service con los planos de la casa (Living y Office) y los mapas de
/// posiciones que se le pasen, tal cual los devuelve la API.
DevicesService _service({
  required List<Device> devices,
  Map<String, Map<String, LightPosition>> positions = const {},
  Map<String, dynamic> jbl = const {},
  Map<String, dynamic> tv = const {},
}) {
  final service =
      DevicesService(config: ServerConfig(), socket: SocketService());
  service.debugSeedDevices(devices);
  service.debugSeedFloorPlans(FloorPlansData(
    plans: [_plan(_living, 'Living'), _plan(_office, 'Office')],
    activePlanId: _living,
    positions: positions,
    jblPositions: DedicatedPositions.fromJson(jbl),
    tvPositions: DedicatedPositions.fromJson(tv),
  ));
  return service;
}

/// Los devices de la habitación [name], o null si `rooms` no la armó.
List<String>? _room(DevicesService s, String name) {
  for (final r in s.rooms) {
    if (r.name == name) return r.deviceIds;
  }
  return null;
}

void main() {
  group('DedicatedPositions: las dos formas de la clave', () {
    test('la clave pelada es el plano y no nombra aparato', () {
      final p = DedicatedPositions.fromJson({
        _living: {'x': 33, 'y': 110},
      });
      expect(p.inPlan(_living).keys, [null]);
      expect(p.inPlan(_living)[null]!.x, 33);
      expect(p.hasPlan(_living), isTrue);
      expect(p.hasPlan(_office), isFalse);
      expect(p.hasPlan(null), isFalse);
    });

    test('la clave compuesta separa plano y aparato', () {
      final p = DedicatedPositions.fromJson({
        '$_office::tv-ce588d39': {'x': 95, 'y': 43},
      });
      expect(p.inPlan(_office).keys, ['tv-ce588d39']);
      expect(p.inPlan(_office)['tv-ce588d39']!.y, 43);
    });

    // Así está hoy la config de la casa: el televisor con clave vieja y el
    // monitor con clave nueva. Ninguna de las dos puede perderse.
    test('las dos formas conviven, cada una en su plano', () {
      final p = DedicatedPositions.fromJson({
        _living: {'x': 26, 'y': 110},
        '$_office::tv-ce588d39': {'x': 95, 'y': 43},
      });
      expect(p.byPlan.keys, {_living, _office});
      expect(p.inPlan(_living).keys, [null]);
      expect(p.inPlan(_office).keys, ['tv-ce588d39']);
    });

    test('dos aparatos en el MISMO plano no se pisan', () {
      final p = DedicatedPositions.fromJson({
        '$_living::tv-1ca02124': {'x': 1, 'y': 2},
        '$_living::tv-ce588d39': {'x': 3, 'y': 4},
      });
      expect(p.inPlan(_living).keys, ['tv-1ca02124', 'tv-ce588d39']);
    });

    test('lo que no es una posición se ignora en vez de romper', () {
      final p = DedicatedPositions.fromJson({
        _living: {'x': 5, 'y': 6},
        _office: 'basura',
        '::sin-plano': {'x': 1, 'y': 1},
      });
      expect(p.byPlan.keys, {_living});
    });
  });

  group('rooms: dónde cae cada device', () {
    test('sin mapas dedicados, las habitaciones son las de siempre', () {
      final s = _service(
        devices: [_light('dev_a'), _light('dev_b')],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
        },
      );
      expect(_room(s, 'Living'), ['dev_a']);
      expect(_room(s, 'Sin ubicación'), ['dev_b']);
    });

    test('el JBL ubicado en el Living aparece en el Living, no en huérfanos',
        () {
      final s = _service(
        devices: [_light('dev_a'), _jbl()],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
        },
        jbl: {
          _living: {'x': 33, 'y': 110},
        },
      );
      expect(_room(s, 'Living'), ['dev_a', 'dev_jbl']);
      // Y ya no hay "Sin ubicación": era el único que caía ahí.
      expect(_room(s, 'Sin ubicación'), isNull);
    });

    test('cada Samsung cae en su habitación: clave pelada y clave compuesta',
        () {
      final s = _service(
        devices: [
          _light('dev_a'),
          _light('dev_b'),
          _tv(_televisor, name: '65" OLED'),
          _tv(_monitor, name: '49" Odyssey OLED G9'),
        ],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
          _office: {'dev_b': LightPosition(2, 2)},
        },
        tv: {
          // pelada → el televisor, que es el único que ninguna clave reclama
          _living: {'x': 26, 'y': 110},
          '$_office::tv-ce588d39': {'x': 95, 'y': 43},
        },
      );
      expect(_room(s, 'Living'), ['dev_a', _televisor]);
      expect(_room(s, 'Office'), ['dev_b', _monitor]);
      expect(_room(s, 'Sin ubicación'), isNull);
    });

    test('la clave pelada sigue resolviendo al id histórico si existe', () {
      final s = _service(
        devices: [_light('dev_a'), _tv('dev_tv'), _tv(_monitor)],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
        },
        tv: {
          _living: {'x': 26, 'y': 110},
        },
      );
      expect(_room(s, 'Living'), ['dev_a', 'dev_tv']);
    });

    test('un dedicado oculto no aparece en ninguna habitación', () {
      final s = _service(
        devices: [_light('dev_a'), _jbl(hidden: true), _tv(_monitor, hidden: true)],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
        },
        jbl: {
          _living: {'x': 33, 'y': 110},
        },
        tv: {
          '$_office::tv-ce588d39': {'x': 95, 'y': 43},
        },
      );
      expect(_room(s, 'Living'), ['dev_a']);
      expect(_room(s, 'Office'), isNull);
      expect(_room(s, 'Sin ubicación'), isNull);
    });

    test('una posición de un aparato que ya no existe no inventa habitaciones',
        () {
      final s = _service(
        devices: [_light('dev_a')],
        positions: {
          _living: {'dev_a': LightPosition(1, 1)},
        },
        tv: {
          '$_office::tv-borrado': {'x': 95, 'y': 43},
        },
      );
      expect(_room(s, 'Office'), isNull);
      expect(s.dedicatedDeviceIdsIn(_office), isEmpty);
    });
  });

  group('stats: los dedicados no cuentan como luces', () {
    test('conteos y brillo promedio no se mueven al sumar el TV y el JBL', () {
      final luces = [_light('dev_a', bri: 254), _light('dev_b', bri: 127)];
      final positions = {
        _living: {
          'dev_a': LightPosition(1, 1),
          'dev_b': LightPosition(2, 2),
        },
      };
      final sinDedicados = _service(devices: luces, positions: positions);
      final conDedicados = _service(
        devices: [...luces, _jbl(), _tv(_televisor)],
        positions: positions,
        jbl: {
          _living: {'x': 33, 'y': 110},
        },
        tv: {
          _living: {'x': 26, 'y': 110},
        },
      );

      final antes = sinDedicados.statsFor(
          sinDedicados.rooms.firstWhere((r) => r.name == 'Living'));
      final room = conDedicados.rooms.firstWhere((r) => r.name == 'Living');
      final despues = conDedicados.statsFor(room);

      expect(room.deviceIds, ['dev_a', 'dev_b', _televisor, 'dev_jbl']);
      expect(despues.lightsTotal, antes.lightsTotal);
      expect(despues.lightsOn, antes.lightsOn);
      expect(despues.avgBrightness, antes.avgBrightness);
      expect(despues.tint, antes.tint);
    });
  });

  group('plano: un marker por aparato ubicado', () {
    // Los markers dedicados salen del inventario, así que los services van
    // vacíos a propósito: si el marker se pintara con ellos (como antes), un
    // aparato encendido se vería apagado y el segundo Samsung no existiría.
    Widget canvas(DevicesService service, String planId) => MaterialApp(
          home: Scaffold(
            body: FloorPlanPanel(
              service: service,
              ui: UiSettingsService(),
              planId: planId,
              showPlanChips: false,
              tv: TvService(config: ServerConfig(), socket: SocketService()),
              jbl: JblService(config: ServerConfig(), socket: SocketService()),
            ),
          ),
        );

    Finder samsung({Color? color}) => find.byWidgetPredicate((w) =>
        w is CceIcon &&
        w.svg == CceIcons.samsung &&
        (color == null || w.color == color));
    final jblGlyph = find.byWidgetPredicate(
        (w) => w is CceIcon && w.svg == CceIcons.jbl);

    DevicesService laCasa() => _service(
          devices: [
            _light('dev_a'),
            _light('dev_b'),
            _jbl(),
            _tv(_televisor),
            _tv(_monitor),
          ],
          positions: {
            _living: {'dev_a': LightPosition(20, 20)},
            _office: {'dev_b': LightPosition(20, 20)},
          },
          jbl: {
            _living: {'x': 33, 'y': 110},
          },
          tv: {
            _living: {'x': 26, 'y': 110},
            '$_office::tv-ce588d39': {'x': 95, 'y': 43},
          },
        );

    testWidgets('el Samsung de clave compuesta se dibuja en SU plano',
        (tester) async {
      await tester.pumpWidget(canvas(laCasa(), _office));
      await tester.pump();
      expect(samsung(), findsOneWidget);
      expect(jblGlyph, findsNothing, reason: 'el JBL está en el Living');
    });

    testWidgets('el de clave pelada y el JBL siguen en el Living',
        (tester) async {
      await tester.pumpWidget(canvas(laCasa(), _living));
      await tester.pump();
      expect(samsung(), findsOneWidget);
      expect(jblGlyph, findsOneWidget);
    });

    testWidgets('cada marker pinta el estado de SU aparato', (tester) async {
      final s = _service(
        devices: [
          _tv(_televisor)..state = DeviceState(on: false),
          _tv(_monitor)..state = DeviceState(on: true),
        ],
        positions: {},
        tv: {
          _living: {'x': 26, 'y': 110},
          '$_office::tv-ce588d39': {'x': 95, 'y': 43},
        },
      );
      // Azul de marca = encendido y alcanzable; gris = lo contrario.
      const encendido = Color(0xFF3A6BC5);

      await tester.pumpWidget(canvas(s, _office));
      await tester.pump();
      expect(samsung(color: encendido), findsOneWidget);

      await tester.pumpWidget(canvas(s, _living));
      await tester.pump();
      expect(samsung(color: encendido), findsNothing,
          reason: 'el televisor del Living está apagado');
    });
  });
}
