// CCE#115: EL VOCABULARIO de `contact`, no la línea que lo rompió.
//
// La vista unificada narraba `contact: true` como «Cerrado» mientras la tile,
// el historial, la alarma y el plano decían «Abierta» para el mismo booleano.
// Un test que sólo mirara esa pantalla no habría impedido nada: el bug no fue
// una línea mal escrita, fue OCHO archivos decidiendo la palabra por su cuenta.
//
// Por eso acá se prueban dos cosas:
//
//  1. EL RECORRIDO — se monta el MISMO device de contacto en todas las vistas
//     que lo narran y se exige que ninguna diga la palabra contraria. Agregar
//     una vista nueva es agregar una línea a `_narradores`.
//  2. LA FUENTE — ningún archivo de `lib/` que lea `contact` puede tener sus
//     propios literales «abierta/cerrada»: tienen que venir de
//     `ContactWords`. Esto es lo que cubre a las vistas que TODAVÍA NO EXISTEN.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_icons.dart';
import 'package:cce_app/theme/cce_theme.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/theme/mdi.dart';
import 'package:cce_app/utils/contact_words.dart';
import 'package:cce_app/utils/icon_resolver.dart';
import 'package:cce_app/views/alarm_view.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/sensor_detail_screen.dart';
import 'package:cce_app/views/unified_device_screen.dart';
import 'package:cce_app/widgets/featured_home_cards.dart';
import 'package:cce_app/widgets/sensor_tile.dart';

const _id = 'dev_puerta_cocina';

/// La puerta de la casa en miniatura. `contact: true` = ABIERTA (lo fija el
/// backend: el parser de eWeLink hace `contact: lock === 1`, y 1 es abierta).
Device _puerta(bool abierta) => Device(
      id: _id,
      name: 'Puerta cocina',
      type: 'contact sensor',
      capabilities: const ['sensor', 'contact'],
      state: DeviceState(),
      sensor: DeviceSensor(contact: abierta, battery: '100'),
    );

/// Puerto muerto en loopback: el `ServerConfig` por default apunta a la casa
/// REAL del dueño, y una pantalla que se escape del doble le hablaría.
DevicesService _servicio(Device d) {
  final s = DevicesService(
    config: ServerConfig(host: '127.0.0.1', port: 1),
    socket: SocketService(),
  );
  s.debugSeedDevices([d]);
  return s;
}

EventRecord _evento(bool abierta) => EventRecord(
      time: '2026-09-06T12:00:00.000Z',
      id: 'ev1',
      channel: 'websocket',
      eventName: 'device:state-changed',
      globalId: _id,
      payload: {
        'deviceId': _id,
        'sensor': {'contact': abierta},
      },
    );

/// Una vista que le cuenta al dueño el estado de una abertura.
class _Narrador {
  const _Narrador(
    this.nombre,
    this.construir, {
    this.diceElCierre = true,
  });

  final String nombre;
  final Widget Function(Device d, DevicesService s) construir;

  /// Las vistas de estado dicen las dos palabras; los badges de la home sólo
  /// aparecen cuando algo está ABIERTO y callan cuando está cerrado. A esas
  /// se les exige nada más que no mientan.
  final bool diceElCierre;
}

final _narradores = <_Narrador>[
  _Narrador('tile de sensor',
      (d, s) => SensorTile(device: d, service: s, interactive: false)),
  _Narrador('vista unificada por capabilities',
      (d, s) => UnifiedDeviceScreen(device: d, service: s)),
  _Narrador('detalle del sensor',
      (d, s) => SensorDetailScreen(device: d, service: s)),
  _Narrador('card destacada de la home',
      (d, s) => SensorHomeCard(device: d, service: s)),
  _Narrador(
    'qué protege (alarma)',
    (d, s) => ProtectedList(
      devices: s,
      triggers: const {_id: true},
      onConfigure: () {},
    ),
  ),
  _Narrador(
    'card de habitación',
    (d, s) => RoomCard(
      title: 'Cocina',
      icon: const Icon(Mdi.lightbulb),
      lightsOn: 0,
      lightsTotal: 1,
      anyOn: false,
      contactOpen: d.sensor?.contact == true,
      onTap: () {},
      onToggle: (_) {},
    ),
    diceElCierre: false,
  ),
  _Narrador(
    'historial de eventos',
    (d, s) => Text(presentEvent(_evento(d.sensor?.contact == true), s).title),
  ),
  _Narrador(
    'condición de una automatización',
    (d, s) => Text(conditionClause(
      AutomationCondition.sensor(
        sensorId: _id,
        field: 'contact',
        value: d.sensor?.contact == true,
      ),
      s,
    )),
  ),
];

