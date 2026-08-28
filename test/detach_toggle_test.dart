// Test de contrato del INTERRUPTOR DE DETACH (EugeValeiras/CCE#39).
//
// El modo detach desacopla la tecla de la pared de la carga: deja de cortar la
// luz y pasa a ser un pulsador. Es configuración que se escribe en hardware de
// la casa, así que el interruptor tiene que aparecer SÓLO donde el device
// declara soportarlo — mostrarlo de más invita a escribir un param que ese
// firmware no atiende.
//
// El backend lo declara con la capability `detach_relay` y lo reporta en
// `state.detached`. Los payloads salen de la casa real (2026-08-28).
//
// AISLADO A PROPÓSITO (mismo criterio que button_relay_test): importa SOLO
// models/device.dart y el registry puro de renderers.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/utils/capability_renderers.dart';

/// «Living patio interno» (ewelink_acc4002926) CON el detach puesto.
const detachOnJson = <String, dynamic>{
  'id': 'dev_6ce4a4fffe449134',
  'name': 'Living patio interno',
  'type': 'eWeLink Switch Button',
  'capabilities': ['sensor', 'button', 'switch', 'detach_relay'],
  'state': {'on': true, 'bri': 1, 'reachable': true, 'detached': true},
  'sensor': {'lastKey': 0},
};

/// El MISMO relé con el detach sacado: sigue soportándolo, ya no lo tiene.
const detachOffJson = <String, dynamic>{
  'id': 'dev_6ce4a4fffe449134',
  'name': 'Living patio interno',
  'type': 'eWeLink Switch',
  'capabilities': ['switch', 'detach_relay'],
  'state': {'on': true, 'bri': 1, 'reachable': true, 'detached': false},
};

/// Un relé común, sin el modo.
const plainSwitchJson = <String, dynamic>{
  'id': 'dev_plain',
  'name': 'Enchufe',
  'type': 'eWeLink Switch',
  'capabilities': ['switch'],
  'state': {'on': true, 'bri': 1, 'reachable': true},
};

/// Un sensor de movimiento a pilas.
const motionJson = <String, dynamic>{
  'id': 'dev_motion',
  'name': 'Office movement',
  'type': 'eWeLink Motion Sensor',
  'capabilities': ['sensor', 'motion'],
  'state': {'on': false, 'bri': 0, 'reachable': true},
  'sensor': {'motion': true, 'battery': '100'},
};

void main() {
  group('quién muestra el interruptor', () {
    test('el relé que soporta detach, sí', () {
      expect(Device.fromJson(detachOnJson).supportsDetach, isTrue);
      expect(Device.fromJson(detachOffJson).supportsDetach, isTrue);
    });

    test('un relé común, no', () {
      expect(Device.fromJson(plainSwitchJson).supportsDetach, isFalse);
    });

    test('un sensor, no', () {
      expect(Device.fromJson(motionJson).supportsDetach, isFalse);
    });
  });

  group('estado que pinta el interruptor', () {
    test('lee state.detached en los dos sentidos', () {
      expect(Device.fromJson(detachOnJson).state.detached, isTrue);
      expect(Device.fromJson(detachOffJson).state.detached, isFalse);
    });

    test('un device sin el modo no inventa un false', () {
      // null y false NO son lo mismo acá: con null el interruptor va
      // deshabilitado (no se sabe de qué estado parte) en vez de mostrarse
      // apagado sobre un device que ni siquiera tiene el modo.
      expect(Device.fromJson(plainSwitchJson).state.detached, isNull);
      expect(Device.fromJson(motionJson).state.detached, isNull);
    });
  });

  group('la vista unificada lo renderiza', () {
    test('detach_relay mapea a su propio renderer', () {
      final kinds = capabilityRenderersFor(
        List<String>.from(detachOnJson['capabilities'] as List),
      ).map((e) => e.kind);

      expect(kinds, contains(CapabilityRendererKind.detach));
    });

    test('va ÚLTIMO: es configuración, no un control de uso diario', () {
      final kinds = capabilityRenderersFor(
        List<String>.from(detachOnJson['capabilities'] as List),
      ).map((e) => e.kind).toList();

      expect(kinds.last, CapabilityRendererKind.detach);
    });

    test('un device sin la capability no lo renderiza', () {
      final kinds = capabilityRenderersFor(['switch', 'brightness'])
          .map((e) => e.kind);

      expect(kinds, isNot(contains(CapabilityRendererKind.detach)));
    });

    test('el relé sin detach conserva su on/off y suma el interruptor', () {
      // Sacar el detach no puede costarle el control de la luz.
      final kinds = capabilityRenderersFor(
        List<String>.from(detachOffJson['capabilities'] as List),
      ).map((e) => e.kind).toList();

      expect(kinds, [
        CapabilityRendererKind.onoff,
        CapabilityRendererKind.detach,
      ]);
    });
  });
}
