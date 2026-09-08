// EugeValeiras/CCE#158 — EL GATE DEL INICIALIZADOR NO SE PIERDE AL GUARDAR
// DESDE LA APP.
//
// `trigger.conditions` significa dos cosas según de dónde venga. Con flujo
// PROYECTADO es el `if` que el backend deriva: la misma condición contada dos
// veces, y por eso al persistir un flujo se borra (CCE#65). Con flujo PROPIO es
// un GATE que alguien escribió aparte del árbol, que el motor evalúa ANTES de
// que la corrida exista: el evento que no lo cumple ni entra, y la corrida que
// estaba esperando sobrevive. Las dos automatizaciones del living y del pasillo
// lo tienen puesto y andando.
//
// `toJson()` borraba las `conditions` de CUALQUIER automatización con flujo
// propio, así que abrir una de esas dos y guardar cualquier cosa —hasta el
// nombre— se llevaba el gate puesto, y ni el sheet ni la card lo mostraban.
//
// El fixture son las dos REALES, tal como vienen del `GET /config/automations`.
// El de siempre (`automations-prod.json`) no cubre el caso: de sus 26, las que
// tienen flujo propio no tienen gate, y las que tienen conditions son de flujo
// proyectado — ahí borrarlas es lo correcto. Por eso los 26 casos de siempre
// pasaban con el agujero puesto.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/automation_flow.dart';

List<Map<String, dynamic>> _load(String name) {
  final text = File('test/fixtures/$name').readAsStringSync();
  return [
    for (final a in jsonDecode(text) as List) Map<String, dynamic>.from(a as Map),
  ];
}

Map<String, dynamic> _byId(List<Map<String, dynamic>> list, String id) =>
    list.singleWhere((m) => m['id'] == id);

/// El gate tal como sale en el JSON que se guardaría.
List<dynamic>? _gateOf(Map<String, dynamic> json) =>
    (json['trigger'] as Map)['conditions'] as List?;

List<dynamic>? _whenGateOf(Map<String, dynamic> json) {
  final when = json['when'] as List?;
  if (when == null || when.isEmpty) return null;
  return (when.first as Map)['conditions'] as List?;
}

/// Una automatización con flujo propio, un gate, y un flujo que SÍ entra en el
/// molde del wizard (un `do` sin más). Es el caso que hoy no existe en la casa
/// pero que el Dashboard puede escribir desde CCE#158: gate + flujo propio +
/// forma editable desde la app.
Map<String, dynamic> _editableConGate({List<Map<String, dynamic>>? gate}) => {
      'id': 'auto_test_gate',
      'name': 'Con gate y flujo propio',
      'icon': '⚡',
      'enabled': true,
      'source': 'custom',
      'mode': 'toggle',
      'trigger': {
        'type': 'sensor',
        'sensorTriggers': [
          {'sensorId': 'dev_pir', 'sensorField': 'motion', 'sensorValue': true},
        ],
        'conditions': gate ??
            [
              {
                'type': 'deviceState',
                'deviceId': 'dev_tv',
                'field': 'on',
                'value': false,
              },
            ],
      },
      'actions': [
        {'lightId': 'dev_luz', 'on': true},
      ],
      'flow': [
        {
          'type': 'do',
          'actions': [
            {'kind': 'device', 'deviceId': 'dev_luz', 'on': true},
          ],
        },
      ],
    };

