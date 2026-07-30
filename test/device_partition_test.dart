// Partición exhaustiva de los getters de listas de DevicesService:
// lights + sensors + thermostats + locks + vacuums + media deben CUBRIR
// `all` (todo device no-hidden) — la raíz del bug del Dashboard era excluir
// a mano dev_tv/dev_jbl de las listas sin darles una lista propia, y este
// test impide que un tipo nuevo (o un filtro nuevo) vuelva a esconder un
// device ("todos son dispositivos").
//
// Usa el MISMO fixture dorado que device_fixture_test.dart y los getters
// REALES del service (sembrado vía debugSeedDevices, sin red ni socket).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';

void main() {
  final entries = (jsonDecode(
          File('test/fixtures/merged-golden.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  DevicesService seeded() {
    // SocketService sin connect(): los streams existen pero no hay socket.
    final service =
        DevicesService(config: ServerConfig(), socket: SocketService());
    service.debugSeedDevices(entries.map(Device.fromJson).toList());
    return service;
  }

  test('la partición de getters cubre TODOS los devices visibles', () {
    final s = seeded();
    expect(s.all, isNotEmpty, reason: 'el fixture no sembró nada');
    final covered = <String>{
      for (final d in s.lights) d.id,
      for (final d in s.sensors) d.id,
      for (final d in s.thermostats) d.id,
      for (final d in s.locks) d.id,
      for (final d in s.vacuums) d.id,
      for (final d in s.media) d.id,
    };
    for (final d in s.all) {
      expect(covered, contains(d.id),
          reason:
              '${d.id} (type=${d.type}, caps=${d.capabilities}) no aparece en '
              'NINGÚN getter — device escondido por su tipo');
    }
  });

  test('media es la contrapartida del filtro manual: dev_tv/dev_jbl viven ahí',
      () {
    final s = seeded();
    final mediaIds = s.media.map((d) => d.id).toList();
    expect(mediaIds, containsAll(['dev_tv', 'dev_jbl']));
    // …y siguen FUERA de lights/sensors (la exclusión que motiva el getter).
    expect(s.lights.any((d) => d.isMediaDevice), isFalse);
    expect(s.sensors.any((d) => d.isMediaDevice), isFalse);
  });
}
