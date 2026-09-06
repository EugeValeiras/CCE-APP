// CCE#115: EL VOCABULARIO de `contact`, no la línea que lo rompió.
//
// La vista unificada narraba `contact: true` como «Cerrado» mientras la tile,
// el historial, la alarma y el plano decían «Abierta» para el mismo booleano.
// Un test que sólo mirara esa pantalla no habría impedido nada: el bug no fue
// una línea mal escrita, fue una docena de archivos decidiendo la palabra por
// su cuenta.
//
// El vocabulario tiene DOS mitades y las dos se prueban acá:
//
//  · el ADJETIVO — «Abierta / Cerrada» — con el que las vistas cuentan cómo
//    está la puerta;
//  · el VERBO — «Se abre / se abra» — con el que las automatizaciones cuentan
//    lo que le pasa. El verbo es el que más pesa: el editor de disparadores no
//    LEE la convención, la ESCRIBE. Si «Se cierra» guardara `sensorValue:
//    true`, el dueño se quedaría con una automatización que dispara al revés
//    de lo que eligió.
//
// Tres partes:
//
//  1. EL RECORRIDO — el MISMO device de contacto montado en todas las vistas
//     que lo narran, exigiendo que ninguna diga —ni DIBUJE— lo contrario.
//     Agregar una vista es agregar una línea a `_narradores`.
//  2. EL EDITOR — la única pantalla que escribe el valor, probada por el
//     camino real (el sheet montado), no por su literal.
//  3. LA FUENTE — ningún archivo de `lib/` que nombre `contact` puede tener
//     sus propios literales del vocabulario: salen de `ContactWords`. Esto es
//     lo que cubre a las vistas que TODAVÍA NO EXISTEN, y por eso tiene su
//     propio meta-test, que ejercita EL MISMO guard (no una copia).
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
import 'package:cce_app/theme/components/cce_segmented.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/theme/mdi.dart';
import 'package:cce_app/utils/contact_words.dart';
import 'package:cce_app/utils/icon_resolver.dart';
import 'package:cce_app/views/alarm_view.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';
import 'package:cce_app/views/automations/sheets/trigger_sheet.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/sensor_detail_screen.dart';
import 'package:cce_app/views/unified_device_screen.dart';
import 'package:cce_app/widgets/featured_home_cards.dart';
import 'package:cce_app/widgets/sensor_tile.dart';

// ═══ EL GUARD ══════════════════════════════════════════════════════════════
// Vive acá arriba, en una sola copia, porque lo usan DOS tests: el que escanea
// `lib/` y el meta-test que se asegura de que sepa encontrar algo. Si estas
// declaraciones se rompen, los dos se caen juntos — que es exactamente lo que
// NO pasaba cuando el meta-test tenía sus propias copias de las regexes.

/// Un archivo narra el contacto si lo NOMBRA de cualquier forma: `s.contact`,
/// `sensor['contact']`, `isContactSensor`, o —la que se escapaba— recibiéndolo
/// como prop, `bool contactOpen`, que es la forma de [RoomCard].
final menciona = RegExp('[Cc]ontact');

/// Las cuatro palabras del vocabulario, cada una en UNA declaración: el
/// adjetivo del estado y el verbo del hecho, en sus dos polaridades.
///
/// El verbo pide el «se» adelante a propósito: «abre» sola es de la CERRADURA
/// («abre con huella», `lockOpenWay`), que es otro aparato y otra palabra.
final _adjetivoAbierta = RegExp(r'abiert[ao]s?', caseSensitive: false);
final _adjetivoCerrada = RegExp(r'cerrad[ao]s?', caseSensitive: false);
final _verboAbrir = RegExp(r'\bse abr[ae]n?\b', caseSensitive: false);
final _verboCerrar = RegExp(r'\bse cierr[ae]n?\b', caseSensitive: false);

/// El vocabulario entero, DERIVADO de las cuatro de arriba: el guard busca
/// exactamente las mismas palabras que el recorrido le exige a cada vista, y
/// una no puede quedar desincronizada de la otra.
final vocabulario = RegExp(
  [_adjetivoAbierta, _adjetivoCerrada, _verboAbrir, _verboCerrar]
      .map((r) => r.pattern)
      .join('|'),
  caseSensitive: false,
);

