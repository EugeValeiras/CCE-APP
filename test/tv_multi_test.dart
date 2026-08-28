// Varios Samsung en la app (EugeValeiras/CCE#45).
//
// En la casa hay un televisor (`65" OLED`) y un monitor (`49" Odyssey OLED G9`),
// y la app mostraba uno. Lo que fija este test:
//
//   1. El estado que se ve y los comandos que se mandan son los del aparato
//      ELEGIDO — `selectedTvId` es lo que viaja como `?tv=` y `selectedDeviceId`
//      es el device por el que llegan SUS eventos del socket.
//   2. Un `device:state-changed` de OTRO aparato no toca lo que se muestra. Sin
//      ese filtro, el monitor apagándose pintaba al televisor como apagado.
//   3. Las features salen del backend: un monitor sin sintonizador ni apps no
//      tiene por qué ofrecerlas, y contra un backend viejo (sin GET /tv/tvs) se
//      asume todo — que es como se comportaba la app antes.
//   4. El televisor histórico conserva `dev_tv`: de ahí cuelgan las
//      automatizaciones, los grupos y los planos que ya lo usan.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/models/tv_status.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/tv_service.dart';

/// Lo que devuelve GET /tv/tvs para esta casa (shape real del backend).
const _televisorJson = {
  'id': 'tv',
  'name': '65" OLED',
  'kind': 'tv',
  'deviceId': '1ca02124-d3af-710f-0ccf-921590094a86',
  'ip': '192.168.1.48',
  'model': 'QN65S95FAGXZB',
  'paired': true,
  'isDefault': true,
  'features': {
    'power': true, 'volume': true, 'mute': true, 'channel': true,
    'input': true, 'playback': true, 'tracks': true, 'apps': true,
    'remote': true, 'pictureMode': true, 'soundMode': true, 'ambient': true,
  },
};

const _monitorJson = {
  'id': 'tv-ce588d39',
  'name': '49" Odyssey OLED G9',
  'kind': 'monitor',
  'deviceId': 'ce588d39-95fc-b700-fcce-813bb6c58284',
  'ip': null,
  'model': 'LS49DG956SNXGO',
  'paired': false,
  'isDefault': false,
  'features': {
    'power': true, 'volume': true, 'mute': true, 'channel': false,
    'input': true, 'playback': true, 'tracks': true, 'apps': false,
    'remote': true, 'pictureMode': true, 'soundMode': true, 'ambient': false,
  },
};

TvService fresh() =>
    TvService(config: ServerConfig(), socket: SocketService());

const _encendido = TvStatus(online: true, power: 'on', volume: 42);

