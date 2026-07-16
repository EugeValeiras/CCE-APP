import 'package:flutter/material.dart';
import '../../models/event_record.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/mdi.dart';
import '../../utils/time_format.dart';
import 'event_grouping.dart';

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
