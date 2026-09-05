import 'package:flutter/material.dart';
import '../../models/event_record.dart';
import '../../models/phone_call.dart';
import '../../models/phone_sms.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../utils/time_format.dart';
import '../../utils/vacuum_state.dart';
import '../../utils/verb_labels.dart';
import '../telephony/call_history_screen.dart' show formatCallDuration;
import 'cause_grouping.dart';
import 'event_grouping.dart';
import 'phone_events.dart';

/// Presentación humanizada de un evento o grupo: ícono (sin color propio,
/// lo tiñe la fila vía IconTheme), color de acento, título y subtítulo.
///
/// UN solo set de íconos (lucide, [CceIcons]) coloreado por semántica: el
/// color dice qué clase de hecho es (ámbar = luz, azul = presencia, naranja
/// = apertura, rojo = alarma/perdida, verde = ok), nunca decora. Y NUNCA se
/// muestra un identificador crudo (`device:state-changed`): si no hay frase
/// para un evento, se dice en castellano qué cambió.
class EventPresentation {
  const EventPresentation({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  final Widget icon;
  final Color color;
  final String title;
  final String? subtitle;
}

/// Tamaño único de los glyphs del historial.
const double _iconSize = 20;

Widget _ic(String svg) => CceIcon(svg, size: _iconSize, emboss: false);

String _deviceName(EventRecord e, DevicesService devices) {
  final device = resolveDevice(e, devices);
  if (device != null) return devices.displayName(device);
  final raw = rawDeviceId(e);
  return raw.isEmpty ? 'Dispositivo' : raw;
}

/// Claves de `state` que NO son un hecho de la casa: telemetría que el
/// dispositivo re-emite entera con cada cambio (listas de opciones, resúmenes
/// de limpieza, consumibles, id de correlación…). Se ignoran al describir un
/// cambio genérico.
const _telemetryKeys = {
  'reachable',
  'rooms',
  'cleanSummary',
  'consumables',
  'fanSpeeds',
  'cleanModes',
  'timestamp',
  'correlationId',
};

/// Etiqueta en castellano de una clave de estado. Reusa el catálogo de verbos
/// (`fanSpeed` ↔ `setFanSpeed` = "Potencia") y completa con las claves que
/// no son verbos.
String _stateKeyLabel(String key) {
  const own = {
    'on': 'encendido',
    'bri': 'brillo',
    'hue': 'color',
    'sat': 'color',
    'ct': 'temperatura de color',
    'battery': 'batería',
    'volume': 'volumen',
    'muted': 'silencio',
    'input': 'entrada',
    'channel': 'canal',
    'app': 'app',
    'mediaState': 'reproducción',
    'vacuumActivity': 'actividad',
    'vacuumState': 'estado',
    'cleanMode': 'modo',
    'fanSpeed': 'potencia',
    'targetTemp': 'objetivo',
    'currentTemp': 'temperatura',
    'systemMode': 'modo',
    'heating': 'calentando',
    'fault': 'falla',
    'childLock': 'bloqueo de teclas',
    'callState': 'llamada',
    'signalBars': 'señal',
    'lineActive': 'línea',
  };
  final o = own[key];
  if (o != null) return o;
  // 'fanSpeed' → 'setFanSpeed' → "Potencia".
  final verb = 'set${key[0].toUpperCase()}${key.substring(1)}';
  final v = kVerbLabels[verb];
  if (v != null) return v.toLowerCase();
  return key;
}

/// Humaniza un evento individual (copy sujeto → hecho, sin mayúsculas
/// gritadas).
EventPresentation presentEvent(EventRecord e, DevicesService devices) {
  final p = e.payload ?? const <String, dynamic>{};

  if (e.eventName == 'alarm:triggered') {
    final name = (p['automationName'] ?? 'Alarma').toString();
    final msg = (p['message'] ?? '').toString();
    return EventPresentation(
      icon: _ic(CceIcons.siren),
      color: CceColors.danger,
      title: 'Alarma: $name',
      subtitle: msg.isEmpty ? null : msg,
    );
  }

  if (e.eventName == 'alarm:armed-changed') {
    final armed = p['armed'] == true;
    return EventPresentation(
      icon: _ic(armed ? CceIcons.alarmShield : CceIcons.shield),
      color: armed ? CceColors.danger : CceColors.textTertiary,
      title: armed ? 'Alarma armada' : 'Alarma desarmada',
    );
  }

  if (e.eventName.startsWith('automation:')) {
    // El payload de automation:executed es {automationId, trigger, sensorId,
    // timestamp} y NO trae name: el título se resuelve SIEMPRE por id.
    final autoId = p['automationId']?.toString();
    final name = devices.automationName(autoId);
    final trigger = (p['trigger'] ?? '').toString();
    String subtitle;
    switch (trigger) {
      case 'schedule':
        subtitle = 'programada';
      case 'manual':
        subtitle = 'manual';
      case 'sensor':
        final sensorId = (p['sensorId'] ?? '').toString();
        final sensorDev = resolveDeviceId(sensorId, devices);
        subtitle = sensorDev != null
            ? 'por ${devices.displayName(sensorDev)}'
            : 'por sensor';
      case '':
        subtitle = 'automatización';
      default:
        subtitle = trigger;
    }
    return EventPresentation(
      icon: _ic(CceIcons.automations),
      color: CceColors.warm,
      title: name,
      subtitle: subtitle,
    );
  }

  if (e.eventName == 'config:changed') {
    return EventPresentation(
      icon: _ic(CceIcons.settings),
      color: CceColors.info,
      title: 'Configuración actualizada',
    );
  }

  if (e.eventName == 'device:command-result') {
    // Acuse del backend a un comando de la app. Sólo el fallo es un hecho:
    // el éxito ya se ve en el cambio de estado que sigue.
    final name = _deviceName(e, devices);
    final status = (p['status'] ?? '').toString();
    final failed = status.isNotEmpty && status != 'confirmed';
    return EventPresentation(
      icon: _ic(failed ? CceIcons.wifiOff : CceIcons.check),
      color: failed ? CceColors.danger : CceColors.textTertiary,
      title: failed ? '$name no respondió' : '$name confirmó la orden',
      subtitle: failed
          ? (status == 'timeout' ? 'sin respuesta' : status)
          : null,
    );
  }

  if (e.eventName.startsWith('phone:')) return _presentPhone(e);

  // device:state-changed / light:changed
  final name = _deviceName(e, devices);
  final sensor = p['sensor'];
  final state = p['state'];

  if (sensor is Map) {
    if (sensor['contact'] != null) {
      final open = sensor['contact'] == true;
      final estado = open ? 'abierta' : 'cerrada';
      final title = name.toLowerCase().contains('puerta')
          ? '$name $estado'
          : 'Puerta de $name $estado';
      return EventPresentation(
        icon: _ic(open ? CceIcons.doorOpen : CceIcons.doorClosed),
        color: open ? CceColors.contact : CceColors.textSecondary,
        title: title,
      );
    }
    if (sensor['motion'] != null) {
      final motion = sensor['motion'] == true;
      return EventPresentation(
        icon: _ic(motion ? CceIcons.personStanding : CceIcons.footprints),
        color: motion ? CceColors.motion : CceColors.textSecondary,
        title: motion ? 'Movimiento en $name' : 'Sin movimiento en $name',
      );
    }
    if (sensor['lastKey'] != null) {
      final key = sensor['lastKey'];
      final outlet = sensor['outlet'];
      return EventPresentation(
        icon: _ic(CceIcons.handTap),
        color: CceColors.accent,
        title: '$name: botón $key',
        subtitle: outlet != null ? 'outlet $outlet' : null,
      );
    }
    // Lecturas numéricas (temperatura, humedad, luz): una sola tabla, la
    // misma que usa la fila colapsada (CCE#112).
    final reading = _numericReadingOf(sensor);
    if (reading != null) {
      return EventPresentation(
        icon: _ic(reading.$1.icon),
        color: reading.$1.color,
        title: name,
        subtitle: reading.$1.format(reading.$2),
      );
    }
  }

  if (state is Map) {
    final on = state['on'];
    final bri = state['bri'];
    final device = resolveDevice(e, devices);

    // Robot aspiradora: la actividad del sidecar (o el estado de Matter) en
    // castellano. Antes caía al fallback genérico y 6 de cada 10 filas del
    // historial decían "Evento de Roborock Qrevo / device:state-changed".
    // Se reconoce por las claves del estado, no sólo por el device: un
    // evento de un robot que ya no está en el inventario también se lee.
    if ((device != null && device.isVacuum) ||
        state.containsKey('vacuumActivity') ||
        state.containsKey('vacuumState')) {
      final act = state['vacuumActivity']?.toString();
      final vs = state['vacuumState']?.toString();
      final label = (act != null ? vacuumActivityLabel[act] : null) ??
          switch (vs) {
            'cleaning' => 'Limpiando',
            'docked' => 'En la base',
            'paused' => 'En pausa',
            'returning' => 'Volviendo a la base',
            'error' => 'Con error',
            'stopped' => 'Detenido',
            _ => null,
          };
      final working = act != null
          ? vacuumWorkingActivities.contains(act)
          : (vs == 'cleaning' || vs == 'returning');
      final battery = state['battery'];
      if (label != null) {
        return EventPresentation(
          icon: _ic(CceIcons.robotVacuum),
          color: act == 'error' || act == 'charging_error' || vs == 'error'
              ? CceColors.danger
              : (working ? CceColors.ok : CceColors.textTertiary),
          title: '$name: ${label.toLowerCase()}',
          subtitle: battery is num ? '${battery.round()}%' : null,
        );
      }
    }

    // Termostato (CCE#101): la actividad del relé (heating), la falla, el
    // objetivo y la temperatura, en castellano. Antes caía a la rama de luces
    // («se encendió» con lamparita) o al fallback genérico. Se reconoce por
    // el device o por las claves propias del clima, como el robot.
    if ((device != null && device.hasCapability('thermostat')) ||
        state.containsKey('heating') ||
        state.containsKey('targetTemp') ||
        state.containsKey('currentTemp')) {
      final t = _presentThermostat(name, state);
      if (t != null) return t;
    }

    // Media (dev_tv/dev_jbl vía /merged): rama PROPIA antes de la de luces —
    // sin esto "Samsung TV: encendido" salía con lamparita y los eventos de
    // volumen/mediaState caían al fallback genérico ("todos son dispositivos":
    // el historial también les debe ícono y copy correctos).
    if (device != null && device.isMediaDevice) {
      // TV vs parlante por capability (media_playback/app_launcher son del
      // TV) con fallback por type; el resto de los media son audio.
      final tvLike = device.hasCapability('media_playback') ||
          device.hasCapability('app_launcher') ||
          device.type.toLowerCase().contains('tv');
      final icon = _ic(tvLike ? CceIcons.tv : CceIcons.speaker);
      if (on != null) {
        return EventPresentation(
          icon: icon,
          color: on == true ? CceColors.warm : CceColors.textTertiary,
          title: on == true ? '$name: encendido' : '$name: apagado',
        );
      }
      final volume = state['volume'];
      if (volume is num) {
        // Volumen 0-100 canónico del backend (la vista JBL reescala, acá no).
        return EventPresentation(
          icon: icon,
          color: CceColors.info,
          title: '$name: volumen',
          subtitle: 'al ${volume.round()}%',
        );
      }
      if (state['muted'] is bool) {
        final muted = state['muted'] == true;
        return EventPresentation(
          icon: icon,
          color: muted ? CceColors.textTertiary : CceColors.info,
          title: muted ? '$name: silenciado' : '$name: sonido activado',
        );
      }
      final mediaState = state['mediaState'];
      if (mediaState is String && mediaState.isNotEmpty) {
        const copy = {
          'playing': 'reproduciendo',
          'paused': 'en pausa',
          'stopped': 'detenido',
        };
        return EventPresentation(
          icon: icon,
          color: mediaState == 'playing' ? CceColors.ok : CceColors.textTertiary,
          title: '$name: ${copy[mediaState] ?? mediaState}',
        );
      }
      // Cualquier otro cambio de estado media (input, app, canal…): con SU
      // ícono y en castellano, nunca el eventName.
      return _genericChange(name, state, icon);
    }
    if (on != null) {
      if (on == true) {
        final pct = bri is num ? (bri / 254 * 100).round() : null;
        return EventPresentation(
          icon: _ic(CceIcons.lights),
          color: CceColors.warm,
          title: '$name se encendió',
          subtitle: pct != null ? 'al $pct%' : null,
        );
      }
      return EventPresentation(
        icon: _ic(CceIcons.lightbulbOff),
        color: CceColors.textTertiary,
        title: '$name se apagó',
      );
    }
    if (bri is num) {
      return EventPresentation(
        icon: _ic(CceIcons.sunMedium),
        color: CceColors.warm,
        title: '$name: brillo',
        subtitle: 'al ${(bri / 254 * 100).round()}%',
      );
    }
    // Sólo cambió la conexión.
    final keys = state.keys.map((k) => k.toString()).toSet();
    if (keys.contains('reachable') &&
        keys.difference(_telemetryKeys).isEmpty) {
      final reachable = state['reachable'] == true;
      return EventPresentation(
        icon: _ic(reachable ? CceIcons.wifi : CceIcons.wifiOff),
        color: reachable ? CceColors.ok : CceColors.danger,
        title: reachable ? '$name volvió a estar en línea' : '$name sin conexión',
      );
    }
    return _genericChange(name, state, _ic(CceIcons.activity));
  }

  // Fallback (payloads raros): en castellano, nunca el identificador.
  final raw = rawDeviceId(e);
  return EventPresentation(
    icon: _ic(CceIcons.activity),
    color: CceColors.textTertiary,
    title: raw.isEmpty ? 'Actividad de la casa' : '$name cambió de estado',
  );
}

/// El termostato en el historial (CCE#101). Una falla manda sobre todo;
/// apagarse es apagarse (el `heating: false` que viene con el mismo push es
/// consecuencia); después la actividad del relé, que ahora viaja sola en el
/// push; después prenderse, el objetivo y la temperatura. null si el estado
/// no trae nada de eso (cae al fallback genérico).
EventPresentation? _presentThermostat(String name, Map state) {
  final fault = state['fault'];
  if (fault is num && fault != 0) {
    return EventPresentation(
      icon: _ic(CceIcons.alarmShield),
      color: CceColors.danger,
      title: 'Falla del termostato (código ${fault.round()})',
      subtitle: name,
    );
  }
  if (state['on'] == false) {
    return EventPresentation(
      icon: _ic(CceIcons.thermometer),
      color: CceColors.textTertiary,
      title: '$name: apagado',
    );
  }
  final heating = state['heating'];
  if (heating is bool) {
    return EventPresentation(
      icon: _ic(heating ? CceIcons.flame : CceIcons.thermometer),
      color: heating ? CceColors.warm : CceColors.textTertiary,
      title: heating ? '$name empezó a calentar' : '$name dejó de calentar',
    );
  }
  if (state['on'] == true) {
    return EventPresentation(
      icon: _ic(CceIcons.thermometer),
      color: CceColors.warm,
      title: '$name: encendido',
    );
  }
  final target = state['targetTemp'];
  if (target is num) {
    return EventPresentation(
      icon: _ic(CceIcons.thermometer),
      color: CceColors.info,
      title: '$name: objetivo',
      subtitle: 'a ${target.toStringAsFixed(1)}°',
    );
  }
  final current = state['currentTemp'];
  if (current is num) {
    return EventPresentation(
      icon: _ic(CceIcons.thermometer),
      color: CceColors.contact,
      title: name,
      subtitle: '${current.toStringAsFixed(1)}°',
    );
  }
  return null;
}

/// Cambio de estado sin frase propia: "X cambió de estado" con las claves que
/// cambiaron, en castellano, como subtítulo.
EventPresentation _genericChange(String name, Map state, Widget icon) {
  final changed = state.keys
      .map((k) => k.toString())
      .where((k) => !_telemetryKeys.contains(k))
      .map(_stateKeyLabel)
      .toSet()
      .toList();
  return EventPresentation(
    icon: icon,
    color: CceColors.textTertiary,
    title: '$name cambió de estado',
    subtitle: changed.isEmpty ? null : changed.take(3).join(' · '),
  );
}

/// Teléfono (CCE#24). Un `switch` por canal: las llamadas
/// (`phone:call-state`) y los SMS (`phone:sms`, CCE#23), con el mismo ícono
/// de base y la misma forma de nombrar al otro lado ([_callPeer]).
EventPresentation _presentPhone(EventRecord e) {
  switch (e.eventName) {
    case kSmsEvent:
      final sms = smsFromEvent(e);
      if (sms != null) return _presentSms(sms);
      return EventPresentation(
        icon: _ic(CceIcons.sms),
        color: CceColors.textTertiary,
        title: 'SMS',
        subtitle: null,
      );
    case kCallStateEvent:
      final call = callFromEvent(e);
      if (call != null) return _presentCall(call);
      // `incoming` (o una forma nueva del canal): [isCallLogNoise] lo saca
      // antes de llegar acá, pero si llega igual no se muestra crudo.
      return EventPresentation(
        icon: _ic(CceIcons.phoneIncoming),
        color: CceColors.textTertiary,
        title: 'Está sonando el teléfono',
        subtitle: _callPeerFromPayload(e.payload),
      );
    default:
      // Canal `phone:*` sin presentación propia todavía: con el ícono del
      // teléfono y en castellano, nunca el nombre del canal.
      return EventPresentation(
        icon: _ic(CceIcons.phone),
        color: CceColors.textTertiary,
        title: 'Actividad del teléfono',
      );
  }
}

/// Un SMS recibido: de quién, y el texto en una línea (el completo está en la
/// pantalla de mensajes del teléfono).
EventPresentation _presentSms(PhoneSms s) {
  final who = s.displayName == 'Remitente desconocido'
      ? 'remitente desconocido'
      : s.displayName;
  return EventPresentation(
    icon: _ic(CceIcons.sms),
    color: CceColors.accent,
    title: 'SMS de $who',
    subtitle: s.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

/// Una llamada terminada, en una línea: quién, qué pasó y cuánto duró.
///
/// La PERDIDA es la información más útil de toda la lista: va con su propio
/// verbo en el título ("Perdida de …"), el ícono de perdida y el rojo de
/// [CceColors.danger], que la fila usa para teñir el ícono. El resto se lee
/// por dirección ("Llamada de …" / "Llamaste a …") y el subtítulo lleva el
/// veredicto con las mismas palabras que el historial dedicado
/// ([PhoneCall.resultLabel]) más la duración cuando la hubo.
EventPresentation _presentCall(PhoneCall c) {
  final who = _callPeer(c);
  if (c.isMissed) {
    return EventPresentation(
      icon: _ic(CceIcons.phoneMissed),
      color: CceColors.danger,
      title: 'Perdida de $who',
      subtitle: 'Nadie atendió',
    );
  }
  final answered = c.result == CallResult.answered;
  final Color color;
  if (answered) {
    color = CceColors.ok;
  } else if (c.result == CallResult.failed) {
    // Falló la línea, no la persona: se marca como algo a mirar.
    color = CceColors.warm;
  } else {
    // Rechazada / no contestaron / sonó y se cortó: sin drama.
    color = CceColors.textTertiary;
  }
  final duration = c.duration.inSeconds > 0
      ? ' · ${formatCallDuration(c.duration)}'
      : '';
  return EventPresentation(
    icon: _ic(c.incoming ? CceIcons.phoneIncoming : CceIcons.phoneOutgoing),
    color: color,
    title: c.incoming ? 'Llamada de $who' : 'Llamaste a $who',
    subtitle: '${c.resultLabel}$duration',
  );
}

/// El otro lado de la llamada: el nombre del contacto si el número está en
/// la libreta (el backend lo resuelve contra `config.telephony.contacts` y lo
/// manda como `contactName`), si no el número, y si tampoco vino número (una
/// entrante sin caller ID) se dice explícitamente.
String _callPeer(PhoneCall c) {
  final name = c.contactName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final number = c.number.trim();
  return number.isEmpty ? 'número desconocido' : number;
}

String? _callPeerFromPayload(Map<String, dynamic>? p) {
  if (p == null) return null;
  final name = (p['contactName'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final number = (p['number'] ?? '').toString().trim();
  return number.isEmpty ? null : number;
}

/// Una lectura numérica del bloque sensor: cómo se dibuja y cómo se escribe.
class _NumericReading {
  const _NumericReading(this.key, this.icon, this.color, this.format);
  final String key;
  final String icon;
  final Color color;
  final String Function(double) format;
}

/// Las lecturas numéricas que el historial sabe leer, en orden de prioridad.
/// UNA tabla para la lectura suelta y para la corrida colapsada (CCE#112).
final List<_NumericReading> _numericReadings = [
  _NumericReading('temperature', CceIcons.thermometer, CceColors.contact,
      (v) => '${v.toStringAsFixed(1)}°'),
  _NumericReading('humidity', CceIcons.droplet, CceColors.info,
      (v) => '${v.toStringAsFixed(0)}%'),
  _NumericReading(
      'lux', CceIcons.sunMedium, CceColors.warm, (v) => '${v.round()} lx'),
];

/// La primera lectura numérica presente en [sensor], con su valor.
(_NumericReading, double)? _numericReadingOf(Map sensor) {
  for (final r in _numericReadings) {
    final v = sensor[r.key];
    if (v is num) return (r, v.toDouble());
  }
  return null;
}

/// Humaniza un grupo: usa el evento más reciente como base y, en el
/// subtítulo, desde cuándo viene repitiéndose ("desde 11:31"). El conteo ×N
/// lo dibuja la fila como pill aparte (no se duplica en el título).
EventPresentation presentGroup(EventGroup g, DevicesService devices) {
  if (g.count == 1) return presentEvent(g.latest, devices);

  final base = presentEvent(g.latest, devices);
  final p = g.latest.payload ?? const <String, dynamic>{};
  final sensor = p['sensor'];
  final state = p['state'];
  final name = _deviceName(g.latest, devices);
  // La fila ya muestra la hora del más reciente en su riel: el rango se
  // reduce a desde cuándo (null si todo cayó en el mismo minuto).
  final from = TimeFormat.hm(g.from);
  final String? since = from == TimeFormat.hm(g.to) ? null : 'desde $from';

  if (sensor is Map) {
    if (sensor['motion'] != null) {
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: 'Movimiento en $name',
        subtitle: since,
      );
    }
    if (sensor['lastKey'] != null) {
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: '$name: botón ${sensor['lastKey']}',
        subtitle: since,
      );
    }
    // Una corrida de lecturas numéricas se lee como «de → a». La tabla es la
    // misma que la de la lectura suelta: sin esto la rama de lux quedó sin
    // escribir y dos lecturas en 30 min perdían el número (review de CCE#112).
    final reading = _numericReadingOf(sensor);
    if (reading != null) {
      final spec = reading.$1;
      final oldSensor = g.events.last.payload?['sensor'];
      final prevRaw = oldSensor is Map ? oldSensor[spec.key] : null;
      final prev = prevRaw is num ? prevRaw.toDouble() : null;
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: name,
        subtitle: prev != null
            ? '${spec.format(prev)} → ${spec.format(reading.$2)}'
            : spec.format(reading.$2),
      );
    }
  }

  if (state is Map && state['on'] == null && state['bri'] is num) {
    // Drag de brillo colapsado: solo el valor final.
    final pct = ((state['bri'] as num) / 254 * 100).round();
    return EventPresentation(
      icon: base.icon,
      color: base.color,
      title: '$name: brillo',
      subtitle: 'al $pct%',
    );
  }

  return EventPresentation(
    icon: base.icon,
    color: base.color,
    title: base.title,
    subtitle: since ?? base.subtitle,
  );
}

/// Humaniza un HECHO (CCE#75): los cambios que comparten causa, en una sola
/// frase. Es la diferencia entre leer doce filas y leer «el Hall se encendió
/// al 56%».
///
/// Tres formas, según lo que el hecho abarque:
///
///  - un aparato y una sola semántica → exactamente lo de antes ([presentGroup]);
///  - un aparato y varias semánticas → una línea: `Hall 4: se encendió · 56% ·
///    temp. de color` (las tres filas que hoy se ven separadas);
///  - varios aparatos → el sujeto común y el hecho: `Hall se encendió`, con el
///    brillo resultante como metadato. El «4 luces» lo pone la fila.
EventPresentation presentCause(CauseGroup c, DevicesService devices) {
  if (c.runs.length == 1 && c.deviceCount == 1) {
    return presentGroup(c.runs.first, devices);
  }

  // El evento que manda es el que trae el hecho principal (`on`); si ninguno
  // lo trae, el más reciente. Sirve para el ícono y el color, que ya saben
  // distinguir luz de robot, de TV y de sensor.
  final events = c.events;
  final principal = events.firstWhere(
    (e) {
      final s = e.payload?['state'];
      return s is Map && s['on'] != null;
    },
    orElse: () => c.latest,
  );
  final base = presentEvent(principal, devices);
  final f = _causeFacts(c);
  final hechos = f.labels;

  if (c.deviceCount == 1) {
    // Las tres filas de «Hall 4» (encendido, brillo, temperatura de color) en
    // una línea, que es la forma que pide el issue para el fallback.
    final name = _deviceName(principal, devices);
    if (hechos.isEmpty) return presentGroup(c.runs.first, devices);
    return EventPresentation(
      icon: base.icon,
      color: base.color,
      title: '$name: ${hechos.join(' · ')}',
    );
  }

  final sujeto = causeSubject(c, devices);
  if (hechos.isEmpty) {
    return EventPresentation(
      icon: base.icon,
      color: base.color,
      title: '${sujeto.text} '
          '${sujeto.plural ? 'cambiaron' : 'cambió'} de estado',
    );
  }
  // Con varios aparatos el hecho va en el título y SÓLO el brillo como
  // metadato: «Hall se encendió» + «al 56%». Que además haya cambiado la
  // temperatura de color al encenderse es detalle, y el detalle está a un
  // toque (la fila despliega los cambios individuales) — la columna de la
  // derecha es angosta y una lista ahí se corta a la mitad.
  if (f.on != null) {
    // Concordancia: «Hall se encendió» pero «5 luces se encendieron». Un
    // sujeto contado es plural, y el historial lo lee gente, no un parser.
    final verbo = f.on!
        ? (sujeto.plural ? 'se encendieron' : 'se encendió')
        : (sujeto.plural ? 'se apagaron' : 'se apagó');
    return EventPresentation(
      icon: base.icon,
      color: base.color,
      title: '${sujeto.text} $verbo',
      subtitle: f.brightnessLabel,
    );
  }
  return EventPresentation(
    icon: base.icon,
    color: base.color,
    title: '${sujeto.text}: ${hechos.join(' · ')}',
  );
}

/// El SUJETO de un hecho que abarca varios aparatos, con su número gramatical:
/// el nombre del grupo configurado si el hecho cae justo sobre él, si no el
/// prefijo común de los nombres («Hall 1..4» → «Hall»), y si tampoco hay,
/// cuántos son y de qué («5 luces») — que es plural y arrastra el verbo.
({String text, bool plural}) causeSubject(
  CauseGroup c,
  DevicesService devices,
) {
  for (final g in devices.groups) {
    final miembros = g.lightIds.toSet();
    if (miembros.length == c.deviceIds.length &&
        miembros.containsAll(c.deviceIds)) {
      return (text: g.name, plural: false);
    }
  }
  final nombres = <String>[];
  for (final id in c.deviceIds) {
    final d = devices.byId(id);
    nombres.add(d != null ? devices.displayName(d) : id);
  }
  final prefijo = _commonPrefix(nombres);
  if (prefijo != null) return (text: prefijo, plural: false);
  return (text: causeCountLabel(c, devices), plural: true);
}

/// «4 luces» / «4 dispositivos»: cuántos aparatos abarca el hecho, dicho por
/// lo que son. Un apagado de cinco luces no son «5 dispositivos».
String causeCountLabel(CauseGroup c, DevicesService devices) {
  final todasLuces = c.deviceIds.every((id) {
    final d = devices.byId(id);
    return d != null && d.isLight;
  });
  return '${c.deviceCount} ${todasLuces ? 'luces' : 'dispositivos'}';
}

/// Prefijo común POR PALABRAS de los nombres, o null si no hay uno que sirva.
/// Por palabras y no por caracteres: «Living» y «Livingston» no comparten
/// sujeto aunque compartan letras.
String? _commonPrefix(List<String> nombres) {
  if (nombres.length < 2) return nombres.isEmpty ? null : nombres.first;
  final partes = [
    for (final n in nombres) n.trim().split(RegExp(r'\s+')),
  ];
  final out = <String>[];
  for (var i = 0;; i++) {
    if (partes.any((p) => i >= p.length)) break;
    final primero = partes.first[i];
    if (!partes.every((p) => p[i].toLowerCase() == primero.toLowerCase())) {
      break;
    }
    out.add(primero);
  }
  if (out.isEmpty) return null;
  // Un prefijo que ya es el nombre entero de alguno no distingue nada.
  if (partes.any((p) => p.length == out.length)) return null;
  return out.join(' ');
}

/// Los hechos del grupo, en orden de importancia y sin repetir: primero el
/// encendido/apagado, después el brillo resultante, después el color. Los
/// valores son los del evento MÁS RECIENTE que los trae — un drag de brillo
/// deja el valor final, no el del camino.
_Facts _causeFacts(CauseGroup c) {
  bool? on;
  num? bri;
  var ct = false;
  var color = false;
  final otras = <String>[];

  // Del más reciente al más viejo: el primero que aparece gana.
  for (final e in c.events) {
    final state = e.payload?['state'];
    if (state is! Map) continue;
    if (on == null && state['on'] is bool) on = state['on'] as bool;
    if (bri == null && state['bri'] is num) bri = state['bri'] as num;
    if (state['ct'] != null) ct = true;
    if (state['hue'] != null || state['sat'] != null || state['xy'] != null) {
      color = true;
    }
    for (final k in state.keys.map((k) => k.toString())) {
      if (const {'on', 'bri', 'ct', 'hue', 'sat', 'xy'}.contains(k)) continue;
      if (_telemetryKeys.contains(k)) continue;
      final label = _stateKeyLabel(k);
      if (!otras.contains(label)) otras.add(label);
    }
  }

  // El brillo de un apagado es el del fade a cero: no es un hecho, es el
  // camino. Sólo cuenta cuando la luz quedó prendida.
  final briUtil = on == false ? null : bri;
  final out = <String>[];
  if (on != null) out.add(on ? 'se encendió' : 'se apagó');
  if (briUtil != null) out.add('al ${(briUtil / 254 * 100).round()}%');
  if (ct) out.add('temp. de color');
  if (color) out.add('color');
  out.addAll(otras);
  return _Facts(on: on, bri: briUtil, labels: out);
}

/// Lo que cambió en un hecho, ya resuelto: el encendido, el brillo final y
/// las frases en el orden en que se leen.
class _Facts {
  const _Facts({this.on, this.bri, required this.labels});

  final bool? on;
  final num? bri;
  final List<String> labels;

  String? get brightnessLabel =>
      bri == null ? null : 'al ${(bri! / 254 * 100).round()}%';
}
