// El termostato como ACCIÓN de una automatización (EugeValeiras/CCE#62).
//
// El picker de «Acción de dispositivo» lista los devices que tienen al menos
// una acción no sensible en el catálogo, y `thermostat` no declaraba ninguna:
// la calefacción no se podía automatizar. Ahora el backend declara tres verbos
// y la app tiene que (a) ver al termostato como accionable, (b) armar un
// control ACOTADO al rango del equipo —no un campo libre— y (c) resumir la
// acción en castellano.
//
// Los payloads salen de la casa real: `cce devices show dev_8b2bfaeba4a3` y
// GET /api/capabilities (2026-08-31).
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/capability.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/utils/arg_controls.dart';
import 'package:cce_app/utils/verb_labels.dart';
import 'package:cce_app/views/automations/automation_phrases.dart';

/// El CCE Thermostat de la casa (Tuya cat 'wk'), con la calefacción prendida.
const thermostatJson = <String, dynamic>{
  'id': 'dev_8b2bfaeba4a3',
  'name': 'CCE Thermostat',
  'type': 'Tuya Thermostat',
  'capabilities': ['switch', 'thermostat', 'sensor'],
  'state': {
    'on': true,
    'bri': 1,
    'reachable': true,
    'currentTemp': 20.7,
    'targetTemp': 19.5,
    'tempMode': 'Manual',
    'systemMode': 'heat',
    'minTemp': 5.0,
    'maxTemp': 45.0,
  },
  'sensor': {'temperature': 20.7},
};

/// Recorte de GET /api/capabilities con la capability del termostato.
const catalogJson = <String, dynamic>{
  'baseStateFields': ['reachable', 'mode'],
  'capabilities': {
    'switch': {
      'capability': 'switch',
      'stateFields': ['on'],
    },
    'sensor': {
      'capability': 'sensor',
      'sensorFields': ['temperature'],
    },
    'thermostat': {
      'capability': 'thermostat',
      'stateFields': [
        'currentTemp',
        'targetTemp',
        'tempMode',
        'systemMode',
        'minTemp',
        'maxTemp',
      ],
      'actions': [
        {
          'verb': 'setTargetTemp',
          'args': [
            {
              'name': 'targetTemp',
              'type': 'number',
              'min': 5,
              'max': 45,
              'minFrom': 'minTemp',
              'maxFrom': 'maxTemp',
              'step': 0.5,
              'unit': '°C',
            }
          ],
          'affects': ['targetTemp'],
        },
        {
          'verb': 'setPower',
          'args': [
            {'name': 'on', 'type': 'boolean'}
          ],
          'affects': ['on'],
        },
        {
          'verb': 'setTempMode',
          'args': [
            {
              'name': 'mode',
              'type': 'string',
              'enumRef': 'THERMOSTAT_TEMP_MODES',
            }
          ],
          'affects': ['tempMode'],
        },
        // CCE#101 — los dos verbos de conveniencia.
        {
          'verb': 'startHeating',
          'args': [
            {
              'name': 'targetTemp',
              'type': 'number',
              'required': false,
              'min': 5,
              'max': 45,
              'minFrom': 'minTemp',
              'maxFrom': 'maxTemp',
              'step': 0.5,
              'unit': '°C',
            }
          ],
          'affects': ['on', 'targetTemp'],
        },
        {'verb': 'stopHeating', 'affects': ['on']},
      ],
    },
  },
  'enums': {
    'THERMOSTAT_TEMP_MODES': ['Manual', 'Program'],
  },
};

/// Mismo criterio que `_actionableDevices` del editor: un device entra al
/// picker si alguna de sus capabilities declara una acción no sensible.
bool isActionable(Device d, CapabilityCatalog cat) {
  for (final cap in d.capabilities) {
    final spec = cat.specFor(cap);
    if (spec != null && spec.actions.any((a) => !a.isSensitive)) return true;
  }
  return false;
}

