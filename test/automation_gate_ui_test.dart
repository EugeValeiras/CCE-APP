// EugeValeiras/CCE#158 — EL GATE DEL INICIALIZADOR SE VE EN LA APP.
//
// No se edita acá —el sheet SOLO SI edita el `if` del flujo, y el gate puede
// tener un `or` que ese sheet no sabe dibujar— pero tiene que VERSE: es lo que
// decide si la automatización arranca, y sin mostrarlo la del living se lee
// como si se disparara con cualquier movimiento, cuando en realidad sólo corre
// con el televisor apagado y entre las 19:00 y las 07:30.
//
// Dos pantallas, que son las dos por las que se llega:
//
//  1. La vista de SOLO LECTURA, que es donde caen hoy las dos reales (su flujo
//     no entra en el molde del wizard).
//  2. El sheet SOLO SI, para cuando el flujo sí entra en el molde — la forma
//     que el Dashboard puede escribir desde este mismo issue.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/automations_service.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/automations/automation_wizard_page.dart';
import 'package:cce_app/views/automations/sheets/conditions_sheet.dart';

List<Map<String, dynamic>> _load(String name) {
  final text = File('test/fixtures/$name').readAsStringSync();
  return [
    for (final a in jsonDecode(text) as List) Map<String, dynamic>.from(a as Map),
  ];
}

(DevicesService, AutomationsService) _services() {
  final devices = DevicesService(config: ServerConfig(), socket: SocketService());
  return (devices, AutomationsService(config: ServerConfig(), devices: devices));
}

/// Pantalla de un iPhone 17 Pro Max: con los 800×600 por defecto las secciones
/// de más abajo no llegan a construirse en el ListView.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1320, 2868);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Una automatización con gate y con un flujo que SÍ entra en el molde: el
/// caso en el que la app abre el wizard editable y el sheet SOLO SI.
Map<String, dynamic> _editableConGate(List<Map<String, dynamic>> gate) => {
      'id': 'auto_test_gate',
      'name': 'Con gate',
      'icon': '⚡',
      'enabled': true,
      'source': 'custom',
      'mode': 'toggle',
      'trigger': {
        'type': 'sensor',
        'sensorTriggers': [
          {'sensorId': 'dev_pir', 'sensorField': 'motion', 'sensorValue': true},
        ],
        'conditions': gate,
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
  final living = conGate.singleWhere((m) => m['id'] == 'auto_mtrxnz073scodx6hwx');

  testWidgets('la vista de solo lectura muestra el gate del living', (tester) async {
    _phone(tester);
    final (devices, service) = _services();
    final draft = Automation.fromJson(living);

    // EL ESCENARIO: esta automatización tiene gate y cae en solo lectura.
    expect(draft.originalGate, isNotEmpty);

    await tester.pumpWidget(MaterialApp(
      home: AutomationWizardPage(
        service: service,
        devices: devices,
        draft: draft,
        isNew: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Solo lectura'), findsOneWidget,
        reason: 'el flujo del living no entra en el molde del wizard');

    // La franja horaria del gate, que es la que no se veía en ningún lado.
    final gateLine = find.textContaining('sólo si');
    expect(gateLine, findsOneWidget);
    final texto = tester.widget<Text>(gateLine).data!;
    expect(texto, contains('19:00'));
    expect(texto, contains('07:30'));
  });

  testWidgets('sin gate, esa línea no aparece', (tester) async {
    _phone(tester);
    final (devices, service) = _services();
    final sinGate = Map<String, dynamic>.from(living);
    sinGate['trigger'] = {
      for (final e in (living['trigger'] as Map).entries)
        if (e.key != 'conditions') e.key: e.value,
    };
    final draft = Automation.fromJson(sinGate);
    expect(draft.originalGate, isEmpty, reason: 'escenario: sin gate');

    await tester.pumpWidget(MaterialApp(
      home: AutomationWizardPage(
        service: service,
        devices: devices,
        draft: draft,
        isNew: false,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Solo lectura'), findsOneWidget);
    expect(find.textContaining('sólo si'), findsNothing);
  });

  testWidgets('el sheet SOLO SI muestra el gate aparte, y no lo deja borrar',
      (tester) async {
    // A lo ancho de un iPad y no de un teléfono: el segmented de ALARMA de
    // este sheet se pasa 9.5px a 440pt —es de antes de este issue y no se
    // toca acá— y en un widget test un overflow es un error que tapa lo que
    // se está probando.
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (devices, _) = _services();
    // Un gate con `or`: la forma que el sheet no sabe editar y que igual tiene
    // que mostrarse sin romper.
    final draft = Automation.fromJson(_editableConGate([
      {
        'or': [
          {'type': 'timeWindow', 'fromTime': '19:00', 'toTime': '07:30'},
          {'type': 'timeWindow', 'fromTime': '12:00', 'toTime': '13:00'},
        ],
      },
    ]));

    // El sheet se abre sobre el draft del wizard, que con flujo propio pisa
    // `trigger.conditions` con las del `if` — acá, ninguna.
    draft.trigger.conditions.clear();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showConditionsSheet(context, draft: draft, devices: devices),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('CONDICIÓN DEL DISPARO'), findsOneWidget);
    expect(find.textContaining('19:00'), findsOneWidget,
        reason: 'el `or` se narra sin romper');
    expect(find.textContaining('se descarta'), findsOneWidget,
        reason: 'y dice qué hace, que es lo que lo distingue del `if`');

    // No se toca desde acá: la papelera es de las condiciones editables, y no
    // hay ninguna.
    expect(find.byTooltip('Quitar condición'), findsNothing);
    expect(
      find.text('Sin condiciones: la automatización se dispara siempre '
          'que ocurra el CUÁNDO.'),
      findsOneWidget,
      reason: 'el gate no cuenta como condición del flujo',
    );
  });
}