/// Todo el texto que la vista pone en pantalla, junto.
String _textoVisible(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' ∥ ');

final _apertura = RegExp(r'abiert[ao]s?', caseSensitive: false);
final _cierre = RegExp(r'cerrad[ao]s?\b', caseSensitive: false);

void main() {
  group('el mapeo canónico', () {
    test('`contact: true` es ABIERTA', () {
      // Si esta línea se invierte, se invierte la App entera de una — que es
      // exactamente lo que este archivo quiere que pase en vez de que una sola
      // pantalla se desincronice en silencio.
      expect(ContactWords.label(true), 'Abierta');
      expect(ContactWords.label(false), 'Cerrada');
      expect(ContactWords.feminine(true), 'abierta');
      expect(ContactWords.masculine(true), 'abierto');
      expect(ContactWords.openCount(1), '1 abierta');
      expect(ContactWords.openCount(3), '3 abiertas');
    });

    test('el ícono acompaña a la palabra', () {
      expect(IconResolver.resolve(_puerta(true)), Mdi.doorOpen);
      expect(IconResolver.resolve(_puerta(false)), isNot(Mdi.doorOpen));
    });
  });

  group('el recorrido: ninguna vista invierte la palabra', () {
    for (final n in _narradores) {
      testWidgets('${n.nombre}: con contact:true dice ABIERTA',
          (tester) async {
        final d = _puerta(true);
        await tester.pumpWidget(MaterialApp(
          theme: CceTheme.dark(),
          home: Scaffold(body: n.construir(d, _servicio(d))),
        ));
        await tester.pump();
        final texto = _textoVisible(tester);
        expect(_apertura.hasMatch(texto), isTrue,
            reason: '«${n.nombre}» no dijo que la puerta está abierta: $texto');
        expect(_cierre.hasMatch(texto), isFalse,
            reason: '«${n.nombre}» narró contact:true como cerrada: $texto');
      });

      testWidgets('${n.nombre}: con contact:false NO dice abierta',
          (tester) async {
        final d = _puerta(false);
        await tester.pumpWidget(MaterialApp(
          theme: CceTheme.dark(),
          home: Scaffold(body: n.construir(d, _servicio(d))),
        ));
        await tester.pump();
        final texto = _textoVisible(tester);
        expect(_apertura.hasMatch(texto), isFalse,
            reason: '«${n.nombre}» narró contact:false como abierta: $texto');
        if (n.diceElCierre) {
          expect(_cierre.hasMatch(texto), isTrue,
              reason: '«${n.nombre}» no dijo que la puerta está cerrada: $texto');
        }
      });
    }

    testWidgets('la tile y la vista unificada dicen la MISMA palabra',
        (tester) async {
      // El bug en una frase: dos pantallas de la misma App diciendo lo
      // opuesto del mismo booleano.
      final d = _puerta(true);
      final s = _servicio(d);
      await tester.pumpWidget(MaterialApp(
        theme: CceTheme.dark(),
        home: Scaffold(
          body: SensorTile(device: d, service: s, interactive: false),
        ),
      ));
      await tester.pump();
      final tile = _apertura.firstMatch(_textoVisible(tester))!.group(0);

      await tester.pumpWidget(MaterialApp(
        theme: CceTheme.dark(),
        home: UnifiedDeviceScreen(device: d, service: s),
      ));
      await tester.pump();
      final unificada = _apertura.firstMatch(_textoVisible(tester))!.group(0);

      expect(unificada, tile);
      expect(tile, ContactWords.open);
    });
  });

  group('el disparador de automatización habla de ABRIR', () {
    final devices = _servicio(_puerta(false));

    test('sensorValue:true es que se abre', () {
      final frase = sensorTriggerPhrase(
        SensorTrigger(
            sensorId: _id, sensorField: 'contact', sensorValue: true),
        devices,
      );
      expect(frase, contains('abre'));
      expect(frase, isNot(contains('cierra')));
    });

    test('sensorValue:false es que se cierra', () {
      final frase = sensorTriggerPhrase(
        SensorTrigger(
            sensorId: _id, sensorField: 'contact', sensorValue: false),
        devices,
      );
      expect(frase, contains('cierra'));
    });
  });

  group('la fuente: el vocabulario vive en un solo archivo', () {
    // Este es el test que cubre las vistas que todavía no existen. El recorrido
    // de arriba sólo puede hablar de las vistas que alguien se acordó de
    // agregar a la lista; esto se lee el `lib/` entero.
    test('ningún archivo que lea `contact` se inventa sus palabras', () {
      const fuente = 'lib/utils/contact_words.dart';
      final menciona = RegExp(r'\bcontact\b');
      final vocabulario = RegExp(r'(abiert|cerrad)[ao]s?', caseSensitive: false);
      final literal = RegExp("'(?:[^'\\\\\\n]|\\\\.)*'"
          '|"(?:[^"\\\\\\n]|\\\\.)*"');

      final infractores = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.replaceAll(r'\', '/').endsWith(fuente)) continue;
        final codigo = _sinComentarios(f.readAsStringSync());
        if (!menciona.hasMatch(codigo)) continue;
        for (final m in literal.allMatches(codigo)) {
          if (vocabulario.hasMatch(m.group(0)!)) {
            infractores.add('${f.path} → ${m.group(0)}');
          }
        }
      }

      expect(
        infractores,
        isEmpty,
        reason: 'Estos archivos leen `contact` y deciden la palabra por su '
            'cuenta; así se rompió CCE#115. Las palabras salen de '
            'ContactWords ($fuente):\n  ${infractores.join('\n  ')}',
      );
    });

    test('el guard sabe encontrar el bug original', () {
      // Sin esto, un guard roto (una regex que no matchea nada) pasaría
      // siempre y el archivo entero sería decorativo.
      const linea =
          "if (s.contact != null) add('Contacto', s.contact! ? 'Cerrado' : 'Abierto');";
      final vocabulario = RegExp(r'(abiert|cerrad)[ao]s?', caseSensitive: false);
      final literal = RegExp("'(?:[^'\\\\\\n]|\\\\.)*'");
      expect(RegExp(r'\bcontact\b').hasMatch(linea), isTrue);
      expect(
        literal
            .allMatches(linea)
            .where((m) => vocabulario.hasMatch(m.group(0)!))
            .length,
        2,
      );
      // …y no confunde una cerradura con una abertura.
      expect(vocabulario.hasMatch("'Cerradura del frente'"), isFalse);
    });
  });

  group('los glifos del historial acompañan a la palabra', () {
    test('abierta lleva la puerta abierta; cerrada, la cerrada', () {
      final devices = _servicio(_puerta(true));
      final abierta = presentEvent(_evento(true), devices);
      final cerrada = presentEvent(_evento(false), devices);
      expect(abierta.title, contains(ContactWords.feminine(true)));
      expect(cerrada.title, contains(ContactWords.feminine(false)));
      expect(_svgDe(abierta.icon), CceIcons.doorOpen);
      expect(_svgDe(cerrada.icon), CceIcons.doorClosed);
    });
  });
}

/// El SVG que lleva adentro el ícono de una presentación de evento.
String? _svgDe(Widget icon) => icon is CceIcon ? icon.svg : null;

/// El código sin comentarios: un `// «Abierta» es contact:true` explicando la
/// convención no puede hacer fallar al guard.
String _sinComentarios(String src) {
  final sinBloques = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return sinBloques
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
      .join('\n');
}