void main() {
  final catalog = CapabilityCatalog.fromJson(catalogJson);
  final thermostat = Device.fromJson(thermostatJson);

  group('el termostato entra al picker de «Acción de dispositivo»', () {
    test('sus capabilities declaran acciones no sensibles', () {
      expect(isActionable(thermostat, catalog), isTrue);
    });

    test('los cinco verbos son los que el provider sabe ejecutar', () {
      final spec = catalog.specFor('thermostat')!;
      expect(
          spec.actions.map((a) => a.verb),
          containsAll([
            'setTargetTemp',
            'setPower',
            'setTempMode',
            'startHeating',
            'stopHeating',
          ]));
      expect(spec.actions.any((a) => a.isSensitive), isFalse);
      expect(spec.isVerbDriven, isTrue);
    });

    // CCE#101 — «Calentar» toma un objetivo OPCIONAL: sin él la API elige un
    // grado más que el ambiente, así que el sheet lo ofrece como slider pero
    // no lo exige para guardar.
    test('startHeating tiene un targetTemp opcional y stopHeating ninguno', () {
      final spec = catalog.specFor('thermostat')!;
      final start = spec.actions.firstWhere((a) => a.verb == 'startHeating');
      expect(start.args.single.name, 'targetTemp');
      expect(start.args.single.required, isFalse);
      expect(start.args.single.step, 0.5);
      final stop = spec.actions.firstWhere((a) => a.verb == 'stopHeating');
      expect(stop.args, isEmpty);
      expect(verbLabel('startHeating'), 'Calentar');
      expect(verbLabel('stopHeating'), 'Dejar de calentar');
    });

    test('un device sin acciones sigue afuera (switch a secas)', () {
      final plug = Device.fromJson(const {
        'id': 'dev_plain',
        'name': 'Enchufe',
        'capabilities': ['switch'],
        'state': {'on': true, 'bri': 0, 'reachable': true},
      });
      expect(isActionable(plug, catalog), isFalse);
    });
  });

  group('el control de temperatura queda acotado al equipo', () {
    final spec = catalog.specFor('thermostat')!.findAction('setTargetTemp')!;
    final arg = spec.args.single;

    test('el arg trae el rango del catálogo y de dónde sacar el real', () {
      expect(arg.min, 5);
      expect(arg.max, 45);
      expect(arg.minFrom, 'minTemp');
      expect(arg.maxFrom, 'maxTemp');
      expect(arg.step, 0.5);
      expect(arg.unit, '°C');
      // El catálogo omite `required` cuando el arg lo es: sin este default el
      // editor dejaba guardar la acción sin temperatura.
      expect(arg.required, isTrue);
    });

    test('el rango efectivo sale del state del device', () {
      final range = argRangeFor(arg, thermostat.state)!;
      expect(range.min, 5);
      expect(range.max, 45);
      expect(range.step, 0.5);
      expect(range.divisions, 80);
    });

    test('un termostato con otro rango manda el suyo, no el documental', () {
      final otro = Device.fromJson(const {
        'id': 'dev_otro',
        'name': 'Termostato acotado',
        'capabilities': ['thermostat'],
        'state': {
          'on': true,
          'bri': 0,
          'reachable': true,
          'targetTemp': 22.0,
          'minTemp': 16.0,
          'maxTemp': 28.0,
        },
      });
      final range = argRangeFor(arg, otro.state)!;
      expect(range.min, 16);
      expect(range.max, 28);
      expect(range.snap(30), 28); // el slider no puede pedir un valor inválido
      expect(range.snap(10), 16);
    });

    test('el slider se mueve de a medio grado', () {
      final range = argRangeFor(arg, thermostat.state)!;
      expect(range.snap(21.3), 21.5);
      expect(range.snap(21.1), 21.0);
      expect(range.asArg(21.5), 21.5);
    });

    test('arranca en el setpoint vigente, no en el mínimo', () {
      final range = argRangeFor(arg, thermostat.state)!;
      expect(initialArgValue(spec, range, thermostat.state), 19.5);
    });

    test('un arg entero (volumen) sigue viajando como int', () {
      final volSpec = CatalogActionSpec.fromJson(const {
        'verb': 'setVolume',
        'args': [
          {'name': 'volume', 'type': 'number', 'min': 0, 'max': 100}
        ],
        'affects': ['volume'],
      });
      final range = argRangeFor(volSpec.args.single, thermostat.state)!;
      expect(range.step, 1);
      expect(range.asArg(30.4), 30);
      expect(range.asArg(30.4), isA<int>());
    });

    test('un arg numérico sin rango dibujable no rompe (volumeUp step)', () {
      final stepOnly = CatalogArgSpec.fromJson(const {
        'name': 'step',
        'type': 'number',
        'required': false,
      });
      expect(argRangeFor(stepOnly, thermostat.state), isNull);
    });

    test('numField resuelve los campos que nombra el catálogo', () {
      expect(thermostat.state.numField('minTemp'), 5.0);
      expect(thermostat.state.numField('maxTemp'), 45.0);
      expect(thermostat.state.numField('targetTemp'), 19.5);
      expect(thermostat.state.numField('tempMode'), isNull);
      expect(thermostat.state.numField(null), isNull);
    });
  });

  group('el resumen se lee en castellano', () {
    final devices = DevicesService(config: ServerConfig(), socket: SocketService());

    test('la temperatura sale con su valor, no el verbo crudo', () {
      final act = AutomationAction.device(
          'dev_8b2bfaeba4a3', 'setTargetTemp', {'targetTemp': 21});
      expect(actionPhrase(act, devices), 'Poner dev_8b2bfaeba4a3 en 21°');
      final medio = AutomationAction.device(
          'dev_8b2bfaeba4a3', 'setTargetTemp', {'targetTemp': 21.5});
      expect(actionPhrase(medio, devices), endsWith('en 21.5°'));
    });

    // CCE#101 — los dos verbos nuevos, como el dueño piensa la acción.
    test('calentar y dejar de calentar se dicen como tales', () {
      final start = AutomationAction.device('dev_8b2bfaeba4a3', 'startHeating', {});
      expect(actionPhrase(start, devices), 'Calentar dev_8b2bfaeba4a3');
      final startTo = AutomationAction.device(
          'dev_8b2bfaeba4a3', 'startHeating', {'targetTemp': 21.5});
      expect(actionPhrase(startTo, devices), 'Calentar dev_8b2bfaeba4a3 a 21.5°');
      final stop = AutomationAction.device('dev_8b2bfaeba4a3', 'stopHeating', {});
      expect(actionPhrase(stop, devices), 'Dejar de calentar dev_8b2bfaeba4a3');
    });

    test('prender y apagar se dicen como tales', () {
      final on =
          AutomationAction.device('dev_8b2bfaeba4a3', 'setPower', {'on': true});
      final off =
          AutomationAction.device('dev_8b2bfaeba4a3', 'setPower', {'on': false});
      expect(actionPhrase(on, devices), startsWith('Prender '));
      expect(actionPhrase(off, devices), startsWith('Apagar '));
    });

    test('el modo se traduce', () {
      final act = AutomationAction.device(
          'dev_8b2bfaeba4a3', 'setTempMode', {'mode': 'Program'});
      expect(actionPhrase(act, devices), endsWith('en modo Programa'));
    });

    test('un verbo sin caso propio conserva «Device: Verbo»', () {
      final act = AutomationAction.device('dev_tv', 'play');
      expect(actionPhrase(act, devices), 'dev_tv: Play');
    });

    test('una acción a medio editar no inventa un valor', () {
      final act = AutomationAction.device('dev_8b2bfaeba4a3', 'setTargetTemp');
      expect(actionPhrase(act, devices), 'dev_8b2bfaeba4a3: Temperatura');
    });
  });
}