void main() {
  final conGate = _load('automations-gate.json');
  final prod = _load('automations-prod.json');
  final living = _byId(conGate, 'auto_mtrxnz073scodx6hwx');
  final pasillo = _byId(conGate, 'auto_mtown9gwxntnevjvj7p');

  group('el escenario existe', () {
    test('las dos del fixture tienen flujo propio y gate', () {
      for (final json in conGate) {
        final a = Automation.fromJson(json);
        expect(a.hasOwnFlow, isTrue, reason: '${a.name}: flujo propio');
        expect(a.originalGate, isNotEmpty, reason: '${a.name}: gate escrito');
      }
    });

    test('y la app NO las puede editar: el flujo no entra en el molde', () {
      // Es importante que el arreglo NO dependa de esto: el camino por el que
      // se perdía el gate es `toJson()`, que corre igual en solo lectura
      // (guardar el nombre, deshacer un borrado).
      for (final json in conGate) {
        final draft = WizardDraft(Automation.fromJson(json));
        expect(draft.readOnly, isTrue);
      }
    });

    test('el fixture de siempre no cubre este caso', () {
      // Tres de las 26 tienen flujo propio, pero NINGUNA tiene gate: el
      // borrado de `toJson()` no le sacaba nada a nadie ahí, y por eso este
      // agujero pasó los 26 casos del fixture de siempre.
      final conGateYFlujoPropio = [
        for (final json in prod)
          if (Automation.fromJson(json).originalGate.isNotEmpty) json,
      ];
      expect(conGateYFlujoPropio, isEmpty);
    });
  });

  group('abrir y guardar', () {
    test('sin tocar nada devuelve el mismo JSON, byte a byte', () {
      for (final json in conGate) {
        final out = Automation.fromJson(json).toJson();
        expect(jsonEncode(out), jsonEncode(json), reason: json['name'] as String);
      }
    });

    test('cambiar el nombre no se lleva el gate puesto', () {
      final a = Automation.fromJson(living)..name = 'Otro nombre';
      final out = a.toJson();

      // EL ESCENARIO: se guardó algo distinto de lo que vino.
      expect(out['name'], 'Otro nombre');
      expect((living['trigger'] as Map)['conditions'], isNotEmpty);

      expect(_gateOf(out), (living['trigger'] as Map)['conditions']);
      expect(_whenGateOf(out), (living['trigger'] as Map)['conditions'],
          reason: 'el `when` es lo que leen el CLI y las listas');
    });

    test('el gate del pasillo tampoco, y ahí convive con un «si no»', () {
      final a = Automation.fromJson(pasillo)..enabled = false;
      final out = a.toJson();
      expect(out['enabled'], isFalse);
      expect(_gateOf(out), (pasillo['trigger'] as Map)['conditions']);
    });

    test('un gate con `or` sobrevive entero', () {
      final gate = [
        {
          'or': [
            {'type': 'timeWindow', 'fromTime': '19:00', 'toTime': '07:30'},
            {
              'type': 'sensor',
              'sensorId': 'dev_pir',
              'field': 'lux',
              'operator': 'lt',
              'value': 20,
            },
          ],
        },
      ];
      final a = Automation.fromJson(_editableConGate(gate: gate))
        ..name = 'Editada';
      final out = a.toJson();
      expect(_gateOf(out), gate, reason: 'el `or` viaja tal cual, sin aplanarse');
      expect(_whenGateOf(out), gate);
    });
  });

  group('editar desde el wizard', () {
    test('la condición del sheet va al `if` y el gate queda aparte', () {
      final a = Automation.fromJson(_editableConGate());
      final draft = WizardDraft(a);

      // EL ESCENARIO: esta sí entra en el molde, así que la app la edita.
      expect(draft.readOnly, isFalse);
      expect(a.trigger.conditions, isEmpty,
          reason: 'el sheet arranca vacío: el árbol no tiene `if`');

      // Lo que hace el sheet SOLO SI: agregar una condición al draft.
      a.trigger.conditions.add(
        AutomationCondition.timeWindow(fromTime: '20:00', toTime: '06:00'),
      );
      expect(draft.dirty, isTrue, reason: 'el escenario llegó a guardar algo');
      draft.commit();
      final out = a.toJson();

      // La condición del sheet es el `if` del árbol…
      final flow = out['flow'] as List;
      expect((flow.first as Map)['type'], 'if',
          reason: 'la condición del sheet se guarda como el `if` del flujo');

      // …y el gate sigue donde estaba, sin duplicarse en el `if`.
      expect(_gateOf(out), [
        {'type': 'deviceState', 'deviceId': 'dev_tv', 'field': 'on', 'value': false},
      ]);
    });

    test('con un `if` en el árbol, el sheet muestra el `if`, no el gate', () {
      final json = _editableConGate();
      json['flow'] = [
        {
          'type': 'if',
          'cond': {'type': 'timeWindow', 'fromTime': '20:00', 'toTime': '06:00'},
          'then': [
            {
              'type': 'do',
              'actions': [
                {'kind': 'device', 'deviceId': 'dev_luz', 'on': true},
              ],
            },
          ],
        },
      ];
      final a = Automation.fromJson(json);
      final draft = WizardDraft(a);
      expect(draft.readOnly, isFalse);

      // El sheet muestra la condición del `if`, que es la que puede editar.
      expect(a.trigger.conditions.single.type, 'timeWindow');
      // Y el gate —que es otra cosa— sigue entero para guardarlo.
      expect(a.originalGate.single['type'], 'deviceState');

      a.name = 'Renombrada';
      draft.commit();
      final out = a.toJson();
      expect(_gateOf(out), [
        {'type': 'deviceState', 'deviceId': 'dev_tv', 'field': 'on', 'value': false},
      ]);
      expect(((out['flow'] as List).first as Map)['type'], 'if',
          reason: 'y el `if` del árbol no se lo comió el gate');
    });
  });

  group('sin flujo propio, la regla de CCE#65 sigue', () {
    test('al persistir un flujo, las conditions proyectadas se borran', () {
      // `encender luz al entrar al living`: proyectada, con conditions que SON
      // el `if` que el backend deriva.
      final json = _byId(prod, 'auto_msd6oasgpfi878');
      final a = Automation.fromJson(json);
      expect(a.hasOwnFlow, isFalse, reason: 'escenario: flujo proyectado');
      expect(a.trigger.conditions, isNotEmpty, reason: 'escenario: con conditions');
      expect(a.originalGate, isEmpty,
          reason: 'no son un gate escrito: son el `if` proyectado');

      final draft = WizardDraft(a);
      expect(draft.readOnly, isFalse);
      a.name = 'Editada';
      draft.commit();
      final out = a.toJson();

      expect(out['flowDerived'], isNull, reason: 'escenario: pasó a flujo propio');
      expect(_gateOf(out), isNull,
          reason: 'y ahí las conditions se van: ya viajaron al árbol como el `if`');
      expect(((out['flow'] as List).first as Map)['type'], 'if');
    });
  });
}
