// CCE#129 — el gráfico del termómetro. Lo que se prueba acá, en orden de
// importancia:
//
//   1. EL RÓTULO NO MIENTE. El sparkline viejo pedía los últimos 1000 eventos
//      y recién ahí descartaba los de más de siete días: con un sensor que
//      reporta seguido, mostraba doce horas bajo un cartel que decía "ÚLTIMOS
//      7 DÍAS". Ahora el rango va al servidor y el rótulo sale de lo que el
//      servidor CONTESTA (`from`/`to` de la respuesta), no del botón apretado.
//      Por eso el servidor de mentira contesta un rango DISTINTO del pedido:
//      si el widget rotulara el preset, el test no lo notaría.
//   2. El pedido lleva el rango elegido y TODOS los bindings del device (un
//      termómetro está mergeado entre eWeLink y Matter).
//   3. Las dos series con su leyenda, y un termómetro sin humedad sin leyenda
//      fantasma.
//   4. Los estados honestos: sin lecturas, error de red.
//   5. El termostato usa el mismo componente pidiendo `currentTemp`.
//
// La API es de mentira (MockClient por `runWithClient`, como
// automations_order_test): ApiService usa las funciones top-level de
// `package:http`, que miran la zona.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_series.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/thermometer_screen.dart';
import 'package:cce_app/widgets/sensor_history_chart.dart';

// ── el servidor de mentira ─────────────────────────────────────────────────

/// Contesta `GET /events/series` con las series que se le pasen y anota cada
/// URL pedida. `from`/`to` de la respuesta son FIJOS y distintos del rango que
/// pide el widget: es lo que deja ver de dónde sale el rótulo.
class _FakeApi {
  _FakeApi({required this.series, this.from, this.to, this.bucket = '5m'});

  final List<Map<String, dynamic>> series;
  final DateTime? from;
  final DateTime? to;
  final String bucket;

  int status = 200;
  bool enabled = true;
  final urls = <Uri>[];

  DateTime get _from => from ?? DateTime(2026, 9, 1, 10);
  DateTime get _to => to ?? DateTime(2026, 9, 8, 10);

