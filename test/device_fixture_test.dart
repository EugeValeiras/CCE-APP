// Test de contrato (F13 PARTE A): verifica que Device.fromJson parsea el
// FIXTURE DORADO capturado del backend (script contract:capture de CCE-API,
// sanitizado) sin romper para NINGUNA entrada.
//
// AISLADO A PROPÓSITO: importa SOLO models/device.dart (+ dart:convert/io y
// flutter_test). El aislamiento nació para esquivar la dep rota
// material_design_icons (hoy eliminada: fuente MDI vendoreada en
// lib/theme/mdi.dart) y se conserva porque un test de contrato de parseo no
// tiene por qué arrastrar el árbol de widgets.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';

void main() {
  // El fixture se genera con `npm run contract:capture` en CCE-API y se copia a
  // este worktree. cwd de `flutter test` = raíz del paquete.
  final file = File('test/fixtures/merged-golden.json');
  final entries =
      (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('el fixture existe y tiene entradas', () {
    expect(file.existsSync(), isTrue,
        reason: 'Corré `npm run contract:capture` en CCE-API para generarlo');
    expect(entries, isNotEmpty);
  });

  test('Device.fromJson parsea cada entrada sin romper', () {
    for (final entry in entries) {
      expect(() => Device.fromJson(entry), returnsNormally,
          reason: 'Falló al parsear id=${entry['id']}');
      final d = Device.fromJson(entry);
      expect(d.id, isNotEmpty, reason: 'id vacío en ${entry['id']}');
    }
  });

  test('cobertura mínima de arquetipos (luz, sensor, termostato, lock, jbl, tv)',
      () {
    final devices = entries.map(Device.fromJson).toList();
    bool anyCap(bool Function(Device) f) => devices.any(f);

    expect(anyCap((d) => d.isLock), isTrue, reason: 'falta un lock');
    expect(anyCap((d) => d.isThermostat), isTrue, reason: 'falta un termostato');
    expect(anyCap((d) => d.capabilities.contains('motion') ||
            d.capabilities.contains('contact')),
        isTrue, reason: 'falta un sensor');
    expect(anyCap((d) => d.isLight), isTrue, reason: 'falta una luz');
    expect(devices.any((d) => d.id == 'dev_jbl'), isTrue,
        reason: 'falta dev_jbl');
    expect(devices.any((d) => d.id == 'dev_tv'), isTrue, reason: 'falta dev_tv');
  });

  test('coherencia de capability-getters', () {
    for (final entry in entries) {
      final d = Device.fromJson(entry);
      if (d.capabilities.contains('lock')) {
        expect(d.isLock, isTrue, reason: '${d.id} con cap lock → isLock');
      }
      if (d.capabilities.contains('thermostat')) {
        expect(d.isThermostat, isTrue,
            reason: '${d.id} con cap thermostat → isThermostat');
      }
      // dev_jbl/dev_tv son media-devices: NO deben clasificar como luz.
      if (d.isMediaDevice) {
        expect(d.isLight, isFalse,
            reason: '${d.id} es media-device y no debe ser luz');
      }
    }
  });

  test('los campos AV (volume/muted/mediaApp) quedan legibles en DeviceState',
      () {
    final byId = {for (final e in entries) e['id'] as String: Device.fromJson(e)};
    final jbl = byId['dev_jbl'];
    final tv = byId['dev_tv'];
    expect(jbl, isNotNull);
    expect(tv, isNotNull);
    // volume del backend es 0-100; el modelo lo transporta tal cual (la vista
    // JBL reescala a 0-31). No forzamos valores exactos: sólo que sean legibles.
    expect(jbl!.state.volume, anyOf(isNull, isA<int>()));
    expect(jbl.state.muted, anyOf(isNull, isA<bool>()));
    expect(tv!.state.volume, anyOf(isNull, isA<int>()));
    // dev_tv suele traer mediaApp/mediaInput; deben mapear a String? sin romper.
    expect(tv.state.mediaApp, anyOf(isNull, isA<String>()));
    expect(tv.state.mediaInput, anyOf(isNull, isA<String>()));
  });

  test('capability desconocida sigue parseando (F7-P-1)', () {
    final entry = {
      'id': 'dev_futuro',
      'name': 'X',
      'type': 'mystery',
      'capabilities': ['switch', 'capability_inventada_2099'],
      'state': {'on': true, 'bri': 10},
    };
    expect(() => Device.fromJson(entry), returnsNormally);
    final d = Device.fromJson(entry);
    expect(d.capabilities, contains('capability_inventada_2099'));
  });
}
