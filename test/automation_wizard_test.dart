// EugeValeiras/CCE#66 — la página del wizard sobre las automatizaciones
// REALES de la casa: una simple abre en el resumen editable con Guardar; una
// con `waitFor` abre narrada, con el aviso del Dashboard y SIN Guardar.
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

List<Map<String, dynamic>> _loadProd() {
  final text = File('test/fixtures/automations-prod.json').readAsStringSync();
  return [
    for (final a in jsonDecode(text) as List) Map<String, dynamic>.from(a as Map),
  ];
}

Map<String, dynamic> _byId(List<Map<String, dynamic>> prod, String id) =>
    prod.singleWhere((m) => m['id'] == id);

Future<(DevicesService, AutomationsService)> _services() async {
  final devices = DevicesService(config: ServerConfig(), socket: SocketService());
  final automations = AutomationsService(config: ServerConfig(), devices: devices);
  return (devices, automations);
}

Future<void> _pumpWizard(
  WidgetTester tester,
  Map<String, dynamic> json, {
  required bool isNew,
}) async {
  final (devices, service) = await _services();
  // Pantalla de un iPhone 17 Pro Max (440×956 pt): las filas del resumen
  // viven en un ListView perezoso y con los 800×600 por defecto la cuarta no
  // llega a construirse.
  tester.view.physicalSize = const Size(1320, 2868);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AutomationWizardPage(
      service: service,
      devices: devices,
      draft: Automation.fromJson(json),
      isNew: isNew,
    ),
  ));
  // Sin pumpAndSettle: el service dispara un GET que en el test falla, y no
  // hay animaciones infinitas que esperar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final prod = _loadProd();

  testWidgets('un flujo con waitFor abre en solo lectura, sin Guardar',
      (tester) async {
    await _pumpWizard(tester, _byId(prod, 'auto_mq872o2ekqh47vglzq'),
        isNew: false);
    expect(find.text('Solo lectura'), findsOneWidget);
    expect(find.text('Este flujo se edita desde el Dashboard'), findsOneWidget);
    expect(find.textContaining('espera'), findsWidgets);
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Cerrar'), findsOneWidget);
    // Narrado: la espera condicional con su timeout y la rama de timeout.
    expect(find.textContaining('Esperar hasta que'), findsOneWidget);
    expect(find.textContaining('Si no pasa en 5 min'), findsOneWidget);
    expect(find.text('Fin'), findsOneWidget);
  });

  // CCE#81 — el «Llamar» con salidas: narrado, con el aviso del Dashboard y
  // sin Guardar. El flujo se arma sobre una real para que el resto (nombre,
  // disparador) sea el de la casa.
  testWidgets('un flujo con «Llamar» abre narrado y sin Guardar',
      (tester) async {
    final base = _byId(prod, 'auto_mq872o2ekqh47vglzq');
    final json = {
      ...base,
      'flowDerived': false,
      'flow': [
        {
          'type': 'call',
          'contactId': 'c_porton',
          'timeoutSeconds': 60,
          'onAnswered': [
            {
              'type': 'do',
              'actions': [
                {'kind': 'alarm', 'action': 'disarm'},
              ],
            },
          ],
          'onMissed': [
            {
              'type': 'do',
              'actions': [
                {'kind': 'notification', 'message': 'nadie atendió'},
              ],
            },
            {'type': 'stop'},
          ],
        },
      ],
    };
    await _pumpWizard(tester, json, isNew: false);
    expect(find.text('Solo lectura'), findsOneWidget);
    expect(find.text('Este flujo se edita desde el Dashboard'), findsOneWidget);
    expect(find.textContaining('cómo termine la llamada'), findsOneWidget);
    expect(find.text('Guardar'), findsNothing);
    // Narrado: la llamada con su tope, y una rama por salida presente.
    expect(
      find.text('Llamar a un contacto y esperar a que termine (máximo 1 min)'),
      findsOneWidget,
    );
    expect(find.text('Si atienden'), findsOneWidget);
    expect(find.text('Si no atienden'), findsOneWidget);
    expect(find.text('Si la rechazan'), findsNothing);
    expect(find.text('Fin'), findsOneWidget);
  });

  testWidgets('un disparador de llamada también queda en solo lectura',
      (tester) async {
    await _pumpWizard(tester, _byId(prod, 'auto_mtarjfciexy6pl7u9v'),
        isNew: false);
    expect(find.text('Este flujo se edita desde el Dashboard'), findsOneWidget);
    expect(find.textContaining('Termina una llamada'), findsOneWidget);
    expect(find.text('Guardar'), findsNothing);
  });

  testWidgets('una simple existente abre en el resumen con Guardar',
      (tester) async {
    await _pumpWizard(tester, _byId(prod, 'auto_mq888zjf4h8pv6k9a1q'),
        isNew: false);
    expect(find.text('Nombre y listo'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    expect(find.text('Este flujo se edita desde el Dashboard'), findsNothing);
    // Las cuatro filas del resumen.
    for (final label in ['CUÁNDO', 'SOLO SI', 'QUÉ HACE', 'Y DESPUÉS']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Nada más'), findsOneWidget);
  });

  testWidgets('tocar «Y después» lleva a esa pantalla y «Resumen» vuelve',
      (tester) async {
    await _pumpWizard(tester, _byId(prod, 'auto_mq888zjf4h8pv6k9a1q'),
        isNew: false);
    await tester.tap(find.text('Y DESPUÉS'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Y después?'), findsOneWidget);
    expect(find.text('Esperar un rato y hacer otra cosa'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
    await tester.tap(find.text('Resumen'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nombre y listo'), findsOneWidget);
  });

  testWidgets('la que ya tiene if + stop del Dashboard abre editable',
      (tester) async {
    await _pumpWizard(tester, _byId(prod, 'auto_mq85ppkv1jqiphvn3fj'),
        isNew: false);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.textContaining('si está oscuro'), findsWidgets);
  });
}