  http.Client client() => MockClient((req) async {
        if (req.url.path.endsWith('/events/series')) {
          urls.add(req.url);
          if (status != 200) return http.Response('{"error":true}', status);
          return http.Response(
            jsonEncode({
              'bucket': bucket,
              'bucketSeconds': 300,
              'from': _from.toUtc().toIso8601String(),
              'to': _to.toUtc().toIso8601String(),
              'series': series,
              'enabled': enabled,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      });
}

Map<String, dynamic> serie(
  String globalId,
  String field,
  String unit,
  List<(DateTime, double)> puntos, {
  int count = 3,
}) =>
    {
      'globalId': globalId,
      'field': field,
      'unit': unit,
      'points': [
        for (final (t, v) in puntos)
          {
            't': t.toUtc().toIso8601String(),
            'avg': v,
            'min': v - 1,
            'max': v + 1,
            'count': count,
          },
      ],
    };

const livingId = 'dev_8c73dafffe29f425';
const bindingEwelink = 'ewelink_acc4001d73';
const bindingMatter = 'matter_6031124286547841337_80';

Device termometro({double? humidity, List<String>? bindings}) =>
    Device.fromJson({
      'id': livingId,
      'name': 'Termómetro living',
      'type': 'eWeLink Sensor',
      'capabilities': ['sensor', 'temperature'],
      'bindings': [
        for (final b in bindings ?? const [bindingEwelink, bindingMatter])
          {'bindingId': b},
      ],
      'state': {'on': false, 'bri': 1, 'reachable': true},
      'sensor': {'temperature': 21.9, 'humidity': ?humidity, 'battery': '100'},
    });

Future<void> pumpTermometro(WidgetTester tester, Device d) async {
  final service = DevicesService(
    config: ServerConfig(host: '127.0.0.1', port: 1),
    socket: SocketService(),
  );
  service.debugSeedDevices([d]);
  await tester.pumpWidget(
    MaterialApp(home: ThermometerScreen(device: d, service: service)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // ── las funciones del eje ────────────────────────────────────────────────
  group('rangeLabel — el rótulo dice la fecha, no "últimos N días"', () {
    test('un rango de horas dentro del mismo día: día y horas', () {
      final label = rangeLabel(DateTime(2026, 9, 8, 9, 12), DateTime(2026, 9, 8, 21, 12));
      expect(label, '8 sep · 09:12 – 21:12');
    });

    test('24 h a caballo de la medianoche: los dos días con su hora', () {
      final label = rangeLabel(DateTime(2026, 9, 7, 21, 5), DateTime(2026, 9, 8, 21, 5));
      expect(label, '7 sep 21:05 – 8 sep 21:05');
    });

    test('varios días: sólo los días', () {
      final label = rangeLabel(DateTime(2026, 9, 1, 10), DateTime(2026, 9, 8, 10));
      expect(label, '1 sep – 8 sep');
    });

    test('30 días cruzando el mes', () {
      final label = rangeLabel(DateTime(2026, 8, 9), DateTime(2026, 9, 8));
      expect(label, '9 ago – 8 sep');
    });
  });

  group('bucketLabel — qué es cada punto', () {
    test('los anchos que devuelve el servidor', () {
      expect(bucketLabel('5m'), 'prom. 5 min');
      expect(bucketLabel('1h'), 'prom. 1 h');
      expect(bucketLabel('1d'), 'prom. 1 día');
    });

    test('un ancho que la app no conoce no rompe el rótulo', () {
      expect(bucketLabel('12h'), 'promedio');
    });
  });

  group('valueTicks — las marcas del eje de valores', () {
    test('números redondos dentro del rango', () {
      final ticks = valueTicks(18.3, 24.7);
      expect(ticks, isNotEmpty);
      for (final t in ticks) {
        expect(t, greaterThanOrEqualTo(18.3));
        expect(t, lessThanOrEqualTo(24.7));
      }
      expect(ticks, contains(20.0));
    });

    test('una línea plana devuelve su propio valor y no una lista vacía', () {
      expect(valueTicks(21.9, 21.9), [21.9]);
    });

    test('un rango grande no devuelve treinta marcas', () {
      expect(valueTicks(0, 1000).length, lessThanOrEqualTo(8));
    });
  });

  group('timeTicks — las marcas del eje de tiempo', () {
    test('24 h: horas, todas dentro del rango', () {
      final from = DateTime(2026, 9, 7, 21, 5);
      final ticks = timeTicks(from, from.add(const Duration(hours: 24)));
      expect(ticks.length, greaterThanOrEqualTo(3));
      expect(ticks.length, lessThanOrEqualTo(6));
      expect(ticks.first.label, endsWith('h'));
      for (final tk in ticks) {
        expect(tk.t.isBefore(from), isFalse);
        expect(tk.t.isAfter(from.add(const Duration(hours: 24))), isFalse);
      }
    });

    test('7 días: fechas, no horas', () {
      final from = DateTime(2026, 9, 1);
      final ticks = timeTicks(from, from.add(const Duration(days: 7)));
      expect(ticks, isNotEmpty);
      expect(ticks.length, lessThanOrEqualTo(6));
      expect(ticks.first.label, contains('/'));
    });

    test('30 días: el paso crece para que no se amontonen', () {
      final from = DateTime(2026, 8, 9);
      final ticks = timeTicks(from, from.add(const Duration(days: 30)));
      expect(ticks.length, lessThanOrEqualTo(6));
    });
  });

  // ── la fusión de bindings ────────────────────────────────────────────────
  group('EventSeriesPage.merged — un aparato, una línea', () {
    EventSeriesPage page(List<Map<String, dynamic>> series) =>
        EventSeriesPage.fromJson({
          'bucket': '1h',
          'bucketSeconds': 3600,
          'from': DateTime(2026, 9, 1).toUtc().toIso8601String(),
          'to': DateTime(2026, 9, 2).toUtc().toIso8601String(),
          'series': series,
          'enabled': true,
        });

    test('los dos bindings del termómetro se unen y quedan ordenados', () {
      final t0 = DateTime(2026, 9, 1, 10);
      final t1 = DateTime(2026, 9, 1, 11);
      final p = page([
        serie(bindingMatter, 'temperature', '°C', [(t1, 22)]),
        serie(bindingEwelink, 'temperature', '°C', [(t0, 21)]),
      ]);
      final points = p.merged('temperature');
      expect(points.map((e) => e.avg).toList(), [21, 22]);
      expect(points.first.t.isBefore(points.last.t), isTrue);
    });

    test('el mismo bucket por los dos caminos es UN punto, ponderado por count',
        () {
      final t0 = DateTime(2026, 9, 1, 10);
      final p = page([
        serie(bindingEwelink, 'temperature', '°C', [(t0, 21)], count: 30),
        serie(bindingMatter, 'temperature', '°C', [(t0, 23)], count: 10),
      ]);
      final points = p.merged('temperature');
      expect(points, hasLength(1), reason: 'no se dibuja dos veces el mismo bucket');
      expect(points.first.avg, closeTo((21 * 30 + 23 * 10) / 40, 0.001));
      expect(points.first.count, 40);
      expect(points.first.min, 20, reason: 'el mínimo es el de los dos');
      expect(points.first.max, 24);
    });

    test('un campo que ninguna serie trae da una lista vacía, no un error', () {
      final p = page([
        serie(bindingEwelink, 'temperature', '°C', [(DateTime(2026, 9, 1, 10), 21)]),
      ]);
      expect(p.merged('humidity'), isEmpty);
      expect(p.unitOf('temperature'), '°C');
    });

    test('la hora llega en UTC y se guarda en local', () {
      final t = DateTime(2026, 9, 1, 10);
      final p = page([serie(bindingEwelink, 'temperature', '°C', [(t, 21)])]);
      expect(p.merged('temperature').first.t, t);
      expect(p.merged('temperature').first.t.isUtc, isFalse);
    });
  });

  // ── la pantalla ──────────────────────────────────────────────────────────
  group('el detalle del termómetro', () {
    final t0 = DateTime(2026, 9, 1, 10);
    List<Map<String, dynamic>> conHumedad() => [
          serie(bindingEwelink, 'temperature', '°C', [
            (t0, 20.0),
            (t0.add(const Duration(hours: 1)), 23.0),
          ]),
          serie(bindingEwelink, 'humidity', '%', [
            (t0, 28.0),
            (t0.add(const Duration(hours: 1)), 34.0),
          ]),
        ];

    testWidgets('muestra las dos series con su leyenda y su mín–máx',
        (tester) async {
      final api = _FakeApi(series: conHumedad());
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(find.textContaining('Temperatura'), findsWidgets);
        expect(find.textContaining('Humedad'), findsWidgets);
        // El mín–máx sale de min/max de los puntos, no del promedio.
        expect(find.text('Temperatura 19.0° – 24.0°'), findsOneWidget);
        expect(find.text('Humedad 27% – 35%'), findsOneWidget);
      }, api.client);
    });

    testWidgets('EL RÓTULO ES EL RANGO QUE CONTESTÓ EL SERVIDOR, no el preset',
        (tester) async {
      // El preset arranca en 24 H; el servidor contesta del 1 al 8 de
      // septiembre. Si el widget rotulara el botón, diría las últimas 24 h.
      final api = _FakeApi(
        series: conHumedad(),
        from: DateTime(2026, 9, 1, 10),
        to: DateTime(2026, 9, 8, 10),
        bucket: '1h',
      );
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(find.text('1 sep – 8 sep · prom. 1 h'), findsOneWidget);
        expect(find.textContaining('7 DÍAS'), findsNothing);

        // Y el pedido llevó el rango del preset elegido (24 h), no un límite
        // de filas: es la otra mitad del arreglo.
        expect(api.urls, hasLength(1));
        final q = api.urls.single.queryParameters;
        final desde = DateTime.parse(q['from']!);
        final hasta = DateTime.parse(q['to']!);
        expect(
          hasta.difference(desde).inMinutes,
          closeTo(24 * 60, 2),
          reason: 'el preset 24 H pide 24 horas',
        );
      }, api.client);
    });

    testWidgets('pide TODOS los bindings del device y los campos del termómetro',
        (tester) async {
      final api = _FakeApi(series: conHumedad());
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        final q = api.urls.single.queryParameters;
        expect(q['globalIds'], '$bindingEwelink,$bindingMatter');
        expect(q['fields'], 'temperature,humidity');
        expect(q['bucket'], 'auto');
      }, api.client);
    });

    testWidgets('cambiar de 24 H a 7 D pide el rango nuevo y cambia el rótulo',
        (tester) async {
      final api = _FakeApi(series: conHumedad(), bucket: '1h');
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(api.urls, hasLength(1));
        final q24 = api.urls.first.queryParameters;

        await tester.tap(find.text('7 D'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(api.urls, hasLength(2), reason: 'el cambio de rango vuelve a pedir');
        final q7 = api.urls.last.queryParameters;
        final span24 = DateTime.parse(q24['to']!).difference(DateTime.parse(q24['from']!));
        final span7 = DateTime.parse(q7['to']!).difference(DateTime.parse(q7['from']!));
        expect(span24.inHours, closeTo(24, 1));
        expect(span7.inDays, closeTo(7, 1));
      }, api.client);
    });

    testWidgets('tocar el gráfico dice la hora y el valor de ESE punto',
        (tester) async {
      // Dos lecturas bien separadas dentro del rango: tocar a la izquierda y
      // tocar a la derecha tienen que dar respuestas DISTINTAS. Con los dos
      // puntos pegados, cualquier mapeo x→punto pasaría el test.
      final manana = DateTime(2026, 9, 1, 10);
      final tarde = DateTime(2026, 9, 1, 20);
      final api = _FakeApi(
        bucket: '1h',
        from: DateTime(2026, 9, 1, 8),
        to: DateTime(2026, 9, 1, 22),
        series: [
          serie(bindingEwelink, 'temperature', '°C', [(manana, 20.0), (tarde, 23.0)]),
          serie(bindingEwelink, 'humidity', '%', [(manana, 28.0), (tarde, 34.0)]),
        ],
      );
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        // Sin tocar no hay ninguna lectura puntual en pantalla.
        expect(find.textContaining('1/9 10:00'), findsNothing);
        expect(find.textContaining('1/9 20:00'), findsNothing);

        final plot = find.byKey(const ValueKey('sensor-history-plot'));
        expect(plot, findsOneWidget, reason: 'el gráfico se dibujó');
        final box = tester.getRect(plot);

        await tester.tapAt(Offset(box.left + 2, box.center.dy));
        await tester.pump();
        expect(find.text('1/9 10:00 · 20.0° · 28%'), findsOneWidget);

        await tester.tapAt(Offset(box.right - 2, box.center.dy));
        await tester.pump();
        expect(find.text('1/9 20:00 · 23.0° · 34%'), findsOneWidget);
        expect(find.textContaining('1/9 10:00'), findsNothing);
      }, api.client);
    });

