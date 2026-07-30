import '../../models/automation.dart';
import '../../services/devices_service.dart';
import '../../utils/button_events.dart';
import '../../utils/verb_labels.dart';

/// Frases humanas en español para automatizaciones (cards, editor, filas).
/// Todo sujeto → hecho, sin flechas ASCII, sin MAYÚSCULAS.

String _deviceName(DevicesService devices, String? id) {
  if (id == null || id.isEmpty) return 'sensor';
  final d = devices.byId(id);
  if (d != null) return devices.displayName(d);
  return id;
}

String _groupName(DevicesService devices, String? id) {
  if (id == null || id.isEmpty) return 'grupo';
  for (final g in devices.groups) {
    if (g.id == id) return g.name;
  }
  return 'grupo';
}

String _hueRoomName(DevicesService devices, String? id) {
  if (id == null) return 'de Hue';
  for (final r in devices.hueRooms) {
    if (r.id == id) return r.name;
  }
  return 'de Hue';
}

String _sceneName(DevicesService devices, Automation a) {
  if (a.source == 'scene') {
    for (final s in devices.scenes) {
      if (s.id == a.sourceId) return s.name;
    }
  } else if (a.source == 'hueScene') {
    for (final s in devices.hueScenes) {
      if (s.id == a.sourceId) return s.name;
    }
  }
  return 'escena';
}

String _num(dynamic v) {
  if (v is double) {
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }
  return v.toString();
}

/// Días compactos: 'L–V', 'S y D', '' (todos/vacío) o abreviados.
String daysCompact(List<int> days) {
  final set = days.where((d) => d >= 0 && d <= 6).toSet();
  if (set.isEmpty || set.length >= 7) return '';
  if (set.length == 5 && [1, 2, 3, 4, 5].every(set.contains)) return 'L–V';
  if (set.length == 2 && set.contains(6) && set.contains(0)) return 'S y D';
  const abbr = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
  final sorted = set.toList()..sort();
  return sorted.map((d) => abbr[d]).join(', ');
}

String _hourOnly(String? hhmm) {
  if (hhmm == null) return '';
  final idx = hhmm.indexOf(':');
  return idx > 0 ? hhmm.substring(0, idx) : hhmm;
}

/// Frase de una entrada de sensor: "Botón 2 del Dial", "Movimiento en X"…
String sensorTriggerPhrase(SensorTrigger t, DevicesService devices) {
  final name = _deviceName(devices, t.sensorId);
  switch (t.sensorField) {
    case 'lastKey':
      // lastKey NO es el número de botón: es el TIPO de pulsación (0 click,
      // 1 doble, 2 mantenido — el mismo contrato que usa pressKindLabel en el
      // historial). Decía "Botón 0 del Office 1-Button" para un pulsador que
      // tiene UN solo botón. Cuál botón físico se aprieta lo dice sensorOutlet,
      // y sólo tiene sentido nombrarlo en los multi-botón.
      final kind = pressKindLabel(int.tryParse('${t.sensorValue}'));
      // Los outlets son 0-based y se muestran +1, igual que en el historial
      // (button_events.dart): "Botón 1" es el primero, no el segundo.
      final outlet = t.sensorOutlet;
      return outlet != null
          ? '$kind en el botón ${outlet + 1} de $name'
          : '$kind en $name';
    case 'motion':
      return t.sensorValue == true
          ? 'Movimiento en $name'
          : 'Sin movimiento en $name';
    case 'contact':
      return t.sensorValue == true ? 'Se abre $name' : 'Se cierra $name';
    case 'temperature':
      final v = _num(t.sensorValue);
      if (t.sensorOperator == 'lt' || t.sensorOperator == 'lte') {
        return '$name baja de $v°';
      }
      if (t.sensorOperator == 'gt' || t.sensorOperator == 'gte') {
        return '$name sube de $v°';
      }
      return '$name a $v°';
    case 'humidity':
      final v = _num(t.sensorValue);
      if (t.sensorOperator == 'lt' || t.sensorOperator == 'lte') {
        return 'Humedad de $name baja de $v%';
      }
      if (t.sensorOperator == 'gt' || t.sensorOperator == 'gte') {
        return 'Humedad de $name sube de $v%';
      }
      return 'Humedad de $name a $v%';
    case 'lockActor':
      return 'Entra ${t.sensorValue}';
    case 'lockEventKind':
      return t.sensorValue == 'doorbell'
          ? 'Tocan el timbre'
          : 'Alguien destraba $name';
    case 'vacuumState':
      switch (t.sensorValue) {
        case 'cleaning':
          return '$name empieza a limpiar';
        case 'docked':
          return '$name vuelve a la base';
        case 'error':
          return '$name en error';
      }
      return '$name: ${_num(t.sensorValue)}';
    default:
      return '$name: ${t.sensorField} ${_num(t.sensorValue)}';
  }
}

