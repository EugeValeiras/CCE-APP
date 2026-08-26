// CCE#24: el teléfono en el historial de la casa.
//
// Los payloads de abajo están copiados del event store de llamadas reales
// (26/08/2026). Lo que se prueba es el CRITERIO, no el widget: una llamada
// deja entre cinco y seis eventos y en el historial tiene que quedar UNA
// entrada, humanizada, con la perdida distinguible y filtrable como
// "Teléfono" sin mover los otros filtros.
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/models/event_record.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/views/history/event_grouping.dart';
import 'package:cce_app/views/history/event_presenter.dart';
import 'package:cce_app/views/history/phone_events.dart';
import 'package:cce_app/views/history_screen.dart';

int _seq = 0;

EventRecord _ev(String name, Map<String, dynamic> payload, {String? time}) {
  _seq++;
  return EventRecord(
    time: time ?? '2026-08-26T20:38:${(60 - _seq).toString().padLeft(2, '0')}.000Z',
    id: 'e$_seq',
    channel: 'websocket',
    eventName: name,
    payload: payload,
  );
}

EventRecord _call(Map<String, dynamic> payload) =>
    _ev('phone:call-state', {'event': 'ended', ...payload});

EventRecord _phoneState(Map<String, dynamic> state) => _ev(
      'device:state-changed',
      {'deviceId': 'dev_phone', 'state': state, 'viaBindingId': 'phone_phone'},
    );

// ── Lo que emitió el backend, tal cual ───────────────────────────────────────

final _missed = _call({
  'number': '+542616110154',
  'result': 'missed',
  'hangupBy': 'remote',
  'contactId': 'cmt96lp8k',
  'direction': 'in',
  'startedAt': 1787776653609,
  'durationMs': 0,
  'contactName': 'Cami',
});

final _inAnswered = _call({
  'number': '+542616110154',
  'result': 'answered',
  'hangupBy': 'local',
  'contactId': 'cmt96lp8k',
  'direction': 'in',
  'startedAt': 1787776576863,
  'connectedAt': 1787776586671,
  'durationMs': 7385,
  'contactName': 'Cami',
});

final _inRejected = _call({
  'number': '+542616110154',
  'result': 'rejected',
  'hangupBy': 'local',
  'direction': 'in',
  'startedAt': 1787776816479,
  'durationMs': 0,
  'contactName': 'Cami',
});

final _outAnswered = _call({
  'number': '+5492364552179',
  'result': 'answered',
  'hangupBy': 'local',
  'direction': 'out',
  'startedAt': 1787780129005,
  'connectedAt': 1787780134920,
  'durationMs': 44000,
  'contactName': 'Euge',
});

final _outNotConnected = _call({
  'number': '+5492614161297',
  'result': 'not-connected',
  'hangupBy': 'local',
  'direction': 'out',
  'startedAt': 1787776867279,
  'durationMs': 0,
  'contactName': 'Porton',
});

final _outUnknownNumber = _call({
  'number': '+5491155550000',
  'result': 'not-connected',
  'hangupBy': 'remote',
  'direction': 'out',
  'startedAt': 1787776867279,
  'durationMs': 0,
});

final _incoming = _ev('phone:call-state', {
  'event': 'incoming',
  'number': '',
  'direction': 'in',
});

final _light = _ev('device:state-changed', {
  'deviceId': 'dev_001788010ee4379c',
  'state': {'on': true, 'bri': 254},
});

final _motion = _ev('device:state-changed', {
  'deviceId': 'dev_9749ba54ab83',
  'sensor': {'motion': true},
});

DevicesService _devices() =>
    DevicesService(config: ServerConfig(), socket: SocketService());