    testWidgets('un termómetro sin humedad muestra una sola serie, sin leyenda fantasma',
        (tester) async {
      // El servidor devuelve igual la serie pedida, vacía: "no hubo datos" es
      // una respuesta, y es la app la que decide no dibujar una línea sin
      // puntos.
      final api = _FakeApi(series: [
        serie(bindingEwelink, 'temperature', '°C', [(t0, 20.0), (t0.add(const Duration(hours: 1)), 23.0)]),
        serie(bindingEwelink, 'humidity', '%', const []),
      ]);
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro());
        expect(find.textContaining('Temperatura'), findsWidgets);
        expect(find.textContaining('Humedad'), findsNothing);
      }, api.client);
    });

    testWidgets('un rango sin lecturas lo dice, no deja el gráfico en blanco',
        (tester) async {
      final api = _FakeApi(series: [
        serie(bindingEwelink, 'temperature', '°C', const []),
        serie(bindingEwelink, 'humidity', '%', const []),
      ]);
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(find.text('Sin lecturas en este rango'), findsOneWidget);
      }, api.client);
    });

    testWidgets('un error de red se dice y se puede reintentar', (tester) async {
      final api = _FakeApi(series: conHumedad())..status = 500;
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(find.text('No se pudo cargar el historial'), findsOneWidget);

        api.status = 200;
        await tester.tap(find.text('Reintentar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('No se pudo cargar el historial'), findsNothing);
        expect(find.textContaining('Temperatura'), findsWidgets);
      }, api.client);
    });

    testWidgets('con el event store apagado no dice "sin lecturas"', (tester) async {
      final api = _FakeApi(series: const [])..enabled = false;
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        expect(find.text('El historial está desactivado'), findsOneWidget);
        expect(find.text('Sin lecturas en este rango'), findsNothing);
      }, api.client);
    });

    testWidgets('el botón FECHAS abre el calendario para elegir un rango',
        (tester) async {
      final api = _FakeApi(series: conHumedad());
      await http.runWithClient(() async {
        await pumpTermometro(tester, termometro(humidity: 28));
        await tester.tap(find.text('FECHAS'));
        await tester.pumpAndSettle();
        expect(find.text('Rango del historial'), findsOneWidget);
      }, api.client);
    });
  });

  group('el termostato usa el mismo componente', () {
    testWidgets('pide currentTemp, que es donde publica su temperatura ambiente',
        (tester) async {
      final api = _FakeApi(series: [
        serie('tuya_eb2f35fed4865c1678qroe', 'currentTemp', '°C', [
          (DateTime(2026, 9, 1, 10), 20.4),
          (DateTime(2026, 9, 1, 11), 21.0),
        ]),
      ]);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SensorHistoryChart(
              config: ServerConfig(host: '127.0.0.1', port: 1),
              globalIds: const ['tuya_eb2f35fed4865c1678qroe'],
              fields: const ['currentTemp'],
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(api.urls.single.queryParameters['fields'], 'currentTemp');
        // Y se dibuja con el nombre y el color de la temperatura, que es lo
        // que es: la misma lectura por otro camino.
        expect(find.textContaining('Temperatura'), findsWidgets);
      }, api.client);
    });
  });
}