/// "Doble click en el botón 2 de Dial", "Movimiento (2 sensores)", "19:30 · L–V",
/// "Cada 15 min · 08–22 h", "Manual".
String triggerPhrase(Automation a, DevicesService devices) {
  final t = a.trigger;
  switch (t.type) {
    case 'schedule':
      if (t.scheduleMode == 'interval') {
        var s = 'Cada ${t.interval} min';
        if (t.fromTime != null && t.toTime != null) {
          s += ' · ${_hourOnly(t.fromTime)}–${_hourOnly(t.toTime)} h';
        }
        return s;
      }
      final d = daysCompact(t.days);
      return d.isEmpty ? (t.time ?? 'Horario') : '${t.time ?? '—'} · $d';
    case 'sensor':
      final triggers = t.sensorTriggers;
      if (triggers.isEmpty) return 'Sensor sin configurar';
      if (triggers.length > 1) {
        if (triggers.every((e) => e.sensorField == 'motion')) {
          return 'Movimiento (${triggers.length} sensores)';
        }
        return '${triggers.length} sensores';
      }
      return sensorTriggerPhrase(triggers.first, devices);
    default:
      return 'Manual';
  }
}

/// Frase larga de UNA acción (filas del editor).
String actionPhrase(AutomationAction act, DevicesService devices) {
  switch (act.kind) {
    case AutomationActionKind.light:
      final name = _deviceName(devices, act.lightId);
      if (act.on == true) {
        final bri = act.bri;
        final pct = bri == null ? '' : ' al ${(bri / 254 * 100).round()}%';
        return 'Prender $name$pct';
      }
      if (act.on == false) return 'Apagar $name';
      return 'Alternar $name';
    case AutomationActionKind.group:
      final name = _groupName(devices, act.groupId);
      switch (act.groupAction) {
        case 'off':
          return 'Apagar grupo $name';
        case 'toggle':
          return 'Alternar grupo $name';
        default:
          return 'Prender grupo $name';
      }
    case AutomationActionKind.hueRoom:
      final name = _hueRoomName(devices, act.hueRoomId);
      switch (act.hueRoomAction) {
        case 'off':
          return 'Apagar room $name';
        case 'toggle':
          return 'Alternar room $name';
        default:
          return 'Prender room $name';
      }
    case AutomationActionKind.device:
      final name = _deviceName(devices, act.deviceId);
      return '$name: ${verbLabel(act.verb)}';
    case AutomationActionKind.notification:
      return 'Aviso: "${act.notificationMessage}"';
    case AutomationActionKind.alarm:
      switch (act.alarmAction) {
        case 'arm':
          return 'Armar la alarma';
        case 'disarm':
          return 'Desarmar la alarma';
        default:
          return 'Alternar la alarma';
      }
    case AutomationActionKind.jbl:
      if (act.jblAction == 'off') return 'Apagar el parlante';
      switch (act.jblOnMode) {
        case 'radio':
          return 'Radio ${act.jblRadioName ?? ''}'.trim();
        case 'plain':
          return 'Prender el parlante';
        default:
          return 'Reanudar la música';
      }
    case AutomationActionKind.advanced:
      if (act.on == 'bri_up') {
        return 'Subir brillo de ${_deviceName(devices, act.lightId)}';
      }
      if (act.on == 'bri_down') {
        return 'Bajar brillo de ${_deviceName(devices, act.lightId)}';
      }
      return 'Acción avanzada';
  }
}

String _actionFragment(AutomationAction act, DevicesService devices) {
  switch (act.kind) {
    case AutomationActionKind.light:
      final name = _deviceName(devices, act.lightId);
      if (act.on == true) return '$name on';
      if (act.on == false) return '$name off';
      return '$name alterna';
    case AutomationActionKind.group:
      final name = _groupName(devices, act.groupId);
      return '$name ${act.groupAction == 'off' ? 'off' : act.groupAction == 'toggle' ? 'alterna' : 'on'}';
    case AutomationActionKind.hueRoom:
      final name = _hueRoomName(devices, act.hueRoomId);
      return '$name ${act.hueRoomAction == 'off' ? 'off' : act.hueRoomAction == 'toggle' ? 'alterna' : 'on'}';
    case AutomationActionKind.device:
      return '${_deviceName(devices, act.deviceId)} ${verbLabel(act.verb)}';
    case AutomationActionKind.notification:
      return 'aviso';
    case AutomationActionKind.alarm:
      return 'alarma';
    case AutomationActionKind.jbl:
      return 'parlante ${act.jblAction == 'off' ? 'off' : 'on'}';
    case AutomationActionKind.advanced:
      return 'avanzada';
  }
}

/// "Living y Cocina off · parlante off · aviso", "Escena 1-Basic",
/// "Grupo Living on". >3 fragmentos → "… +N más".
String actionsPhrase(Automation a, DevicesService devices) {
  switch (a.source) {
    case 'scene':
    case 'hueScene':
      return 'Escena ${_sceneName(devices, a)}';
    case 'group':
      return 'Grupo ${_groupName(devices, a.sourceId)} '
          '${a.sourceAction == 'off' ? 'off' : 'on'}';
    default:
      if (a.actions.isEmpty) return 'Sin acciones';
      final fragments = [
        for (final act in a.actions) _actionFragment(act, devices),
      ];
      if (fragments.length > 3) {
        return '${fragments.take(3).join(' · ')} +${fragments.length - 3} más';
      }
      return fragments.join(' · ');
  }
}

