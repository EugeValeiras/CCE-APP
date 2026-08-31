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

/// Nombre de una escena CCE por id (acciones on:'scene'). Si la escena ya no
/// existe se muestra el id: mejor pista que un genérico "escena".
String _cceSceneName(DevicesService devices, String? id) {
  if (id == null || id.isEmpty) return 'escena';
  for (final s in devices.scenes) {
    if (s.id == id) return s.name;
  }
  return id;
}

/// Nombre de una escena Hue por id (acciones on:'hueScene'). Mismo fallback
/// al id que [_cceSceneName].
String _hueSceneName(DevicesService devices, String? id) {
  if (id == null || id.isEmpty) return 'escena';
  for (final s in devices.hueScenes) {
    if (s.id == id) return s.name;
  }
  return id;
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

/// Próxima ejecución de un trigger programado de hora fija ("19:04", días
/// 0=dom..6=sáb; vacío = todos). null para intervalos, sin hora válida o si
/// no hay día habilitado. Pura, para la card ("Próxima hoy 19:04") y el test.
DateTime? nextScheduleRun(AutomationTrigger t, {DateTime? now}) {
  if (t.type != 'schedule' || t.scheduleMode == 'interval') return null;
  final time = t.time;
  if (time == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
  if (m == null) return null;
  final hh = int.parse(m.group(1)!);
  final mm = int.parse(m.group(2)!);
  if (hh > 23 || mm > 59) return null;
  final n = now ?? DateTime.now();
  final days = t.days.where((d) => d >= 0 && d <= 6).toSet();
  for (var i = 0; i < 8; i++) {
    final day = DateTime(n.year, n.month, n.day + i);
    final candidate = DateTime(day.year, day.month, day.day, hh, mm);
    if (!candidate.isAfter(n)) continue;
    if (days.isEmpty || days.contains(candidate.weekday % 7)) return candidate;
  }
  return null;
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
    // "Escena X" a secas: la marca Hue no va en la frase, la distingue el
    // ícono naranja de la fila.
    case AutomationActionKind.scene:
      return 'Escena ${_cceSceneName(devices, act.sceneId)}';
    case AutomationActionKind.hueScene:
      return 'Escena ${_hueSceneName(devices, act.hueSceneId)}';
    case AutomationActionKind.device:
      return _devicePhrase(_deviceName(devices, act.deviceId), act);
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

/// 21 → "21", 21.5 → "21.5" (misma convención que la pantalla del termostato).
String _fmtNum(num n) => n == n.roundToDouble()
    ? n.toStringAsFixed(0)
    : n.toDouble().toStringAsFixed(1);

/// Frase de una acción por capability. Los verbos con argumento se leen con su
/// VALOR ("Poner el termostato en 21°"): "CCE Thermostat: setTargetTemp" no
/// dice a cuánto queda la calefacción, que es justo lo que se quiere revisar
/// de un vistazo. Los verbos sin caso propio conservan "Device: Verbo".
String _devicePhrase(String name, AutomationAction act, {bool short = false}) {
  final args = act.args;
  switch (act.verb) {
    case 'setTargetTemp':
      final temp = args['targetTemp'];
      if (temp is! num) break;
      return short ? '$name ${_fmtNum(temp)}°' : 'Poner $name en ${_fmtNum(temp)}°';
    case 'setPower':
      final on = args['on'] == true;
      if (short) return '$name ${on ? 'on' : 'off'}';
      return on ? 'Prender $name' : 'Apagar $name';
    case 'setTempMode':
      final mode = args['mode'];
      if (mode is! String || mode.isEmpty) break;
      final label = tempModeLabel(mode);
      return short ? '$name modo $label' : 'Poner $name en modo $label';
  }
  return short ? '$name ${verbLabel(act.verb)}' : '$name: ${verbLabel(act.verb)}';
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
    case AutomationActionKind.scene:
      return 'escena ${_cceSceneName(devices, act.sceneId)}';
    case AutomationActionKind.hueScene:
      return 'escena ${_hueSceneName(devices, act.hueSceneId)}';
    case AutomationActionKind.device:
      return _devicePhrase(_deviceName(devices, act.deviceId), act,
              short: true)
          .toLowerCase();
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
