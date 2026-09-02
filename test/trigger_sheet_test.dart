// EugeValeiras/CCE#80 — el sheet del disparador ya no ofrece la espera.
//
// `sensorDelay` era un «sostenido» del motor: espera N segundos y cancela si el
// sensor cambia en el medio. Desde CCE#64 las esperas van en el flujo, donde
// se ven, así que el sheet deja de escribirlo. Lo que se prueba, sobre las 26
// automatizaciones REALES de la casa (fixture del 01/09/2026):
//  - el sheet no ofrece «Esperar antes de ejecutar» a ninguna;
//  - «Abrir portón», la única con sensorDelay > 0, muestra el aviso de forma
//    vieja SIN botón de convertir (eso es del Dashboard, que tiene el editor
//    completo del flujo);
//  - una con sensorDelay 0 no muestra nada;
//  - abrir el sheet y cerrarlo no toca el valor: el draft re-serializa igual,
//    y el motor sigue respetando el sostenido hasta que el dueño lo convierta.
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/automation.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/views/automations/sheets/trigger_sheet.dart';

const _eq = DeepCollectionEquality();

List<Map<String, dynamic>> _loadProd() {
  final text = File('test/fixtures/automations-prod.json').readAsStringSync();
  return [
    for (final a in jsonDecode(text) as List) Map<String, dynamic>.from(a as Map),
  ];
}

Map<String, dynamic> _byId(List<Map<String, dynamic>> prod, String id) =>
    prod.singleWhere((m) => m['id'] == id);

/// Abre el sheet CUÁNDO sobre un draft de [json] y devuelve ese draft, para
/// mirar qué le quedó después.
Future<Automation> _openSheet(
  WidgetTester tester,
  Map<String, dynamic> json,
) async {
  final draft = Automation.fromJson(json);
  final devices = DevicesService(config: ServerConfig(), socket: SocketService());
  // Pantalla de un iPhone 17 Pro Max (440×956 pt): el sheet es una lista
  // perezosa y con los 800×600 por defecto el final no llega a construirse.
  tester.view.physicalSize = const Size(1320, 2868);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
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
  // Sin pumpAndSettle: el service dispara un GET que en el test falla, y no
  // hay animaciones infinitas que esperar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return draft;
}

void main() {
  final prod = _loadProd();

  testWidgets('«Abrir portón» muestra el aviso de forma vieja, sin convertir',
      (tester) async {
    final draft = await _openSheet(tester, _byId(prod, 'auto_mtajh8tolh3wylpjs5'));
    expect(draft.trigger.sensorDelay, 10, reason: 'el fixture trae los 10 s');
    expect(find.text('Cuándo'), findsOneWidget);
    expect(
      find.textContaining('espera 10 s antes de disparar (forma vieja)'),
      findsOneWidget,
    );
    expect(find.textContaining('desde el Dashboard'), findsOneWidget);
    // La conversión es del Dashboard: acá no hay botón.
    expect(find.text('Convertir a pasos'), findsNothing);
    // Y el stepper viejo ya no está.
    expect(find.text('ESPERAR ANTES DE EJECUTAR'), findsNothing);
    expect(find.textContaining('Se cancela si la condición'), findsNothing);
  });

  testWidgets('una con sensorDelay 0 abre sin aviso y sin ofrecer la espera',
      (tester) async {
    // Abrir portón (aviso): el MISMO botón que «Abrir portón», sin sostenido.
    final draft = await _openSheet(tester, _byId(prod, 'auto_mtd3y0yplmjdx3mjbb'));
    expect(draft.trigger.sensorDelay, 0);
    expect(find.text('Cuándo'), findsOneWidget);
    expect(find.textContaining('forma vieja'), findsNothing);
    expect(find.text('ESPERAR ANTES DE EJECUTAR'), findsNothing);
  });

  testWidgets('abrir y cerrar el sheet no toca el sostenido: re-serializa igual',
      (tester) async {
    final json = _byId(prod, 'auto_mtajh8tolh3wylpjs5');
    final draft = await _openSheet(tester, json);
    await tester.tap(find.text('Listo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(draft.trigger.sensorDelay, 10, reason: 'el aviso es solo lectura');
    expect(
      _eq.equals(draft.toJson(), Automation.fromJson(json).toJson()),
      isTrue,
      reason: 'lo que se manda es lo que vino: ni un byte distinto',
    );
  });

  test('la espera se lee como la dice el Dashboard', () {
    expect(legacyDelayLabel(10), '10 s');
    expect(legacyDelayLabel(300), '5 min');
    expect(legacyDelayLabel(90), '1 min 30 s');
    expect(legacyDelayLabel(3600), '1 h');
    expect(legacyDelayLabel(5400), '1 h 30 min');
  });
}
