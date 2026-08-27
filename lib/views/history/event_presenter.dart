import 'package:flutter/material.dart';
import '../../models/event_record.dart';
import '../../models/phone_call.dart';
import '../../models/phone_sms.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/mdi.dart';
import '../../utils/time_format.dart';
import '../telephony/call_history_screen.dart' show formatCallDuration;
import 'event_grouping.dart';
import 'phone_events.dart';

/// Presentación humanizada de un evento o grupo: ícono (sin color propio,
/// lo tiñe la fila vía IconTheme), color de acento, título y subtítulo.
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

const Color _tempColor = Color(0xFFFF8A5C);

String _deviceName(EventRecord e, DevicesService devices) {
  final device = resolveDevice(e, devices);
  if (device != null) return devices.displayName(device);
  final raw = rawDeviceId(e);
  return raw.isEmpty ? 'Dispositivo' : raw;
}

/// Humaniza un evento individual (copy sujeto → hecho, sin mayúsculas
/// gritadas).
EventPresentation presentEvent(EventRecord e, DevicesService devices) {
  final p = e.payload ?? const <String, dynamic>{};

  if (e.eventName == 'alarm:triggered') {
    final name = (p['automationName'] ?? 'Alarma').toString();
    final msg = (p['message'] ?? '').toString();
    return EventPresentation(
      icon: Icon(Mdi.alarmLight, size: 22),
      color: CceColors.danger,
      title: 'Alarma: $name',
      subtitle: msg.isEmpty ? null : msg,
    );
  }

  if (e.eventName == 'alarm:armed-changed') {
    final armed = p['armed'] == true;
    return EventPresentation(
      icon: Icon(armed ? Mdi.shield : Mdi.shieldOutline, size: 22),
      color: armed ? CceColors.danger : CceColors.ok,
      title: armed ? 'Alarma activada' : 'Alarma desactivada',
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
        subtitle = 'Automatización · programada';
      case 'manual':
        subtitle = 'Automatización · manual';
      case 'sensor':
        final sensorId = (p['sensorId'] ?? '').toString();
        final sensorDev = resolveDeviceId(sensorId, devices);
        subtitle = sensorDev != null
            ? 'Automatización · ${devices.displayName(sensorDev)}'
            : 'Automatización · por sensor';
      case '':
        subtitle = 'Automatización';
      default:
        subtitle = 'Automatización · $trigger';
    }
    return EventPresentation(
      icon: const CceIcon(CceIcons.automations, size: 20),
      color: CceColors.warm,
      title: name,
      subtitle: subtitle,
    );
  }

  if (e.eventName == 'config:changed') {
    return const EventPresentation(
      icon: Icon(Icons.info_outline, size: 22),
      color: CceColors.info,
      title: 'Configuración actualizada',
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
          ? '$name: $estado'
          : 'Puerta de $name $estado';
      return EventPresentation(
        icon: open
            ? const CceIcon(CceIcons.doorOpen, size: 20)
            : Icon(Mdi.doorClosed, size: 22),
        color: open ? CceColors.contact : CceColors.textSecondary,
        title: title,
      );
    }
    if (sensor['motion'] != null) {
      final motion = sensor['motion'] == true;
      return EventPresentation(
        icon: Icon(
          motion ? Mdi.motionSensor : Mdi.motionSensorOff,
          size: 22,
        ),
        color: motion ? CceColors.motion : CceColors.textSecondary,
        title: motion ? 'Movimiento en $name' : 'Sin movimiento en $name',
      );
    }
    if (sensor['lastKey'] != null) {
      final key = sensor['lastKey'];
      final outlet = sensor['outlet'];
      return EventPresentation(
        icon: const CceIcon(CceIcons.handTap, size: 20),
        color: CceColors.accent,
        title: '$name: botón $key',
        subtitle: outlet != null ? 'outlet $outlet' : null,
      );
    }
    if (sensor['temperature'] is num) {
      final t = (sensor['temperature'] as num).toDouble();
      return EventPresentation(
        icon: Icon(Mdi.thermometer, size: 22),
        color: _tempColor,
        title: '$name: ${t.toStringAsFixed(1)}°',
      );
    }
    if (sensor['humidity'] is num) {
      final h = (sensor['humidity'] as num).toDouble();
      return EventPresentation(
        icon: Icon(Mdi.waterPercent, size: 22),
        color: CceColors.info,
        title: '$name: ${h.toStringAsFixed(0)}%',
      );
    }
  }

  if (state is Map) {
    final on = state['on'];
    final bri = state['bri'];
    // Media (dev_tv/dev_jbl vía /merged): rama PROPIA antes de la de luces —
    // sin esto "Samsung TV: encendido" salía con lamparita y los eventos de
    // volumen/mediaState caían al fallback genérico ("todos son dispositivos":
    // el historial también les debe ícono y copy correctos).
    final device = resolveDevice(e, devices);
    if (device != null && device.isMediaDevice) {
      // TV vs parlante por capability (media_playback/app_launcher son del
      // TV) con fallback por type; el resto de los media son audio.
      final tvLike = device.hasCapability('media_playback') ||
          device.hasCapability('app_launcher') ||
          device.type.toLowerCase().contains('tv');
      final icon = Icon(tvLike ? Mdi.television : Mdi.speaker, size: 22);
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
          title: '$name: volumen al ${volume.round()}%',
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
      // Cualquier otro cambio de estado media (input, app, canal…): genérico
      // pero con SU ícono, nunca la lamparita ni el fallback "Evento de".
      return EventPresentation(
        icon: icon,
        color: CceColors.textTertiary,
        title: 'Evento de $name',
        subtitle: e.eventName,
      );
    }
    if (on != null) {
      if (on == true) {
        final pct = bri is num ? (bri / 254 * 100).round() : null;
        return EventPresentation(
          icon: Icon(Mdi.lightbulbOn, size: 22),
          color: CceColors.warm,
          title: pct != null
              ? '$name: encendido al $pct%'
              : '$name: encendido',
        );
      }
      return EventPresentation(
        icon: Icon(Mdi.lightbulbOutline, size: 22),
        color: CceColors.textTertiary,
        title: '$name: apagado',
      );
    }
    if (bri is num) {
      return EventPresentation(
        icon: Icon(Mdi.brightness6, size: 22),
        color: CceColors.warm,
        title: '$name → ${(bri / 254 * 100).round()}%',
      );
    }
  }

  // Fallback genérico (config desconocida, payloads raros).
  final raw = rawDeviceId(e);
  if (raw.isEmpty) {
    return EventPresentation(
      icon: Icon(Mdi.information, size: 22),
      color: CceColors.textTertiary,
      title: e.eventName,
    );
  }
  return EventPresentation(
    icon: Icon(Mdi.information, size: 22),
    color: CceColors.textTertiary,
    title: 'Evento de $name',
    subtitle: e.eventName,
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
        icon: const CceIcon(CceIcons.sms, size: 20),
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
        icon: const CceIcon(CceIcons.phoneIncoming, size: 20),
        color: CceColors.textTertiary,
        title: 'Está sonando el teléfono',
        subtitle: _callPeerFromPayload(e.payload),
      );
    default:
      // Canal `phone:*` sin presentación propia todavía: con el ícono del
      // teléfono y el nombre del canal como pista, nunca el ⓘ genérico.
      return EventPresentation(
        icon: const CceIcon(CceIcons.phone, size: 20),
        color: CceColors.textTertiary,
        title: 'Teléfono',
        subtitle: e.eventName,
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
    icon: const CceIcon(CceIcons.sms, size: 20),
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
      icon: const CceIcon(CceIcons.phoneMissed, size: 20),
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
    icon: CceIcon(
      c.incoming ? CceIcons.phoneIncoming : CceIcons.phoneOutgoing,
      size: 20,
    ),
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

/// Humaniza un grupo: usa el evento más reciente como base y agrega
/// rango horario / valor anterior. El conteo ×N lo dibuja la fila como
/// pill aparte (no se duplica en el título).
EventPresentation presentGroup(EventGroup g, DevicesService devices) {
  if (g.count == 1) return presentEvent(g.latest, devices);

  final base = presentEvent(g.latest, devices);
  final p = g.latest.payload ?? const <String, dynamic>{};
  final sensor = p['sensor'];
  final state = p['state'];
  final name = _deviceName(g.latest, devices);
  final range = '${TimeFormat.hm(g.from)} – ${TimeFormat.hm(g.to)}';

  if (sensor is Map) {
    if (sensor['motion'] != null) {
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: 'Movimiento en $name',
        subtitle: range,
      );
    }
    if (sensor['lastKey'] != null) {
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: '$name: botón ${sensor['lastKey']}',
        subtitle: range,
      );
    }
    if (sensor['temperature'] is num) {
      final t = (sensor['temperature'] as num).toDouble();
      final oldSensor = g.events.last.payload?['sensor'];
      final prev = oldSensor is Map
          ? (oldSensor['temperature'] as num?)?.toDouble()
          : null;
      final title = prev != null
          ? '$name: ${t.toStringAsFixed(1)}° (antes ${prev.toStringAsFixed(1)}°)'
          : '$name: ${t.toStringAsFixed(1)}°';
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: title,
        subtitle: range,
      );
    }
    if (sensor['humidity'] is num) {
      final h = (sensor['humidity'] as num).toDouble();
      final oldSensor = g.events.last.payload?['sensor'];
      final prev = oldSensor is Map
          ? (oldSensor['humidity'] as num?)?.toDouble()
          : null;
      final title = prev != null
          ? '$name: ${h.toStringAsFixed(0)}% (antes ${prev.toStringAsFixed(0)}%)'
          : '$name: ${h.toStringAsFixed(0)}%';
      return EventPresentation(
        icon: base.icon,
        color: base.color,
        title: title,
        subtitle: range,
      );
    }
  }

  if (state is Map && state['on'] == null && state['bri'] is num) {
    // Drag de brillo colapsado: solo el valor final.
    final pct = ((state['bri'] as num) / 254 * 100).round();
    return EventPresentation(
      icon: base.icon,
      color: base.color,
      title: '$name → $pct%',
      subtitle: range,
    );
  }

  return EventPresentation(
    icon: base.icon,
    color: base.color,
    title: base.title,
    subtitle: range,
  );
}
