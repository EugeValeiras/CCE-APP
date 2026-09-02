// EugeValeiras/CCE#66 — el wizard de flujo escribe `when` + `flow`.
//
// Lo que se prueba es el contrato del issue, sin UI:
//  - las 26 automatizaciones REALES de la casa (fixture = GET
//    /api/config/automations del 01/09/2026) abren: las simples entran en el
//    molde del wizard y las complejas quedan en solo lectura;
//  - abrir cualquiera de las 26 sin tocar y re-serializar no cambia un byte;
//  - el ejemplo del issue (movimiento → si está oscuro → living al 40% →
//    esperar 5 min → apagar) produce exactamente el árbol documentado;
//  - lo que el wizard guarda es `when` + `flow` propio, con `trigger` sin
//    `conditions` y `actions` como espejo del camino feliz (el DTO del backend
//    exige el campo; el motor lo ignora porque `flow` gana).
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/automation_flow.dart';

const _eq = DeepCollectionEquality();

List<Map<String, dynamic>> _loadProd() {
  final text = File('test/fixtures/automations-prod.json').readAsStringSync();
  return [
    for (final a in jsonDecode(text) as List) Map<String, dynamic>.from(a as Map),
  ];
}

/// Las dos de la casa que el wizard NO edita, y por qué.
const _readOnlyIds = {
  'auto_mq872o2ekqh47vglzq': 'waitFor', // Apagar Living con Living Movimiento
  'auto_mtarjfciexy6pl7u9v': 'callEnded', // Portón abierto (aviso)
};