/// Frase de UNA condición.
String conditionPhrase(AutomationCondition c, DevicesService devices) {
  if (c.type == 'timeWindow') {
    return 'de ${c.fromTime ?? '—'} a ${c.toTime ?? '—'}';
  }
  if (c.field == 'brightness') {
    return c.value == 'brighter' ? 'si hay luz' : 'si está oscuro';
  }
  if (c.field == 'lockOpenWay') {
    const ways = {
      'fingerprint': 'con huella',
      'password': 'con clave',
      'card': 'con tarjeta',
      'remote': 'a distancia',
      'face': 'con la cara',
    };
    return ways[c.value] ?? 'con ${c.value}';
  }
  final name = _deviceName(devices, c.sensorId);
  return 'si $name: ${c.field ?? '?'} ${_num(c.value)}';
}

/// "si está oscuro", "con alarma armada", primera + "+N" si hay más.
String conditionsPhrase(Automation a, DevicesService devices) {
  final parts = <String>[
    for (final c in a.trigger.conditions) conditionPhrase(c, devices),
  ];
  switch (a.trigger.alarmCondition) {
    case 'armed':
      parts.add('con alarma armada');
    case 'disarmed':
      parts.add('con alarma desarmada');
  }
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.first} +${parts.length - 1}';
}

/// "Cuando haya movimiento en Pasillo, si está oscuro, prender el grupo
/// Living" — banner vivo del editor.
String editorSummary(Automation a, DevicesService devices) {
  final t = a.trigger;
  String cuando;
  switch (t.type) {
    case 'schedule':
      if (t.scheduleMode == 'interval') {
        cuando = 'cada ${t.interval} min';
        if (t.fromTime != null && t.toTime != null) {
          cuando += ' entre las ${t.fromTime} y las ${t.toTime}';
        }
      } else {
        cuando = 'sean las ${t.time ?? '—'}';
        final d = daysCompact(t.days);
        if (d.isNotEmpty) cuando += ' ($d)';
      }
    case 'sensor':
      if (t.sensorTriggers.isEmpty) {
        cuando = 'se dispare el sensor';
      } else {
        final first = t.sensorTriggers.first;
        final name = _deviceName(devices, first.sensorId);
        switch (first.sensorField) {
          case 'motion':
            cuando = first.sensorValue == true
                ? 'haya movimiento en $name'
                : 'deje de haber movimiento en $name';
          case 'contact':
            cuando =
                first.sensorValue == true ? 'se abra $name' : 'se cierre $name';
          case 'lastKey':
            cuando = 'toques el botón ${_num(first.sensorValue)} del $name';
          case 'temperature':
            cuando = (first.sensorOperator == 'lt' ||
                    first.sensorOperator == 'lte')
                ? '$name baje de ${_num(first.sensorValue)}°'
                : '$name supere los ${_num(first.sensorValue)}°';
          case 'lockActor':
            cuando = 'entre ${first.sensorValue}';
          case 'lockEventKind':
            cuando = first.sensorValue == 'doorbell'
                ? 'toquen el timbre'
                : 'alguien destrabe $name';
          case 'vacuumState':
            cuando = switch (first.sensorValue) {
              'cleaning' => '$name empiece a limpiar',
              'docked' => '$name vuelva a la base',
              'error' => '$name entre en error',
              _ => 'cambie $name',
            };
          default:
            cuando = 'cambie $name';
        }
        if (t.sensorTriggers.length > 1) {
          cuando += t.sensorTriggersMode == 'all'
              ? ' (y ${t.sensorTriggers.length - 1} sensores más)'
              : ' (o ${t.sensorTriggers.length - 1} sensores más)';
        }
      }
    default:
      cuando = 'la ejecutes manualmente';
  }

  String entonces;
  switch (a.source) {
    case 'scene':
    case 'hueScene':
      entonces = 'activar la escena ${_sceneName(devices, a)}';
    case 'group':
      entonces =
          '${a.sourceAction == 'off' ? 'apagar' : 'prender'} el grupo ${_groupName(devices, a.sourceId)}';
    case 'hueRoom':
      entonces =
          '${a.sourceAction == 'off' ? 'apagar' : 'prender'} el room ${_hueRoomName(devices, a.sourceId)}';
    default:
      entonces = a.actions.isEmpty
          ? '(sin acciones todavía)'
          : a.actions.length == 1
              ? actionPhrase(a.actions.first, devices).toLowerCase()
              : '${a.actions.length} acciones';
  }

  final cond = conditionsPhrase(a, devices);
  if (cond.isEmpty) return 'Cuando $cuando, $entonces.';
  return 'Cuando $cuando, $cond, $entonces.';
}