/// Los literales del vocabulario que [fuente] decide por su cuenta, o vacío si
/// no decide ninguno (porque no nombra `contact`, o porque los toma de
/// [ContactWords]).
List<String> palabrasSueltas(String fuente) {
  final (:codigo, :literales) = _lexer(fuente);
  final nombra = menciona.hasMatch(codigo) || literales.any(menciona.hasMatch);
  if (!nombra) return const [];
  return [
    for (final l in literales)
      if (vocabulario.hasMatch(l)) l,
  ];
}

/// Separa el código de sus literales de string, salteando comentarios.
///
/// Un lexer mínimo, pero DE VERDAD: la versión anterior borraba de `//` hasta
/// el fin de la línea con una regex y se comía media línea cada vez que un
/// string llevaba una URL (`'https://casa.local'`, que ya existe en
/// `cce_icons.dart` y `hue_badge.dart`) — o sea, dejaba agujeros por los que se
/// colaba justo lo que el guard busca.
({String codigo, List<String> literales}) _lexer(String fuente) {
  final codigo = StringBuffer();
  final literales = <String>[];
  var i = 0;
  while (i < fuente.length) {
    final c = fuente[i];
    final sig = i + 1 < fuente.length ? fuente[i + 1] : '';
    if (c == '/' && sig == '/') {
      while (i < fuente.length && fuente[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && sig == '*') {
      i += 2;
      while (i + 1 < fuente.length &&
          !(fuente[i] == '*' && fuente[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final delim = fuente.startsWith(c * 3, i) ? c * 3 : c;
      i += delim.length;
      final buf = StringBuffer();
      while (i < fuente.length) {
        if (fuente[i] == '\\') {
          i += 2;
          continue;
        }
        if (fuente.startsWith(delim, i)) {
          i += delim.length;
          break;
        }
        buf.write(fuente[i]);
        i++;
      }
      literales.add(buf.toString());
      codigo.write(' ');
      continue;
    }
    codigo.write(c);
    i++;
  }
  return (codigo: codigo.toString(), literales: literales);
}

// ═══ LA CASA EN MINIATURA ══════════════════════════════════════════════════

const _id = 'dev_puerta_cocina';

/// `contact: true` = ABIERTA (lo fija el backend: el parser de eWeLink hace
/// `contact: lock === 1`, y 1 es la puerta abierta).
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
  final socket = SocketService();
  final service = DevicesService(
    config: ServerConfig(host: '127.0.0.1', port: 1),
    socket: socket,
  );
  service.debugSeedDevices([d]);
  // Cada par deja siete StreamController broadcast vivos si nadie los cierra.
  addTearDown(() {
    service.dispose();
    socket.dispose();
  });
  return service;
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

SensorTrigger _disparador(bool abre) =>
    SensorTrigger(sensorId: _id, sensorField: 'contact', sensorValue: abre);

Automation _automatizacion(bool abre) => Automation.fromJson({
      'id': 'auto_puerta',
      'name': 'Luz al abrir',
      'icon': '⚡',
      'enabled': true,
      'source': 'custom',
      'mode': 'toggle',
      'trigger': {
        'type': 'sensor',
        'sensorTriggers': [_disparador(abre).toJson()],
      },
      'actions': <Map<String, dynamic>>[],
    });

// ═══ EL RECORRIDO ══════════════════════════════════════════════════════════

/// De qué mitad del vocabulario habla una vista: del estado de la puerta
/// («Abierta») o del hecho que le pasa («Se abre»).
enum _Registro { adjetivo, verbo }

class _Narrador {
  const _Narrador(
    this.nombre,
    this.construir, {
    this.registro = _Registro.adjetivo,
    this.dibujaLaPuerta = false,
    this.calladaCuandoCierra = false,
  });

  final String nombre;
  final Widget Function(Device d, DevicesService s) construir;
  final _Registro registro;

  /// La vista muestra el glifo de la puerta, no sólo la palabra. Los íconos se
  /// podían invertir sin que nada muriera hasta que esto se empezó a mirar.
  final bool dibujaLaPuerta;

  /// Los badges de la home aparecen cuando algo está ABIERTO y callan cuando
  /// está cerrado: a ésos se les exige nada más que no mientan.
  final bool calladaCuandoCierra;
}

final _narradores = <_Narrador>[
  _Narrador(
    'tile de sensor',
    (d, s) => SensorTile(device: d, service: s, interactive: false),
    dibujaLaPuerta: true,
  ),
  _Narrador('vista unificada por capabilities',
      (d, s) => UnifiedDeviceScreen(device: d, service: s)),
  _Narrador(
    'detalle del sensor',
    (d, s) => SensorDetailScreen(device: d, service: s),
    dibujaLaPuerta: true,
  ),
  _Narrador(
    'card destacada de la home',
    (d, s) => SensorHomeCard(device: d, service: s),
    dibujaLaPuerta: true,
  ),
  _Narrador(
    'qué protege (alarma)',
    (d, s) => ProtectedList(
      devices: s,
      triggers: const {_id: true},
      onConfigure: () {},
    ),
    dibujaLaPuerta: true,
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
    dibujaLaPuerta: true,
    calladaCuandoCierra: true,
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
  _Narrador(
    'resumen del disparador',
    (d, s) =>
        Text(sensorTriggerPhrase(_disparador(d.sensor?.contact == true), s)),
    registro: _Registro.verbo,
  ),
  _Narrador(
    'cláusula «Cuando» de la lista',
    (d, s) =>
        Text(triggerClause(_automatizacion(d.sensor?.contact == true), s)),
    registro: _Registro.verbo,
  ),
];

/// Todo el texto que la vista pone en pantalla, junto.
String _textoVisible(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' ∥ ');

/// Los glifos que la vista dibuja: el SVG de icons0 y el IconData de MDI, que
/// es como llegan los dos caminos (`CceIcon` y el `IconResolver`).
Set<Object> _glifosVisibles(WidgetTester tester) => {
      ...tester.widgetList<CceIcon>(find.byType(CceIcon)).map((i) => i.svg),
      ...tester
          .widgetList<Icon>(find.byType(Icon))
          .map((i) => i.icon)
          .whereType<IconData>(),
    };

// No pueden ser `const`: IconData no tiene igualdad primitiva. La comparación
// del Set usa su ==, que sí está definido.
final _glifosDeApertura = <Object>{CceIcons.doorOpen, Mdi.doorOpen};
final _glifosDeCierre = <Object>{
  CceIcons.doorClosed,
  Mdi.door,
  Mdi.doorClosed,
};

(RegExp, RegExp) _palabrasDe(_Registro r) => switch (r) {
      _Registro.adjetivo => (_adjetivoAbierta, _adjetivoCerrada),
      _Registro.verbo => (_verboAbrir, _verboCerrar),
    };

void main() {
  group('el mapeo canónico', () {
    test('`contact: true` es ABIERTA, y abrir es lo que le pasa', () {
      // Si estas líneas se invierten, se invierte la App entera de una — que es
      // exactamente lo que este archivo quiere que pase, en vez de que una sola
      // pantalla se desincronice en silencio.
      expect(ContactWords.label(true), 'Abierta');
      expect(ContactWords.label(false), 'Cerrada');
      expect(ContactWords.feminine(true), 'abierta');
      expect(ContactWords.masculine(true), 'abierto');
      expect(ContactWords.verb(true), 'Se abre');
      expect(ContactWords.verb(false), 'Se cierra');
      expect(ContactWords.verbSubjunctive(true), 'se abra');
      expect(ContactWords.verbSubjunctive(false), 'se cierre');
    });

    test('el contador de aberturas resuelve el cero él mismo', () {
      expect(ContactWords.openCount(0), isNull);
      expect(ContactWords.openCount(1), '1 abierta');
      expect(ContactWords.openCount(3), '3 abiertas');
    });

    test('el ícono del resolver acompaña a la palabra', () {
      expect(IconResolver.resolve(_puerta(true)), Mdi.doorOpen);
      expect(IconResolver.resolve(_puerta(false)), isNot(Mdi.doorOpen));
    });
  });

  group('el recorrido: ninguna vista invierte la palabra', () {
    for (final n in _narradores) {
      final (abrir, cerrar) = _palabrasDe(n.registro);

      testWidgets('${n.nombre}: con contact:true habla de ABRIR',
          (tester) async {
        final d = _puerta(true);
        await tester.pumpWidget(MaterialApp(
          theme: CceTheme.dark(),
          home: Scaffold(body: n.construir(d, _servicio(d))),
        ));
        await tester.pump();

        final texto = _textoVisible(tester);
        expect(abrir.hasMatch(texto), isTrue,
            reason: '«${n.nombre}» no dijo que la puerta se abre: $texto');
        expect(cerrar.hasMatch(texto), isFalse,
            reason: '«${n.nombre}» narró contact:true como cerrada: $texto');

        if (n.dibujaLaPuerta) {
          final glifos = _glifosVisibles(tester);
          expect(glifos.intersection(_glifosDeApertura), isNotEmpty,
              reason:
                  '«${n.nombre}» dice abierta y no dibuja la puerta abierta');
          expect(glifos.intersection(_glifosDeCierre), isEmpty,
              reason: '«${n.nombre}» dice abierta y dibuja la puerta cerrada');
        }
      });

      testWidgets('${n.nombre}: con contact:false NO habla de abrir',
          (tester) async {
        final d = _puerta(false);
        await tester.pumpWidget(MaterialApp(
          theme: CceTheme.dark(),
          home: Scaffold(body: n.construir(d, _servicio(d))),
        ));
        await tester.pump();

        final texto = _textoVisible(tester);
        expect(abrir.hasMatch(texto), isFalse,
            reason: '«${n.nombre}» narró contact:false como abierta: $texto');
        if (!n.calladaCuandoCierra) {
          expect(cerrar.hasMatch(texto), isTrue,
              reason:
                  '«${n.nombre}» no dijo que la puerta está cerrada: $texto');
        }

        if (n.dibujaLaPuerta) {
          final glifos = _glifosVisibles(tester);
          expect(glifos.intersection(_glifosDeApertura), isEmpty,
              reason: '«${n.nombre}» dice cerrada y dibuja la puerta abierta');
          if (!n.calladaCuandoCierra) {
            expect(glifos.intersection(_glifosDeCierre), isNotEmpty,
                reason:
                    '«${n.nombre}» dice cerrada y no dibuja la puerta cerrada');
          }
        }
      });
    }

    testWidgets('la tile y la vista unificada dicen la MISMA palabra',
        (tester) async {
      // El bug en una frase: dos pantallas de la misma App diciendo lo opuesto
      // del mismo booleano.
      final d = _puerta(true);
      final s = _servicio(d);
      await tester.pumpWidget(MaterialApp(
        theme: CceTheme.dark(),
        home: Scaffold(
          body: SensorTile(device: d, service: s, interactive: false),
        ),
      ));
      await tester.pump();
      final tile = _adjetivoAbierta.firstMatch(_textoVisible(tester))!.group(0);

      await tester.pumpWidget(MaterialApp(
        theme: CceTheme.dark(),
        home: UnifiedDeviceScreen(device: d, service: s),
      ));
      await tester.pump();
      final unificada =
          _adjetivoAbierta.firstMatch(_textoVisible(tester))!.group(0);

      expect(unificada, tile);
      expect(tile, ContactWords.open);
    });
  });

  group('el editor de disparadores: la pantalla que ESCRIBE el valor', () {
    // Las otras vistas leen mal y el dueño ve un texto equivocado. Acá el dueño
    // elige «Se cierra», se guarda `sensorValue: true` y queda una
    // automatización que hace lo contrario de lo que pidió. Por eso se prueba
    // por el camino real —el sheet montado— y no por su literal.
    Future<CceSegmented<bool>> abrirSheet(WidgetTester tester, bool abre) async {
      final devices = _servicio(_puerta(false));
      final draft = _automatizacion(abre);
      // Pantalla de un iPhone 17 Pro Max: el sheet es una lista perezosa y con
      // los 800×600 por defecto el segmentado no llega a construirse.
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: CceTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showTriggerSheet(context, draft: draft, devices: devices),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return tester.widget<CceSegmented<bool>>(find.byType(CceSegmented<bool>));
    }

    testWidgets('el segmento elegido con sensorValue:true dice «Se abre»',
        (tester) async {
      final seg = await abrirSheet(tester, true);
      final elegido = seg.segments.firstWhere((s) => s.value == seg.value);
      expect(elegido.label, ContactWords.opens);
    });

    testWidgets('el segmento elegido con sensorValue:false dice «Se cierra»',
        (tester) async {
      final seg = await abrirSheet(tester, false);
      final elegido = seg.segments.firstWhere((s) => s.value == seg.value);
      expect(elegido.label, ContactWords.closes);
    });

    testWidgets('elegir «Se abre» guarda true, no lo contrario',
        (tester) async {
      final seg = await abrirSheet(tester, false);
      final abrir =
          seg.segments.firstWhere((s) => s.label == ContactWords.opens);
      expect(abrir.value, isTrue,
          reason: 'el dueño elegiría abrir y quedaría guardado cerrar');
    });
  });

  group('la fuente: el vocabulario vive en un solo archivo', () {
    // Este es el test que cubre las vistas que todavía no existen. El recorrido
    // sólo puede hablar de las que alguien se acordó de agregar a la lista;
    // esto se lee el `lib/` entero.
    test('ningún archivo que nombre `contact` se inventa sus palabras', () {
      const fuente = 'lib/utils/contact_words.dart';
      final infractores = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.replaceAll('\\', '/').endsWith(fuente)) continue;
        for (final palabra in palabrasSueltas(f.readAsStringSync())) {
          infractores.add('${f.path} → «$palabra»');
        }
      }

      expect(
        infractores,
        isEmpty,
        reason: 'Estos archivos nombran `contact` y deciden la palabra por su '
            'cuenta; así se rompió CCE#115. Las palabras salen de ContactWords '
            '($fuente):\n  ${infractores.join('\n  ')}',
      );
    });

    group('el meta-test del guard', () {
      // Ejercita EL MISMO `palabrasSueltas` que escanea `lib/`, no una copia:
      // romper la regex de arriba tiene que matar a los dos tests, en vez de
      // dejar a uno probándose a sí mismo.
      test('encuentra el bug original', () {
        expect(
          palabrasSueltas(
              "add('Contacto', s.contact! ? 'Cerrado' : 'Abierto');"),
          ['Cerrado', 'Abierto'],
        );
      });

      test('encuentra el vocabulario VERBAL, que es el que se escribe', () {
        expect(
          palabrasSueltas("case 'contact': segments = const ["
              "CceSegment(value: true, label: 'Se abre'),"
              "CceSegment(value: false, label: 'Se cierra')];"),
          ['Se abre', 'Se cierra'],
        );
        expect(
          palabrasSueltas("if (t.sensorField == 'contact') "
              "s = v == true ? 'se abra \$name' : 'se cierre \$name';"),
          [r'se abra $name', r'se cierre $name'],
        );
      });

      test('ve el estado que llega como prop, no sólo `sensor.contact`', () {
        // La forma de RoomCard. `\bcontact\b` no matcheaba `contactOpen` y el
        // guard pasaba de largo por los componentes que reciben el booleano.
        expect(
          palabrasSueltas(
              "if (widget.contactOpen) StatusBadgeData(label: 'Abierta');"),
          ['Abierta'],
        );
      });

      test('una URL adentro de un string no le tapa la línea', () {
        // El `//` de `https://` hacía que la versión vieja borrara el resto de
        // la línea y no viera nada. Pasa en cce_icons.dart y hue_badge.dart.
        expect(
          palabrasSueltas("const svg = 'https://casa.local/x';"
              "final t = s.contact! ? 'Cerrada' : 'Abierta';"),
          ['Cerrada', 'Abierta'],
        );
      });

      test('no confunde la cerradura con una abertura', () {
        // «abre con huella» (lockOpenWay) y «Cerradura» son de otro aparato: el
        // guard pide el «se» del verbo y la palabra entera del adjetivo.
        expect(palabrasSueltas("case 'contact': return 'abre \$way';"), isEmpty);
        expect(palabrasSueltas("d.contact; const t = 'Cerradura del frente';"),
            isEmpty);
      });

      test('un comentario que explica la convención no lo hace fallar', () {
        expect(
          palabrasSueltas('// `contact: true` es abierta.\n'
              'final x = ContactWords.label(open);'),
          isEmpty,
        );
      });

      test('un archivo que no nombra `contact` no le interesa', () {
        // La cerradura dice «Puerta abierta» con todo derecho: es otro estado,
        // de otro device.
        expect(palabrasSueltas("return 'Puerta abierta';"), isEmpty);
      });
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
