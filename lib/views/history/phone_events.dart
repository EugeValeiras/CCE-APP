/// El teléfono en el historial de la casa (CCE#24): qué eventos son del
/// teléfono, cuál de ellos ES la llamada y cuáles son su log.
///
/// Una llamada deja en el event store entre cuatro y seis eventos:
///
///  - `phone:call-state` `incoming` (sólo entrantes; 3 de 4 veces sin número,
///    porque sale con el primer RING y el caller ID llega después);
///  - `device:state-changed` de `dev_phone` con `callState`
///    `ringing`/`dialing` → `active` → `ended` → `idle`, más los deltas de
///    `peerNumber`/`peerName` en el medio;
///  - `phone:call-state` `ended`, con el veredicto: dirección, resultado,
///    duración, quién cortó y el contacto ya resuelto por el backend.
///
/// Y sin llamada de por medio `dev_phone` sigue emitiendo `signalBars` casi
/// cada minuto y algún `reachable` que va y viene. El historial de la casa
/// cuenta lo que pasó, no vuelca el log: acá se decide que **la llamada es el
/// `ended`** y todo lo demás es ruido que no se lista. No es agrupación por
/// adyacencia (`event_grouping.dart`): entre el `ringing` y el `ended` pasan
/// eventos de otros dispositivos y un run adyacente no los juntaría.
///
/// Los SMS (#23) van a llegar por otro `phone:*`: [isPhoneEvent] ya los toma
/// para el filtro, y su presentación entra como un `case` más en
/// `event_presenter.dart` sin tocar esto.
library;

import '../../models/event_record.dart';
import '../../models/phone_call.dart';
import '../../services/telephony_service.dart' show kPhoneDeviceId;
import 'event_grouping.dart' show rawDeviceId;

/// Canal de las llamadas: `incoming` cuando suena, `ended` cuando terminó.
const String kCallStateEvent = 'phone:call-state';

/// Evento del teléfono, para el filtro "Teléfono": el canal `phone:*`
/// (llamadas hoy, SMS cuando entre el #23) o un cambio de estado de
/// `dev_phone`.
bool isPhoneEvent(EventRecord e) =>
    e.eventName.startsWith('phone:') || isPhoneDeviceState(e);

/// `device:state-changed` del teléfono 4G (`dev_phone`).
bool isPhoneDeviceState(EventRecord e) =>
    (e.eventName == 'device:state-changed' ||
        e.eventName == 'light:changed') &&
    rawDeviceId(e) == kPhoneDeviceId;

/// UNA llamada = UNA entrada: lo que se saca del historial ANTES de filtrar y
/// agrupar.
///
///  - `phone:call-state` que no sea `ended`: el `incoming` no tiene veredicto
///    y casi nunca tiene número; el `ended` de la misma llamada lo cuenta todo.
///  - Cualquier `device:state-changed` de `dev_phone`: el ciclo de la llamada
///    ya está resumido en el `ended`, y `signalBars`/`reachable` son telemetría
///    del módem, no un hecho de la casa. (Sin esto, además, el `{on: true,
///    callState: 'dialing'}` caía en el filtro "Luces" como "Teléfono:
///    encendido".)
bool isCallLogNoise(EventRecord e) {
  if (e.eventName == kCallStateEvent) return e.payload?['event'] != 'ended';
  return isPhoneDeviceState(e);
}

/// La llamada que cuenta un `phone:call-state` de fin, con el mismo modelo que
/// `GET /phone/calls`: el payload del `ended` es un espejo del historial
/// dedicado (`direction`, `number`, `contactId`, `contactName`, `startedAt`,
/// `connectedAt`, `durationMs`, `result`, `hangupBy`), así que el nombre del
/// contacto, la etiqueta del resultado y la duración salen de [PhoneCall] y
/// se leen igual acá que detrás del reloj del teléfono.
///
/// `null` para cualquier otra forma del canal.
PhoneCall? callFromEvent(EventRecord e) {
  if (e.eventName != kCallStateEvent) return null;
  final p = e.payload;
  if (p == null || p['event'] != 'ended') return null;
  return PhoneCall.fromJson(p);
}
