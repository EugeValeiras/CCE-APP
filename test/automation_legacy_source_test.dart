import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';

/// Modo Simple retirado (2026-07-30): la config del server está migrada a
/// source:'custom', pero el editor convierte por robustez cualquier
/// automation legacy que aparezca (backup, otro cliente). Estos tests fijan
/// el mapeo source→acción equivalente y que al serializar sale 'custom' SIN
/// las claves legacy — el backend detecta el tipo de acción por `on`.
void main() {
  Automation legacy(Map<String, dynamic> extra) => Automation.fromJson({
        'id': 'auto_x',
        'name': 'Legacy',
        'icon': '⚡',
        'enabled': true,
        'mode': 'toggle',
        'trigger': {'type': 'manual'},
        'actions': <Map<String, dynamic>>[],
        ...extra,
      });

  group('convertLegacySourceToAction', () {
    test("source 'scene' → acción on:'scene'", () {
      final a = legacy({'source': 'scene', 'sourceId': 'scene_7'});
      a.convertLegacySourceToAction();
      expect(a.source, 'custom');
      expect(a.actions, hasLength(1));
      expect(a.actions.first.kind, AutomationActionKind.scene);
      expect(a.actions.first.sceneId, 'scene_7');
      final json = a.toJson();
      expect(json['source'], 'custom');
      expect(json.containsKey('sourceId'), isFalse);
    });

    test("source 'hueScene' → acción on:'hueScene' con sceneSmart", () {
      final a = legacy({
        'source': 'hueScene',
        'sourceId': 'hue_sc_1',
        'sourceSmart': true,
      });
      a.convertLegacySourceToAction();
      final act = a.actions.single;
      expect(act.kind, AutomationActionKind.hueScene);
      expect(act.hueSceneId, 'hue_sc_1');
      expect(act.sceneSmart, isTrue);
      expect(a.toJson().containsKey('sourceSmart'), isFalse);
    });

    test("source 'group' → acción de grupo con sourceAction", () {
      final a = legacy({
        'source': 'group',
        'sourceId': 'grp_living',
        'sourceAction': 'off',
      });
      a.convertLegacySourceToAction();
      final act = a.actions.single;
      expect(act.kind, AutomationActionKind.group);
      expect(act.groupId, 'grp_living');
      expect(act.groupAction, 'off');
      expect(a.toJson().containsKey('sourceAction'), isFalse);
    });

    test("source 'group' sin sourceAction → default 'on'", () {
      final a = legacy({'source': 'group', 'sourceId': 'grp_1'});
      a.convertLegacySourceToAction();
      expect(a.actions.single.groupAction, 'on');
    });

    test("source 'hueRoom' → acción on:'hueRoom' con sourceAction", () {
      final a = legacy({
        'source': 'hueRoom',
        'sourceId': 'room_abc',
        'sourceAction': 'off',
      });
      a.convertLegacySourceToAction();
      final act = a.actions.single;
      expect(act.kind, AutomationActionKind.hueRoom);
      expect(act.hueRoomId, 'room_abc');
      expect(act.hueRoomAction, 'off');
    });

    test("source 'custom' es no-op (no duplica acciones)", () {
      final a = legacy({
        'source': 'custom',
        'actions': [
          {'on': 'scene', 'sceneId': 'scene_1'},
        ],
      });
      a.convertLegacySourceToAction();
      expect(a.actions, hasLength(1));
      expect(a.source, 'custom');
    });

    test('source legacy SIN sourceId → custom sin acciones (validará el '
        'editor)', () {
      final a = legacy({'source': 'scene'});
      a.convertLegacySourceToAction();
      expect(a.source, 'custom');
      expect(a.actions, isEmpty);
      expect(a.validationError(), isNotNull);
    });

    test('source desconocido queda intacto (round-trip sin pérdida)', () {
      final a = legacy({'source': 'holograma', 'sourceId': 'x'});
      a.convertLegacySourceToAction();
      expect(a.toJson()['source'], 'holograma');
      expect(a.toJson()['sourceId'], 'x');
    });

    test('los campos no modelados sobreviven a la conversión', () {
      final a = legacy({
        'source': 'scene',
        'sourceId': 'scene_9',
        'planId': 'plan_pb',
        'futuro': 42,
      });
      a.convertLegacySourceToAction();
      final json = a.toJson();
      expect(json['planId'], 'plan_pb');
      expect(json['futuro'], 42);
    });

    test('la automation convertida valida y frasea como custom', () {
      final a = legacy({'source': 'hueScene', 'sourceId': 'hue_sc_2'});
      a.convertLegacySourceToAction();
      // Con nombre + trigger manual + 1 acción, guardable como custom.
      expect(a.validationError(), isNull);
      // La frase sale del camino custom (acciones), no del legacy por
      // source; sin escenas cargadas el nombre cae al id — mejor pista que
      // el genérico "escena".
      final devices =
          DevicesService(config: ServerConfig(), socket: SocketService());
      expect(actionsPhrase(a, devices), 'escena hue_sc_2');
      expect(actionPhrase(a.actions.single, devices), 'Escena hue_sc_2');
    });
  });

  group('editor unificado de grupo: cambio de tipo en la misma fila', () {
    test('Room Hue → grupo CCE limpia las claves del contrato hueRoom', () {
      final act = AutomationAction.hueRoom('room_1')
        ..updateHueRoom(hueRoomId: 'room_1', hueRoomAction: 'off');
      act.updateGroup(groupId: 'grp_2', groupAction: 'toggle');
      final json = act.toJson();
      expect(json['on'], 'group');
      expect(json['groupId'], 'grp_2');
      expect(json['groupAction'], 'toggle');
      expect(json.containsKey('hueRoomId'), isFalse);
      expect(json.containsKey('hueRoomAction'), isFalse);
    });

    test('grupo CCE → Room Hue limpia groupId/groupAction', () {
      final act = AutomationAction.group('grp_2')
        ..updateGroup(groupId: 'grp_2', groupAction: 'off');
      act.updateHueRoom(hueRoomId: 'room_1', hueRoomAction: 'on');
      final json = act.toJson();
      expect(json['on'], 'hueRoom');
      expect(json['hueRoomId'], 'room_1');
      expect(json['hueRoomAction'], 'on');
      expect(json.containsKey('groupId'), isFalse);
      expect(json.containsKey('groupAction'), isFalse);
    });
  });
}