void main() {
  group('presentación de una llamada', () {
    final devices = _devices();

    test('la perdida se lee de un vistazo: verbo propio, ícono y rojo', () {
      final r = presentEvent(_missed, devices);
      expect(r.title, 'Perdida de Cami');
      expect(r.subtitle, 'Nadie atendió');
      expect(r.color, CceColors.danger);
    });

    test('entrante atendida: quién, veredicto y duración', () {
      final r = presentEvent(_inAnswered, devices);
      expect(r.title, 'Llamada de Cami');
      expect(r.subtitle, 'Atendida · 0:07');
      expect(r.color, CceColors.ok);
    });

    test('entrante rechazada', () {
      final r = presentEvent(_inRejected, devices);
      expect(r.title, 'Llamada de Cami');
      expect(r.subtitle, 'Rechazada');
    });

    test('saliente contestada', () {
      final r = presentEvent(_outAnswered, devices);
      expect(r.title, 'Llamaste a Euge');
      expect(r.subtitle, 'Contestaron · 0:44');
      expect(r.color, CceColors.ok);
    });

    test('saliente que cortó la casa (ring-and-hangup): sin duración', () {
      final r = presentEvent(_outNotConnected, devices);
      expect(r.title, 'Llamaste a Porton');
      expect(r.subtitle, 'Sonó y se cortó');
    });

    test('sin contacto en la libreta se muestra el número', () {
      final r = presentEvent(_outUnknownNumber, devices);
      expect(r.title, 'Llamaste a +5491155550000');
      expect(r.subtitle, 'No contestaron');
    });

    test('nunca el eventName crudo, ni para un incoming suelto', () {
      final r = presentEvent(_incoming, devices);
      expect(r.title, isNot(contains('phone:')));
    });
  });

  group('una llamada = una entrada', () {
    test('sólo el ended cuenta; incoming y el ciclo de dev_phone son log', () {
      expect(isCallLogNoise(_missed), isFalse);
      expect(isCallLogNoise(_incoming), isTrue);
      expect(isCallLogNoise(_phoneState({'on': true, 'callState': 'ringing'})),
          isTrue);
      expect(isCallLogNoise(_phoneState({'callState': 'active'})), isTrue);
      expect(isCallLogNoise(_phoneState({'on': false, 'callState': 'idle'})),
          isTrue);
      // Telemetría del módem: tampoco es un hecho de la casa.
      expect(isCallLogNoise(_phoneState({'signalBars': 3})), isTrue);
      expect(isCallLogNoise(_phoneState({'reachable': false})), isTrue);
    });

    test('los eventos de los demás dispositivos no se tocan', () {
      expect(isCallLogNoise(_light), isFalse);
      expect(isCallLogNoise(_motion), isFalse);
      expect(isCallLogNoise(_ev('alarm:triggered', {})), isFalse);
      expect(isCallLogNoise(_ev('config:changed', {'section': 'telephony'})),
          isFalse);
    });

    test('la secuencia real de una entrante perdida deja UNA fila', () {
      // Orden descendente, como llega del server.
      final ended = _call({
        'number': '+542616110154',
        'result': 'missed',
        'hangupBy': 'remote',
        'direction': 'in',
        'startedAt': 1787776653609,
        'durationMs': 0,
        'contactName': 'Cami',
      });
      final items = [
        _phoneState({'signalBars': 3}),
        _phoneState({'on': false, 'callState': 'idle'}),
        _phoneState({'callState': 'ended'}),
        ended,
        _light, // otro dispositivo en el medio: nada que agrupar por adyacencia
        _phoneState({'peerName': 'Cami'}),
        _phoneState({
          'on': true,
          'callState': 'ringing',
          'peerNumber': '+542616110154',
          'callDirection': 'in',
        }),
        _ev('phone:call-state', {
          'event': 'incoming',
          'number': '+542616110154',
          'direction': 'in',
          'contactName': 'Cami',
        }),
      ];
      final devices = _devices();
      final visible = items.where((e) => !isCallLogNoise(e)).toList();
      final groups = groupEvents(visible, devices);
      expect(groups.map((g) => g.latest.id), [ended.id, _light.id]);
      expect(presentGroup(groups.first, devices).title, 'Perdida de Cami');
    });
  });

  group('filtro Teléfono', () {
    test('acepta las llamadas y lo de dev_phone, nada más', () {
      expect(HistoryFilter.telefono.accepts(_missed), isTrue);
      expect(HistoryFilter.telefono.accepts(_incoming), isTrue);
      expect(
          HistoryFilter.telefono.accepts(_phoneState({'callState': 'active'})),
          isTrue);
      expect(HistoryFilter.telefono.accepts(_light), isFalse);
      expect(HistoryFilter.telefono.accepts(_motion), isFalse);
      expect(HistoryFilter.telefono.accepts(_ev('alarm:triggered', {})),
          isFalse);
      expect(HistoryFilter.telefono.label, 'Teléfono');
    });

    test('los filtros existentes no ven las llamadas', () {
      for (final f in HistoryFilter.values) {
        if (f == HistoryFilter.all || f == HistoryFilter.telefono) continue;
        expect(f.accepts(_missed), isFalse, reason: '${f.label} aceptó una llamada');
      }
      expect(HistoryFilter.all.accepts(_missed), isTrue);
    });

    test('los filtros existentes siguen aceptando lo suyo', () {
      expect(HistoryFilter.lights.accepts(_light), isTrue);
      expect(HistoryFilter.sensors.accepts(_motion), isTrue);
      expect(HistoryFilter.lights.accepts(_motion), isFalse);
      expect(HistoryFilter.automations.accepts(_ev('automation:executed', {})),
          isTrue);
      expect(HistoryFilter.alarm.accepts(_ev('alarm:triggered', {})), isTrue);
    });
  });
}