void main() {
  final prod = _loadProd();

  group('las 26 reales', () {
    test('el fixture trae las 26 con when + flow', () {
      expect(prod, hasLength(26));
      for (final m in prod) {
        expect(m['when'], isA<List>(), reason: m['id'].toString());
        expect(m['flow'], isA<List>(), reason: m['id'].toString());
      }
    });

    test('tres tienen flujo propio y 23 vienen proyectadas (flowDerived)', () {
      final own = prod.where((m) => Automation.fromJson(m).hasOwnFlow).toList();
      expect(own.map((m) => m['id']), containsAll([
        'auto_mq85ppkv1jqiphvn3fj',
        'auto_mq872o2ekqh47vglzq',
        'auto_mq8981z14zei13mh62f',
      ]));
      expect(own, hasLength(3));
      expect(prod.where((m) => m['flowDerived'] == true), hasLength(23));
    });

    test('las simples entran en el molde; las complejas quedan en solo lectura',
        () {
      for (final m in prod) {
        final draft = WizardDraft(Automation.fromJson(m));
        final id = m['id'].toString();
        if (_readOnlyIds.containsKey(id)) {
          expect(draft.readOnly, isTrue, reason: '$id debería ser solo lectura');
          expect(draft.unsupportedReason, isNotNull, reason: id);
        } else {
          expect(draft.readOnly, isFalse,
              reason: '$id debería entrar en el molde');
        }
      }
    });

    test('la que espera a que se cumpla una condición dice por qué', () {
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq872o2ekqh47vglzq');
      final draft = WizardDraft(Automation.fromJson(m));
      expect(draft.unsupportedReason, contains('espera'));
    });

    test('abrir sin tocar: el árbol reconstruido es el que vino', () {
      for (final m in prod) {
        final draft = WizardDraft(Automation.fromJson(m));
        if (draft.readOnly) continue;
        expect(draft.buildFlow(), m['flow'], reason: m['id'].toString());
        expect(draft.flowChanged, isFalse, reason: m['id'].toString());
        expect(draft.triggerChanged, isFalse, reason: m['id'].toString());
        expect(draft.dirty, isFalse, reason: m['id'].toString());
      }
    });

    test('abrir y re-serializar sin tocar no cambia un byte', () {
      for (final m in prod) {
        final a = Automation.fromJson(m);
        expect(jsonEncode(a.toJson()), jsonEncode(m),
            reason: m['id'].toString());
        // También después de pasar por el wizard sin editar nada, incluso si
        // algo llegara a "guardar" ese draft: commit() sin cambios es no-op.
        WizardDraft(a).commit();
        expect(jsonEncode(a.toJson()), jsonEncode(m),
            reason: '${m['id']} tras abrir el wizard');
      }
    });

    test('un flujo propio del Dashboard vuelve idéntico aunque se fuerce', () {
      // El caso del conflicto: «Sobrescribir» re-guarda el draft tal cual.
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq85ppkv1jqiphvn3fj');
      final a = Automation.fromJson(m);
      final draft = WizardDraft(a);
      a.setOwnFlow(draft.buildFlow());
      expect(jsonEncode(a.toJson()), jsonEncode(m));
    });

    test('el `stop` final de dos automatizaciones se conserva', () {
      final withStop = prod.where((m) {
        final flow = m['flow'] as List;
        return flow.isNotEmpty && (flow.last as Map)['type'] == 'stop';
      }).toList();
      expect(withStop, hasLength(2));
      for (final m in withStop) {
        final shape = wizardShapeOf(FlowStep.parseList(m['flow']));
        expect(shape, isNotNull);
        expect(shape!.trailingStop, isTrue);
        expect(buildWizardFlow(shape), m['flow']);
      }
    });
  });

  group('el ejemplo del issue', () {
    Automation blankWithMotion() {
      final a = Automation.blank();
      a.name = 'Living con movimiento';
      a.trigger.type = 'sensor';
      a.trigger.sensorTriggers = [
        SensorTrigger(
            sensorId: 'dev_motion', sensorField: 'motion', sensorValue: true),
      ];
      a.actions = [
        AutomationAction.light('dev_living')
          ..updateLight(lightId: 'dev_living', on: true, bri: 102),
      ];
      return a;
    }

    test('movimiento → si está oscuro → living al 40% → esperar 5 min → apagar',
        () {
      final a = blankWithMotion();
      final draft = WizardDraft(a);
      a.trigger.conditions.add(AutomationCondition.sensor(
          sensorId: 'dev_motion', field: 'brightness', value: 'darker'));
      draft.waitSeconds = 300;
      draft.afterActions.add(AutomationAction.light('dev_living')
        ..updateLight(lightId: 'dev_living', on: false));

      expect(draft.validationError(), isNull);
      expect(draft.dirty, isTrue);
      draft.commit();
      final json = a.toJson();

      expect(json['flow'], [
        {
          'type': 'if',
          'cond': {
            'type': 'sensor',
            'sensorId': 'dev_motion',
            'field': 'brightness',
            'value': 'darker',
          },
          'then': [
            {
              'type': 'do',
              'actions': [
                {'kind': 'device', 'deviceId': 'dev_living', 'on': true, 'bri': 102},
              ],
            },
            {'type': 'wait', 'seconds': 300},
            {
              'type': 'do',
              'actions': [
                {'kind': 'device', 'deviceId': 'dev_living', 'on': false},
              ],
            },
          ],
        },
      ]);
      // `when` es el trigger desduplicado, sin las conditions (viven en el if).
      expect(json['when'], [
        {
          'type': 'sensor',
          'alarmCondition': 'any',
          'sensorTriggers': [
            {'sensorId': 'dev_motion', 'sensorField': 'motion', 'sensorValue': true},
          ],
          'sensorTriggersMode': 'any',
          'sensorDelay': 0,
        },
      ]);
      expect((json['trigger'] as Map).containsKey('conditions'), isFalse);
      expect(json.containsKey('flowDerived'), isFalse);
      // El DTO exige `actions`: sale el espejo del camino feliz, nunca la
      // fuente de verdad.
      expect(json['actions'], [
        {'lightId': 'dev_living', 'on': true, 'bri': 102},
        {'lightId': 'dev_living', 'on': false},
      ]);
      expect(json['mode'], 'toggle');
      expect(json['source'], 'custom');
    });

    test('sin condición el árbol es plano: [do, wait, do]', () {
      final a = blankWithMotion();
      final draft = WizardDraft(a);
      draft.waitSeconds = 120;
      draft.afterActions.add(AutomationAction.light('dev_living')
        ..updateLight(lightId: 'dev_living', on: false));
      draft.commit();
      final flow = a.toJson()['flow'] as List;
      expect(flow.map((s) => (s as Map)['type']), ['do', 'wait', 'do']);
      expect((flow[1] as Map)['seconds'], 120);
    });

    test('sin «¿y después?» queda un solo do', () {
      final a = blankWithMotion();
      final draft = WizardDraft(a);
      draft.commit();
      expect(a.toJson()['flow'], [
        {
          'type': 'do',
          'actions': [
            {'kind': 'device', 'deviceId': 'dev_living', 'on': true, 'bri': 102},
          ],
        },
      ]);
    });

    test('una espera sin acciones después no se puede guardar', () {
      final a = blankWithMotion();
      final draft = WizardDraft(a);
      draft.waitSeconds = 300;
      expect(draft.validationError(), 'Elegí qué hacer después de la espera');
    });

    test('lo que produce el wizard vuelve a entrar en el molde', () {
      final a = blankWithMotion();
      final draft = WizardDraft(a);
      a.trigger.conditions.add(AutomationCondition.timeWindow(
          fromTime: '20:00', toTime: '07:00'));
      draft.waitSeconds = 300;
      draft.afterActions.add(AutomationAction.light('dev_living')
        ..updateLight(lightId: 'dev_living', on: false));
      draft.commit();
      final reopened = WizardDraft(Automation.fromJson(a.toJson()));
      expect(reopened.readOnly, isFalse);
      expect(reopened.dirty, isFalse);
      expect(reopened.waitSeconds, 300);
      expect(reopened.afterActions, hasLength(1));
      expect(reopened.automation.trigger.conditions, hasLength(1));
    });
  });

  group('editar una de las 26 proyectadas', () {
    test('pasa a flujo propio y conserva lo que no toca', () {
      // "1-Relax": derivada, un do con una escena Hue.
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq888zjf4h8pv6k9a1q');
      final a = Automation.fromJson(m);
      final draft = WizardDraft(a);
      expect(a.actions.single.kind, AutomationActionKind.hueScene);
      a.actions.single.updateHueScene(hueSceneId: 'otra', sceneSmart: true);
      expect(draft.dirty, isTrue);
      expect(draft.triggerChanged, isFalse);
      draft.commit();
      final json = a.toJson();
      expect(json.containsKey('flowDerived'), isFalse);
      expect(json['flow'], [
        {
          'type': 'do',
          'actions': [
            {'kind': 'hueScene', 'hueSceneId': 'otra', 'smart': true},
          ],
        },
      ]);
      // El trigger no se tocó: salen sus bytes originales y el `when` que el
      // backend ya había derivado de ellos.
      expect(json['trigger'], m['trigger']);
      expect(json['when'], m['when']);
      for (final k in ['id', 'icon', 'enabled', 'mode', 'planId', 'source']) {
        expect(json[k], m[k], reason: k);
      }
    });

    test('las conditions del trigger pasan al if del árbol', () {
      // "Prender soundbar cuando entra Euge": derivada con dos modulePower.
      final m = prod.singleWhere((m) => m['id'] == 'auto_mqp7916ccvqlhhmnk1v');
      final a = Automation.fromJson(m);
      final draft = WizardDraft(a);
      expect(a.trigger.conditions, hasLength(2));
      a.name = 'Otro nombre';
      draft.commit();
      final json = a.toJson();
      expect((json['trigger'] as Map).containsKey('conditions'), isFalse);
      expect(((json['when'] as List).single as Map).containsKey('conditions'),
          isFalse);
      final ifStep = (json['flow'] as List).single as Map;
      expect(ifStep['type'], 'if');
      expect((ifStep['cond'] as Map)['and'], (m['trigger'] as Map)['conditions']);
    });

    test('flowLayout del Dashboard sobrevive al guardado', () {
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq85ppkv1jqiphvn3fj');
      final a = Automation.fromJson(m);
      final draft = WizardDraft(a);
      draft.waitSeconds = 60;
      draft.afterActions.add(AutomationAction.hueRoom('room_x')
        ..updateHueRoom(hueRoomId: 'room_x', hueRoomAction: 'off'));
      draft.commit();
      final json = a.toJson();
      expect(json['flowLayout'], m['flowLayout']);
      final flow = json['flow'] as List;
      expect(flow.map((s) => (s as Map)['type']), ['if', 'stop']);
      expect(((flow.first as Map)['then'] as List).map((s) => (s as Map)['type']),
          ['do', 'wait', 'do']);
    });
  });

  group('acciones: legacy ↔ flujo', () {
    const flowActions = [
      {'kind': 'device', 'deviceId': 'dev_1', 'on': true, 'bri': 200, 'ct': 300},
      {'kind': 'device', 'deviceId': 'dev_1', 'on': 'bri_up', 'briDelta': 30},
      {'kind': 'deviceVerb', 'deviceId': 'dev_jbl', 'verb': 'setVolume', 'args': {'volume': 30}},
      {'kind': 'group', 'groupId': 'g1', 'action': 'off'},
      {'kind': 'group', 'groupId': 'g1'},
      {'kind': 'hueRoom', 'hueRoomId': 'r1', 'action': 'toggle'},
      {'kind': 'scene', 'sceneId': 's1'},
      {'kind': 'hueScene', 'hueSceneId': 'h1', 'smart': false},
      {'kind': 'notification', 'message': 'Hola', 'sound': 'doorbell', 'notificationType': 'info'},
      {'kind': 'notification'},
      {'kind': 'alarm', 'action': 'arm'},
      {'kind': 'jbl', 'action': 'on', 'onMode': 'radio', 'radioName': 'Urbana', 'volume': 7, 'nightMode': true},
      {'kind': 'jbl', 'action': 'off'},
      {'kind': 'announce', 'announcerId': 'porton'},
      {'kind': 'automation', 'automationIds': ['a1', 'a2'], 'action': 'toggle'},
      {'kind': 'call', 'contactId': 'c1', 'ringSeconds': 60},
    ];

    test('flujo → legacy → flujo es identidad para los 12 kinds', () {
      for (final f in flowActions) {
        final legacy = flowActionToLegacy(Map<String, dynamic>.from(f));
        expect(legacyActionToFlow(legacy), f, reason: jsonEncode(f));
      }
    });

    test('el legacy que sale lo entiende el modelo de la app', () {
      final kinds = [
        for (final f in flowActions)
          AutomationAction.fromJson(
                  flowActionToLegacy(Map<String, dynamic>.from(f)))
              .kind,
      ];
      expect(kinds.take(2), everyElement(isIn([
        AutomationActionKind.light,
        AutomationActionKind.advanced,
      ])));
      expect(kinds[2], AutomationActionKind.device);
      expect(kinds[3], AutomationActionKind.group);
      expect(kinds[5], AutomationActionKind.hueRoom);
      expect(kinds[6], AutomationActionKind.scene);
      expect(kinds[7], AutomationActionKind.hueScene);
      expect(kinds[8], AutomationActionKind.notification);
      expect(kinds[10], AutomationActionKind.alarm);
      expect(kinds[11], AutomationActionKind.jbl);
    });

    test('las acciones que arman los sheets de la app se traducen bien', () {
      expect(legacyActionToFlow(AutomationAction.light('dev_1').toJson()),
          {'kind': 'device', 'deviceId': 'dev_1', 'on': true, 'bri': 254});
      expect(
          legacyActionToFlow((AutomationAction.group('g1')
                ..updateGroup(groupId: 'g1', groupAction: 'off'))
              .toJson()),
          {'kind': 'group', 'groupId': 'g1', 'action': 'off'});
      expect(legacyActionToFlow(AutomationAction.scene('s1').toJson()),
          {'kind': 'scene', 'sceneId': 's1'});
      expect(
          legacyActionToFlow(
              AutomationAction.device('dev_t', 'setTargetTemp', {'targetTemp': 21})
                  .toJson()),
          {
            'kind': 'deviceVerb',
            'deviceId': 'dev_t',
            'verb': 'setTargetTemp',
            'args': {'targetTemp': 21},
          });
      expect(legacyActionToFlow(AutomationAction.jbl().toJson()),
          {'kind': 'jbl', 'action': 'on', 'onMode': 'resume'});
      expect(legacyActionToFlow(AutomationAction.alarm().toJson()),
          {'kind': 'alarm', 'action': 'arm'});
    });

    test('un sentinel sin clave explícita igual resuelve el id', () {
      expect(legacyActionToFlow({'lightId': '__scene__legacy1', 'on': 'scene'}),
          {'kind': 'scene', 'sceneId': 'legacy1'});
    });

    test('un kind desconocido se conserva entero', () {
      final raro = {'kind': 'holograma', 'x': 1};
      expect(flowActionToLegacy(raro), raro);
    });
  });

  group('deriveWhenEntry', () {
    test('con sensorTriggers[] borra los escalares duplicados', () {
      final when = deriveWhenEntry({
        'type': 'sensor',
        'sensorId': 'a',
        'sensorField': 'motion',
        'sensorValue': true,
        'sensorTriggers': [
          {'sensorId': 'a', 'sensorField': 'motion', 'sensorValue': true},
        ],
        'sensorDelay': 0,
      });
      expect(when, {
        'type': 'sensor',
        'sensorTriggers': [
          {'sensorId': 'a', 'sensorField': 'motion', 'sensorValue': true},
        ],
        'sensorDelay': 0,
      });
    });

    test('sin array promueve los escalares a sensorTriggers[0]', () {
      final when = deriveWhenEntry({
        'type': 'sensor',
        'sensorId': 'a',
        'sensorField': 'lastKey',
        'sensorValue': 0,
        'sensorOutlet': 2,
        'sensorDelay': 10,
      });
      expect(when, {
        'type': 'sensor',
        'sensorDelay': 10,
        'sensorTriggers': [
          {'sensorId': 'a', 'sensorField': 'lastKey', 'sensorValue': 0, 'sensorOutlet': 2},
        ],
      });
    });

    test('reproduce el when del backend para las 26', () {
      for (final m in prod) {
        final t = Map<String, dynamic>.from(m['trigger'] as Map);
        expect(deriveWhenEntry(t), (m['when'] as List).single,
            reason: m['id'].toString());
      }
    });
  });

  group('lo que no entra en el molde', () {
    List<FlowStep> steps(List<Map<String, dynamic>> json) =>
        FlowStep.parseList(json);
    const doOn = {
      'type': 'do',
      'actions': [
        {'kind': 'device', 'deviceId': 'd', 'on': true},
      ],
    };
    const doOff = {
      'type': 'do',
      'actions': [
        {'kind': 'device', 'deviceId': 'd', 'on': false},
      ],
    };
    const dark = {'type': 'sensor', 'sensorId': 's', 'field': 'brightness', 'value': 'darker'};

    test('si no con contenido', () {
      final flow = steps([
        {'type': 'if', 'cond': dark, 'then': [doOn], 'else': [doOff]},
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('si no'));
    });

    test('ramas anidadas', () {
      final flow = steps([
        {
          'type': 'if',
          'cond': dark,
          'then': [
            {'type': 'if', 'cond': dark, 'then': [doOn]},
          ],
        },
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('anidadas'));
    });

    test('más de una espera', () {
      final flow = steps([
        doOn,
        {'type': 'wait', 'seconds': 60},
        doOff,
        {'type': 'wait', 'seconds': 60},
        doOn,
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('más de una espera'));
    });

    test('waitFor', () {
      final flow = steps([
        {'type': 'waitFor', 'cond': dark, 'timeoutSeconds': 300, 'onTimeout': [doOff]},
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('espera'));
    });

    test('condición con o', () {
      final flow = steps([
        {'type': 'if', 'cond': {'or': [dark, dark]}, 'then': [doOn]},
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('«o»'));
    });

    test('un stop en el medio no es el stop final', () {
      expect(wizardShapeOf(steps([doOn, {'type': 'stop'}, doOff])), isNull);
    });

    // CCE#81 — el «Llamar» con salidas: la app lo narra, el wizard no lo edita.
    test('un call queda en solo lectura y dice por qué', () {
      final flow = steps([
        {
          'type': 'call',
          'contactId': 'c_porton',
          'timeoutSeconds': 60,
          'onAnswered': [doOn],
          'onMissed': [doOff],
        },
      ]);
      expect(flow.single, isA<FlowCallStep>());
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('cómo termine la llamada'));
    });

    test('un call escondido en una rama también', () {
      final flow = steps([
        {
          'type': 'if',
          'cond': dark,
          'then': [
            {'type': 'call', 'number': '123', 'timeoutSeconds': 30},
            doOn,
          ],
        },
      ]);
      expect(wizardShapeOf(flow), isNull);
      expect(wizardUnsupportedReason(flow), contains('llama'));
    });

    test('flow vacío entra (automatización sin acciones todavía)', () {
      final shape = wizardShapeOf(const []);
      expect(shape, isNotNull);
      expect(shape!.actions, isEmpty);
      expect(buildWizardFlow(shape), isEmpty);
    });

    test('un and de una sola hoja se reconstruye envuelto', () {
      final json = [
        {'type': 'if', 'cond': {'and': [dark]}, 'then': [doOn]},
      ];
      final shape = wizardShapeOf(steps(json))!;
      expect(shape.condWrapped, isTrue);
      expect(buildWizardFlow(shape), json);
    });
  });

  group('lo que muestra la app con flujo propio', () {
    test('effectiveActions y effectiveConditions salen del árbol', () {
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq85ppkv1jqiphvn3fj');
      final a = Automation.fromJson(m);
      expect(a.hasOwnFlow, isTrue);
      expect(a.trigger.conditions, isEmpty);
      expect(a.effectiveConditions, hasLength(2));
      expect(a.effectiveActions.single.kind, AutomationActionKind.hueRoom);
      expect(a.effectiveActions.single.hueRoomAction, 'on');
    });

    test('sin flujo propio son las legacy', () {
      final m = prod.singleWhere((m) => m['id'] == 'auto_mqp7916ccvqlhhmnk1v');
      final a = Automation.fromJson(m);
      expect(a.hasOwnFlow, isFalse);
      expect(identical(a.effectiveActions, a.actions), isTrue);
      expect(a.effectiveConditions, hasLength(2));
    });

    test('con call las acciones del camino feliz son las de «atendida»', () {
      final a = Automation.fromJson({
        'id': 'x',
        'name': 'x',
        'enabled': true,
        'trigger': {'type': 'manual'},
        'actions': [],
        'flow': [
          {
            'type': 'call',
            'contactId': 'c_porton',
            'timeoutSeconds': 60,
            'onAnswered': [
              {
                'type': 'do',
                'actions': [
                  {'kind': 'device', 'deviceId': 'd_ok', 'on': true},
                ],
              },
            ],
            'onMissed': [
              {
                'type': 'do',
                'actions': [
                  {'kind': 'notification', 'message': 'nadie'},
                ],
              },
            ],
          },
        ],
      });
      expect(a.effectiveActions.map((x) => x.lightId), ['d_ok']);
    });

    test('con waitFor las acciones del camino feliz no incluyen onTimeout', () {
      final m = prod.singleWhere((m) => m['id'] == 'auto_mq872o2ekqh47vglzq');
      final a = Automation.fromJson(m);
      expect(a.effectiveActions, isEmpty);
    });
  });

  group('CCE#81: el call se conserva entero', () {
    const callJson = {
      'type': 'call',
      'contactId': 'c_porton',
      'timeoutSeconds': 45,
      'onAnswered': [
        {
          'type': 'do',
          'actions': [
            {'kind': 'alarm', 'action': 'disarm'},
          ],
        },
      ],
      'onRejected': [
        {'type': 'stop'},
      ],
      'onTimeout': [
        {
          'type': 'do',
          'actions': [
            {'kind': 'notification', 'message': 'venció'},
          ],
        },
        {'type': 'stop'},
      ],
    };

    test('se parsea con sus salidas presentes, y sólo ésas', () {
      final s = FlowStep.parse(callJson) as FlowCallStep;
      expect(s.contactId, 'c_porton');
      expect(s.number, isNull);
      expect(s.timeoutSeconds, 45);
      expect(s.branches.keys, ['onAnswered', 'onRejected', 'onTimeout']);
      expect(s.branch('onMissed'), isEmpty);
      expect(s.branch('onTimeout').length, 2);
      expect(s.allBranches.length, 5);
    });

    test('re-serializar no cambia un byte (el JSON crudo se conserva)', () {
      final s = FlowStep.parse(callJson);
      expect(sameFlow([s.toJson()], [callJson]), isTrue);
      // Y un campo que la app no modela sobrevive igual.
      final extra = {...callJson, 'futuro': 1};
      expect(sameFlow([FlowStep.parse(extra).toJson()], [extra]), isTrue);
    });
  });

  test('setOwnFlow convierte un source legacy a custom', () {
    final a = Automation.fromJson({
      'id': 'x',
      'name': 'Legacy',
      'enabled': true,
      'source': 'scene',
      'sourceId': 'scene_1',
      'trigger': {'type': 'manual'},
      'actions': <Map<String, dynamic>>[],
    });
    a.setOwnFlow([
      {
        'type': 'do',
        'actions': [
          {'kind': 'scene', 'sceneId': 'scene_1'},
        ],
      },
    ]);
    final json = a.toJson();
    expect(json['source'], 'custom');
    expect(json.containsKey('sourceId'), isFalse);
    expect(json['actions'], [
      {'lightId': '', 'on': 'scene', 'sceneId': 'scene_1'},
    ]);
    // El trigger no se tocó: `when` sale de sus bytes tal cual vinieron.
    expect(_eq.equals(json['when'], [{'type': 'manual'}]), isTrue);
  });
}
