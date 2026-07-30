import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/automation.dart';

/// Round-trip de las acciones Escena (CCE y Hue) del modo Personalizado.
/// El toJson DEBE emitir el contrato exacto del backend (on:'scene'+sceneId /
/// on:'hueScene'+hueSceneId+sceneSmart); el lightId sentinel es local y la
/// API lo ignora, pero el kind tiene que sobrevivir parse→serialize→parse.
void main() {
  group('AutomationAction escena CCE (on:scene)', () {
    test('factory + toJson emiten el contrato del backend', () {
      final act = AutomationAction.scene('scene_123');
      expect(act.kind, AutomationActionKind.scene);
      expect(act.sceneId, 'scene_123');
      final json = act.toJson();
      expect(json['on'], 'scene');
      expect(json['sceneId'], 'scene_123');
      // Claves del contrato Hue: NUNCA en una escena CCE.
      expect(json.containsKey('hueSceneId'), isFalse);
      expect(json.containsKey('sceneSmart'), isFalse);
    });

    test('round-trip parse → serialize → parse conserva todo', () {
      final parsed = AutomationAction.fromJson({
        'on': 'scene',
        'sceneId': 'scene_abc',
      });
      expect(parsed.kind, AutomationActionKind.scene);
      expect(parsed.sceneId, 'scene_abc');
      // Sin tocar por el editor, el raw re-serializa intacto.
      expect(parsed.toJson(), {'on': 'scene', 'sceneId': 'scene_abc'});
      final reparsed = AutomationAction.fromJson(parsed.toJson());
      expect(reparsed.kind, AutomationActionKind.scene);
      expect(reparsed.sceneId, 'scene_abc');
    });

    test('sceneId cae al sentinel si falta la clave', () {
      final act = AutomationAction.fromJson({
        'lightId': '__scene__legacy1',
        'on': 'scene',
      });
      expect(act.sceneId, 'legacy1');
    });
  });

  group('AutomationAction escena Hue (on:hueScene)', () {
    test('factory + toJson emiten el contrato del backend', () {
      final act = AutomationAction.hueScene('hue_sc_9', sceneSmart: true);
      expect(act.kind, AutomationActionKind.hueScene);
      expect(act.hueSceneId, 'hue_sc_9');
      expect(act.sceneSmart, isTrue);
      final json = act.toJson();
      expect(json['on'], 'hueScene');
      expect(json['hueSceneId'], 'hue_sc_9');
      expect(json['sceneSmart'], true);
      expect(json.containsKey('sceneId'), isFalse);
    });

    test('round-trip parse → serialize → parse conserva sceneSmart', () {
      final parsed = AutomationAction.fromJson({
        'on': 'hueScene',
        'hueSceneId': 'hue_sc_1',
        'sceneSmart': false,
      });
      expect(parsed.kind, AutomationActionKind.hueScene);
      expect(parsed.hueSceneId, 'hue_sc_1');
      expect(parsed.sceneSmart, isFalse);
      expect(parsed.toJson(), {
        'on': 'hueScene',
        'hueSceneId': 'hue_sc_1',
        'sceneSmart': false,
      });
      final reparsed = AutomationAction.fromJson(parsed.toJson());
      expect(reparsed.kind, AutomationActionKind.hueScene);
      expect(reparsed.sceneSmart, isFalse);
    });
  });

  group('cambio de tipo en el mismo editor', () {
    test('Hue → CCE limpia las claves del contrato Hue', () {
      final act = AutomationAction.hueScene('hue_sc_9', sceneSmart: true);
      act.updateScene(sceneId: 'scene_5');
      final json = act.toJson();
      expect(json['on'], 'scene');
      expect(json['sceneId'], 'scene_5');
      expect(json.containsKey('hueSceneId'), isFalse);
      expect(json.containsKey('sceneSmart'), isFalse);
    });

    test('CCE → Hue limpia sceneId', () {
      final act = AutomationAction.scene('scene_5');
      act.updateHueScene(hueSceneId: 'hue_sc_9', sceneSmart: true);
      final json = act.toJson();
      expect(json['on'], 'hueScene');
      expect(json['hueSceneId'], 'hue_sc_9');
      expect(json['sceneSmart'], true);
      expect(json.containsKey('sceneId'), isFalse);
    });
  });
}