void main() {
  group('TvSummary / TvFeatures', () {
    test('parsea el shape del backend', () {
      final tv = TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson));
      expect(tv.id, 'tv');
      expect(tv.name, '65" OLED');
      expect(tv.isMonitor, isFalse);
      expect(tv.paired, isTrue, reason: 'el televisor ya está pareado');
      expect(tv.canonicalDeviceId, 'dev_tv',
          reason: 'el id del televisor histórico NO se puede mover: de él '
              'cuelgan planos, grupos y automatizaciones');

      final mon = TvSummary.fromJson(Map<String, dynamic>.from(_monitorJson));
      expect(mon.isMonitor, isTrue);
      expect(mon.paired, isFalse,
          reason: 'el monitor nace sin parear: hay que aceptar el aviso en su '
              'pantalla');
      expect(mon.canonicalDeviceId, 'dev_tv-ce588d39');
      expect(mon.features.channel, isFalse, reason: 'un monitor sin sintonizador');
      expect(mon.features.apps, isFalse);
      expect(mon.features.volume, isTrue, reason: 'pero sí lo que declara');
    });

    test('sin features declaradas se asume TODO (backend viejo)', () {
      final tv = TvSummary.fromJson({'id': 'tv', 'name': 'TV'});
      expect(tv.features.channel, isTrue);
      expect(tv.features.apps, isTrue);
      expect(tv.features.ambient, isTrue);
      expect(tv.paired, isFalse);
      expect(TvFeatures.fromJson(null).channel, isTrue);
    });
  });

  group('TvService: elegir aparato', () {
    test('sin lista se comporta como cuando había uno solo', () {
      final s = fresh();
      expect(s.tvs, isEmpty);
      expect(s.hasMultipleTvs, isFalse);
      expect(s.selectedTv, isNull);
      expect(s.selectedTvId, isNull,
          reason: 'sin id no se manda ?tv= y el backend usa su aparato por '
              'defecto — el comportamiento anterior a CCE#45');
      expect(s.selectedDeviceId, 'dev_tv');
      expect(s.displayName, '65" OLED');
      expect(s.features.channel, isTrue);
      expect(s.needsPairing, isFalse,
          reason: 'sin saber nada del aparato no se muestra el aviso');
    });

    test('con la lista, manda el marcado como principal', () {
      final s = fresh()
        ..debugSeed(tvs: [
          TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson)),
          TvSummary.fromJson(Map<String, dynamic>.from(_monitorJson)),
        ]);
      expect(s.hasMultipleTvs, isTrue, reason: 'la UI muestra el selector');
      expect(s.selectedTv?.id, 'tv');
      expect(s.selectedTvId, 'tv');
      expect(s.selectedDeviceId, 'dev_tv');
      expect(s.displayName, '65" OLED');
      expect(s.needsPairing, isFalse);
    });

    test('elegido el monitor, todo apunta al monitor', () {
      final s = fresh()
        ..debugSeed(
          tvs: [
            TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson)),
            TvSummary.fromJson(Map<String, dynamic>.from(_monitorJson)),
          ],
          selectedId: 'tv-ce588d39',
        );
      expect(s.selectedTvId, 'tv-ce588d39', reason: 'es lo que viaja en ?tv=');
      expect(s.selectedDeviceId, 'dev_tv-ce588d39');
      expect(s.displayName, '49" Odyssey OLED G9');
      expect(s.features.channel, isFalse, reason: 'no se muestra el rocker CH');
      expect(s.features.apps, isFalse, reason: 'ni el botón de aplicaciones');
      expect(s.needsPairing, isTrue,
          reason: 'sin pairing hay que ir hasta el aparato: la app lo avisa');
    });

    test('un elegido que ya no existe cae al principal', () {
      final s = fresh()
        ..debugSeed(
          tvs: [TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson))],
          selectedId: 'tv-borrado',
        );
      expect(s.selectedTv?.id, 'tv',
          reason: 'no puede quedar apuntando a un aparato inexistente');
      expect(s.selectedDeviceId, 'dev_tv');
    });
  });

  group('TvService: el socket no mezcla aparatos', () {
    TvService conLosDos({String? selected}) => fresh()
      ..debugSeed(
        tvs: [
          TvSummary.fromJson(Map<String, dynamic>.from(_televisorJson)),
          TvSummary.fromJson(Map<String, dynamic>.from(_monitorJson)),
        ],
        status: _encendido,
        selectedId: selected,
      );

    test('un evento del monitor NO apaga al televisor en pantalla', () {
      final s = conLosDos();
      s.debugApplyDeviceEvent(DeviceStateEvent(
        deviceId: 'dev_tv-ce588d39',
        state: const {'on': false, 'reachable': false},
      ));
      expect(s.isOn, isTrue, reason: 'el televisor sigue encendido');
      expect(s.online, isTrue);
      expect(s.volume, 42);
    });

    test('el evento del televisor sí actualiza', () {
      final s = conLosDos();
      s.debugApplyDeviceEvent(DeviceStateEvent(
        deviceId: 'dev_tv',
        state: const {'on': false},
      ));
      expect(s.isOn, isFalse);
    });

    test('con el monitor elegido, se invierte', () {
      final s = conLosDos(selected: 'tv-ce588d39');
      s.debugApplyDeviceEvent(DeviceStateEvent(
        deviceId: 'dev_tv',
        state: const {'on': false},
      ));
      expect(s.isOn, isTrue, reason: 'el evento del televisor ya no le aplica');
      s.debugApplyDeviceEvent(DeviceStateEvent(
        deviceId: 'dev_tv-ce588d39',
        state: const {'on': false},
      ));
      expect(s.isOn, isFalse, reason: 'ahora manda el del monitor');
    });
  });
}
