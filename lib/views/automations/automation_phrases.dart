import '../../models/automation.dart';
import '../../models/automation_flow.dart';
import '../../services/devices_service.dart';
import '../../models/device.dart';
import '../../utils/button_events.dart';
import '../../utils/enum_options.dart';
import '../../utils/verb_labels.dart';

/// Frases humanas en español para automatizaciones (cards, wizard, filas,
/// narración de un flujo en solo lectura). Todo sujeto → hecho, sin flechas
/// ASCII, sin MAYÚSCULAS.
///
/// Las frases de la card y del resumen leen [Automation.effectiveActions] y
/// [Automation.effectiveConditions]: con flujo propio (CCE#64) lo que corre
/// es el árbol, no el `actions` legacy.

/// "Prender Living" → "prender Living": baja SÓLO la primera letra, los
/// nombres de dispositivos conservan sus mayúsculas.
String _lcFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

String _ucFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
    // CCE#112 — el lux numérico de los SNZB-03PR2.
    case 'lux':
      final v = _num(t.sensorValue);
      if (t.sensorOperator == 'lt' || t.sensorOperator == 'lte') {
        return 'Luz de $name baja de $v lx';
      }
      if (t.sensorOperator == 'gt' || t.sensorOperator == 'gte') {
        return 'Luz de $name sube de $v lx';
      }
      return 'Luz de $name a $v lx';
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
    case 'incomingCall':
      return 'Llamada entrante${_callFromSuffix(t)}';
    case 'callStarted':
      return 'Empieza una llamada${_callFromSuffix(t)}';
    case 'callEnded':
      return 'Termina una llamada${_callFromSuffix(t)}';
    case 'calendar':
      return t.raw['calendarEdge'] == 'end'
          ? 'Termina un evento del calendario'
          : 'Empieza un evento del calendario';
    default:
      return 'Manual';
  }
}

/// " de un contacto" / " de un desconocido" según el filtro `callFrom` de los
/// triggers de telefonía (la app no tiene la libreta a mano para el nombre).
String _callFromSuffix(AutomationTrigger t) {
  switch (t.raw['callFrom']) {
    case 'contact':
      return ' de un contacto';
    case 'known':
      return ' de un conocido';
    case 'unknown':
      return ' de un desconocido';
    default:
      return '';
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
      return _devicePhrase(
        _deviceName(devices, act.deviceId),
        act,
        state: devices.byId(act.deviceId)?.state,
      );
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
      // Acciones que el Dashboard sabe armar y la app sólo muestra (la fila
      // no tiene lápiz): se narran igual, no como "Acción avanzada".
      if (act.on == 'announce') {
        return 'Anunciar «${act.raw['announcerId'] ?? '?'}»';
      }
      if (act.on == 'automation') return _automationTogglePhrase(act, devices);
      if (act.on == 'call') {
        final number = act.raw['callNumber'];
        return number is String && number.isNotEmpty
            ? 'Llamar al $number'
            : 'Llamar a un contacto';
      }
      return 'Acción avanzada';
  }
}

/// "Activar «Modo movimiento»" / "Desactivar 2 automatizaciones" / "Alternar…"
String _automationTogglePhrase(AutomationAction act, DevicesService devices) {
  final ids = act.raw['automationIds'];
  final list = ids is List ? [for (final i in ids) i.toString()] : <String>[];
  final verb = switch (act.raw['automationAction']) {
    'enable' => 'Activar',
    'disable' => 'Desactivar',
    _ => 'Alternar',
  };
  if (list.length == 1) return '$verb «${devices.automationName(list.first)}»';
  return '$verb ${list.length} automatizaciones';
}

/// 21 → "21", 21.5 → "21.5" (misma convención que la pantalla del termostato).
String _fmtNum(num n) => n == n.roundToDouble()
    ? n.toStringAsFixed(0)
    : n.toDouble().toStringAsFixed(1);

/// Frase de una acción por capability. Los verbos con argumento se leen con su
/// VALOR ("Poner el termostato en 21°"): "CCE Thermostat: setTargetTemp" no
/// dice a cuánto queda la calefacción, que es justo lo que se quiere revisar
/// de un vistazo. Los verbos sin caso propio conservan "Device: Verbo".
String _devicePhrase(
  String name,
  AutomationAction act, {
  bool short = false,
  DeviceState? state,
}) {
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
    // CCE#101 — «Calentar X (a N°)» / «Dejar de calentar X». El objetivo es
    // opcional: sin él la API elige un grado más que el ambiente.
    case 'startHeating':
      final temp = args['targetTemp'];
      final to = temp is num ? ' a ${_fmtNum(temp)}°' : '';
      return short ? 'Calentar $name$to' : 'Calentar $name$to';
    case 'stopHeating':
      return 'Dejar de calentar $name';
    // CCE#100 — la luz con modos y escenas propias (Hexagon). El modo se lee en
    // castellano y la escena por el NOMBRE que le puso el dueño: el arg guarda
    // el id de la escena (`tuyascene_a`), que no le dice nada a nadie.
    case 'setMode':
      final mode = args['mode'];
      if (mode is! String || mode.isEmpty) break;
      final label = lightModeLabel(mode);
      return short ? '$name modo $label' : 'Poner $name en modo $label';
    case 'setScene':
      final id = args['sceneId'];
      if (id is! String || id.isEmpty) break;
      // Sin el estado del device no se puede resolver el nombre; el id crudo
      // es mejor que nada, y es lo que pasa con un device desconectado.
      final label =
          state == null ? id : enumOptionLabel('LIGHT_SCENES', id, state);
      return short ? '$name «$label»' : 'Poner $name en la escena «$label»';
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
          state: devices.byId(act.deviceId)?.state,
              short: true)
          .toLowerCase();
    case AutomationActionKind.notification:
      return 'aviso';
    case AutomationActionKind.alarm:
      return 'alarma';
    case AutomationActionKind.jbl:
      return 'parlante ${act.jblAction == 'off' ? 'off' : 'on'}';
    case AutomationActionKind.advanced:
      return switch (act.on) {
        'announce' => 'anuncio',
        'automation' => 'automatizaciones',
        'call' => 'llamada',
        _ => 'avanzada',
      };
  }
}

/// "Living y Cocina off · parlante off · aviso", "Escena 1-Basic",
/// "Grupo Living on". >3 fragmentos → "… +N más". Con flujo propio se
/// anteponen las esperas: "Living on · esperar 5 min · Living off".
String actionsPhrase(Automation a, DevicesService devices) {
  switch (a.source) {
    case 'scene':
    case 'hueScene':
      return 'Escena ${_sceneName(devices, a)}';
    case 'group':
      return 'Grupo ${_groupName(devices, a.sourceId)} '
          '${a.sourceAction == 'off' ? 'off' : 'on'}';
    default:
      final acts = a.effectiveActions;
      if (acts.isEmpty) {
        // Un flujo que sólo tiene ramas que no son el camino feliz (un
        // waitFor con onTimeout, p.ej.) no es "sin acciones": es un flujo.
        return a.hasOwnFlow ? 'Flujo del Dashboard' : 'Sin acciones';
      }
      final fragments = a.hasOwnFlow
          ? _flowFragments(a.flow, devices)
          : [for (final act in acts) _actionFragment(act, devices)];
      if (fragments.length > 3) {
        return '${fragments.take(3).join(' · ')} +${fragments.length - 3} más';
      }
      return fragments.join(' · ');
  }
}

/// Los fragmentos de la card para un flujo propio: acciones del camino feliz
/// con las esperas intercaladas ("Living on · esperar 5 min · Living off").
List<String> _flowFragments(List<FlowStep> flow, DevicesService devices) {
  final out = <String>[];
  void walk(List<FlowStep> steps) {
    for (final s in steps) {
      switch (s) {
        case FlowDoStep():
          for (final a in s.actions) {
            out.add(_actionFragment(
                AutomationAction.fromJson(flowActionToLegacy(a)), devices));
          }
        case FlowWaitStep():
          out.add(waitPhrase(s.seconds?.round() ?? 0));
        case FlowIfStep():
          walk(s.then);
        default:
          break;
      }
    }
  }

  walk(flow);
  return out;
}

const _lockWays = {
  'fingerprint': 'con huella',
  'password': 'con clave',
  'card': 'con tarjeta',
  'remote': 'a distancia',
  'face': 'con la cara',
};

/// "el parlante" / "la tele" para las condiciones `modulePower`.
String _moduleName(dynamic module) => switch (module) {
      'jbl' => 'el parlante',
      'tv' => 'la tele',
      _ => '$module',
    };

/// Frase de UNA condición (pastilla de la card, filas del sheet SOLO SI).
String conditionPhrase(AutomationCondition c, DevicesService devices) {
  if (c.type == 'timeWindow') {
    return 'de ${c.fromTime ?? '—'} a ${c.toTime ?? '—'}';
  }
  if (c.type == 'modulePower') {
    final on = c.raw['on'] == true;
    return 'con ${_moduleName(c.raw['module'])} ${on ? 'prendido' : 'apagado'}'
        .replaceFirst('la tele prendido', 'la tele prendida')
        .replaceFirst('la tele apagado', 'la tele apagada');
  }
  if (c.type == 'deviceState') {
    final name = _deviceName(devices, c.raw['deviceId'] as String?);
    return 'si $name: ${c.field ?? '?'} ${_num(c.value)}';
  }
  if (c.field == 'brightness') {
    return c.value == 'brighter' ? 'si hay luz' : 'si está oscuro';
  }
  // CCE#112 — «si luz < 30 lx», con el símbolo: es como se lee un umbral.
  if (c.field == 'lux') {
    return 'si luz ${_opSymbol(c.operator)} ${_num(c.value)} lx';
  }
  if (c.field == 'lockOpenWay') {
    return _lockWays[c.value] ?? 'con ${c.value}';
  }
  final name = _deviceName(devices, c.sensorId);
  return 'si $name: ${c.field ?? '?'} ${_num(c.value)}';
}

/// La condición como CLÁUSULA, sin el "si" adelante, para armar oraciones:
/// "está oscuro", "es entre las 20:00 y las 07:00", "el parlante está
/// apagado", "hay movimiento en Pasillo".
String conditionClause(AutomationCondition c, DevicesService devices) {
  switch (c.type) {
    case 'timeWindow':
      return 'es entre las ${c.fromTime ?? '—'} y las ${c.toTime ?? '—'}';
    case 'modulePower':
      final on = c.raw['on'] == true;
      final module = _moduleName(c.raw['module']);
      final adj = module == 'la tele'
          ? (on ? 'prendida' : 'apagada')
          : (on ? 'prendido' : 'apagado');
      return '$module está $adj';
    case 'deviceState':
      final name = _deviceName(devices, c.raw['deviceId'] as String?);
      return '$name tiene ${c.field ?? '?'} en ${_num(c.value)}';
  }
  final name = _deviceName(devices, c.sensorId);
  switch (c.field) {
    case 'brightness':
      return c.value == 'brighter' ? 'hay luz' : 'está oscuro';
    case 'lockOpenWay':
      return 'abre ${_lockWays[c.value] ?? 'con ${c.value}'}';
    case 'motion':
      return c.value == true
          ? 'hay movimiento en $name'
          : 'no hay movimiento en $name';
    case 'contact':
      return c.value == true ? '$name está abierto' : '$name está cerrado';
    case 'temperature':
      final v = _num(c.value);
      if (c.operator == 'lt' || c.operator == 'lte') {
        return '$name está por debajo de $v°';
      }
      if (c.operator == 'gt' || c.operator == 'gte') {
        return '$name está por encima de $v°';
      }
      return '$name está a $v°';
    case 'lux':
      final v = _num(c.value);
      if (c.operator == 'lt' || c.operator == 'lte') {
        return 'la luz de $name está por debajo de $v lx';
      }
      if (c.operator == 'gt' || c.operator == 'gte') {
        return 'la luz de $name está por encima de $v lx';
      }
      return 'la luz de $name está en $v lx';
  }
  return '$name tiene ${c.field ?? '?'} en ${_num(c.value)}';
}

/// El operador de una condición numérica como símbolo («<», «≥»); igualdad si falta.
String _opSymbol(String? op) => switch (op) {
      'lt' => '<',
      'lte' => '≤',
      'gt' => '>',
      'gte' => '≥',
      _ => '=',
    };

/// Las frases de VARIAS condiciones, desambiguadas: dos «está oscuro» de dos
/// sensores distintos se leen como una sola si no se dice quién mide, así que
/// las repetidas llevan el sensor ("está oscuro en Living Movimiento 1").
/// [phrase] arma cada frase (clausula u oración corta).
List<String> disambiguatedConditions(
  List<AutomationCondition> conds,
  DevicesService devices,
  String Function(AutomationCondition) phrase,
) {
  final base = [for (final c in conds) phrase(c)];
  final counts = <String, int>{};
  for (final b in base) {
    counts[b] = (counts[b] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < conds.length; i++)
      if ((counts[base[i]] ?? 0) > 1 &&
          conds[i].type == 'sensor' &&
          (conds[i].sensorId ?? '').isNotEmpty)
        '${base[i]} en ${_deviceName(devices, conds[i].sensorId)}'
      else
        base[i],
  ];
}

/// El árbol booleano de un `if` como cláusula: "está oscuro y es entre las
/// 20:00 y las 07:00", "hay movimiento en A o hay movimiento en B",
/// "no se cumple que …".
String condClause(FlowCond c, DevicesService devices) {
  if (c.isAnd || c.isOr) {
    final leaves = c.children.every((x) => x.isLeaf)
        ? disambiguatedConditions(
            [for (final x in c.children) x.leaf],
            devices,
            (x) => conditionClause(x, devices),
          )
        : [for (final x in c.children) condClause(x, devices)];
    return leaves.join(c.isAnd ? ' y ' : ' o ');
  }
  if (c.isNot) {
    return 'no se cumple que ${condClause(c.children.first, devices)}';
  }
  return conditionClause(c.leaf, devices);
}

/// "si está oscuro", "con alarma armada", primera + "+N" si hay más.
String conditionsPhrase(Automation a, DevicesService devices) {
  final parts = <String>[
    for (final c in a.effectiveConditions) conditionPhrase(c, devices),
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

/// El disparador como cláusula después de "Cuando": "haya movimiento en
/// Pasillo", "sean las 19:00 (L–V)", "toques el botón 1 de Dial", "termine
/// una llamada de un contacto", "la ejecutes manualmente".
String triggerClause(Automation a, DevicesService devices) {
  final t = a.trigger;
  switch (t.type) {
    case 'schedule':
      if (t.scheduleMode == 'interval') {
        var s = 'pasen ${t.interval} min';
        if (t.fromTime != null && t.toTime != null) {
          s += ' entre las ${t.fromTime} y las ${t.toTime}';
        }
        return s;
      }
      var s = 'sean las ${t.time ?? '—'}';
      final d = daysCompact(t.days);
      if (d.isNotEmpty) s += ' ($d)';
      return s;
    case 'sensor':
      if (t.sensorTriggers.isEmpty) return 'se dispare el sensor';
      final first = t.sensorTriggers.first;
      final name = _deviceName(devices, first.sensorId);
      String s;
      switch (first.sensorField) {
        case 'motion':
          s = first.sensorValue == true
              ? 'haya movimiento en $name'
              : 'deje de haber movimiento en $name';
        case 'contact':
          s = first.sensorValue == true ? 'se abra $name' : 'se cierre $name';
        case 'lastKey':
          // lastKey es el TIPO de pulsación (0 click, 1 doble, 2 mantenido);
          // el botón físico lo dice sensorOutlet (0-based, se muestra +1).
          final verb = switch (int.tryParse('${first.sensorValue}')) {
            1 => 'toques dos veces',
            2 => 'mantengas apretado',
            _ => 'toques',
          };
          final outlet = first.sensorOutlet;
          s = outlet != null
              ? '$verb el botón ${outlet + 1} de $name'
              : '$verb $name';
        case 'temperature':
          s = (first.sensorOperator == 'lt' || first.sensorOperator == 'lte')
              ? '$name baje de ${_num(first.sensorValue)}°'
              : '$name supere los ${_num(first.sensorValue)}°';
        case 'humidity':
          s = (first.sensorOperator == 'lt' || first.sensorOperator == 'lte')
              ? 'la humedad de $name baje de ${_num(first.sensorValue)}%'
              : 'la humedad de $name supere el ${_num(first.sensorValue)}%';
        case 'lux':
          s = (first.sensorOperator == 'lt' || first.sensorOperator == 'lte')
              ? 'la luz de $name baje de ${_num(first.sensorValue)} lx'
              : 'la luz de $name supere los ${_num(first.sensorValue)} lx';
        case 'lockActor':
          s = 'entre ${first.sensorValue}';
        case 'lockEventKind':
          s = first.sensorValue == 'doorbell'
              ? 'toquen el timbre'
              : 'alguien destrabe $name';
        case 'vacuumState':
          s = switch (first.sensorValue) {
            'cleaning' => '$name empiece a limpiar',
            'docked' => '$name vuelva a la base',
            'error' => '$name entre en error',
            _ => 'cambie $name',
          };
        default:
          s = 'cambie $name';
      }
      final more = t.sensorTriggers.length - 1;
      if (more > 0) {
        final noun = more == 1 ? 'sensor más' : 'sensores más';
        s += t.sensorTriggersMode == 'all' ? ' (y $more $noun)' : ' (o $more $noun)';
      }
      return s;
    case 'incomingCall':
      return 'entre una llamada${_callFromSuffix(t)}';
    case 'callStarted':
      return 'empiece una llamada${_callFromSuffix(t)}';
    case 'callEnded':
      return 'termine una llamada${_callFromSuffix(t)}';
    case 'calendar':
      return t.raw['calendarEdge'] == 'end'
          ? 'termine un evento del calendario'
          : 'empiece un evento del calendario';
    default:
      return 'la ejecutes manualmente';
  }
}

/// "5 min", "30 s", "1 h", "1 h 30 min", "2 min 30 s".
String durationLabel(int seconds) {
  if (seconds < 60) return '$seconds s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final parts = <String>[
    if (h > 0) '$h h',
    if (m > 0) '$m min',
    if (s > 0) '$s s',
  ];
  return parts.join(' ');
}

/// "esperar 5 min".
String waitPhrase(int seconds) => 'esperar ${durationLabel(seconds)}';

/// Las acciones como lista hablada: "prender Living al 40%", "prender Living
/// y apagar la tele", "a, b y c", ">3 → N acciones".
String _spokenActions(List<AutomationAction> acts, DevicesService devices) {
  if (acts.isEmpty) return '(sin acciones todavía)';
  final phrases = [
    for (final a in acts) _lcFirst(actionPhrase(a, devices)),
  ];
  if (phrases.length == 1) return phrases.first;
  if (phrases.length > 3) return '${phrases.length} acciones';
  return '${phrases.sublist(0, phrases.length - 1).join(', ')} y ${phrases.last}';
}

/// La oración completa del wizard, con lo que hay en sus cuatro pantallas:
/// "Cuando haya movimiento en Living, si está oscuro, prender Living al 40%,
/// esperar 5 min y apagar Living."
String wizardSummary(
  Automation a,
  DevicesService devices, {
  required List<AutomationCondition> conditions,
  required List<AutomationAction> actions,
  int? waitSeconds,
  List<AutomationAction> afterActions = const [],
}) {
  final buf = StringBuffer('Cuando ${triggerClause(a, devices)}');
  final conds = disambiguatedConditions(
      conditions, devices, (c) => conditionClause(c, devices));
  switch (a.trigger.alarmCondition) {
    case 'armed':
      conds.add('la alarma está armada');
    case 'disarmed':
      conds.add('la alarma está desarmada');
  }
  if (conds.isNotEmpty) buf.write(', si ${conds.join(' y ')}');
  buf.write(', ${_spokenActions(actions, devices)}');
  if (waitSeconds != null && afterActions.isNotEmpty) {
    buf.write(', ${waitPhrase(waitSeconds)} y '
        '${_spokenActions(afterActions, devices)}');
  }
  buf.write('.');
  return buf.toString();
}

/// La misma oración sobre lo que la automatización TIENE. Si el árbol entra
/// en el molde del wizard sale entera (con la espera); si no, se narra el
/// camino feliz y se avisa que hay más.
String flowSummary(Automation a, DevicesService devices) {
  switch (a.source) {
    case 'scene':
    case 'hueScene':
      return 'Cuando ${triggerClause(a, devices)}, activar la escena '
          '${_sceneName(devices, a)}.';
    case 'group':
      return 'Cuando ${triggerClause(a, devices)}, '
          '${a.sourceAction == 'off' ? 'apagar' : 'prender'} el grupo '
          '${_groupName(devices, a.sourceId)}.';
    case 'hueRoom':
      return 'Cuando ${triggerClause(a, devices)}, '
          '${a.sourceAction == 'off' ? 'apagar' : 'prender'} el room '
          '${_hueRoomName(devices, a.sourceId)}.';
  }
  final shape = a.raw['flow'] is List ? wizardShapeOf(a.flow) : null;
  if (shape != null && a.hasOwnFlow) {
    return wizardSummary(
      a,
      devices,
      conditions: shape.conditions,
      actions: [
        for (final x in shape.actions)
          AutomationAction.fromJson(flowActionToLegacy(x)),
      ],
      waitSeconds: shape.waitSeconds,
      afterActions: [
        for (final x in shape.afterActions)
          AutomationAction.fromJson(flowActionToLegacy(x)),
      ],
    );
  }
  final summary = wizardSummary(
    a,
    devices,
    conditions: a.effectiveConditions,
    actions: a.effectiveActions,
  );
  if (a.hasOwnFlow && shape == null) {
    return '$summary Y más: este flujo tiene ramas o esperas que se ven '
        'en el Dashboard.';
  }
  return summary;
}

/// Alias histórico del banner del editor por bloques.
String editorSummary(Automation a, DevicesService devices) =>
    flowSummary(a, devices);

// ── Narración de un árbol (solo lectura) ─────────────────────────────────────

enum FlowLineKind { condition, branch, action, wait, call, stop, unknown }

/// Cómo se llama cada salida del «Llamar» en la narración (CCE#81). «Si no
/// atienden» cubre también la que el otro lado rechazó: en una saliente el
/// módem no distingue una de otra, y el motor las manda a la misma rama.
const Map<String, String> kCallBranchPhrase = {
  'onAnswered': 'Si atienden',
  'onMissed': 'Si no atienden',
  'onRejected': 'Si la rechazan',
  'onFailed': 'Si no se pudo llamar',
  'onTimeout': 'Si vence',
};

/// A quién llama un `call`: la app no tiene la libreta a mano para el nombre
/// del contacto, igual que en los disparadores de llamada.
String callTargetPhrase(FlowCallStep s) {
  final number = s.number;
  if (number != null && number.isNotEmpty) return 'al $number';
  return s.contactId != null ? 'a un contacto' : 'a nadie todavía';
}

/// Una línea de la narración: qué es, a qué profundidad y qué dice.
class FlowLine {
  const FlowLine(this.kind, this.text, {this.depth = 0});

  final FlowLineKind kind;
  final String text;
  final int depth;
}

/// El árbol entero, paso por paso, con la sangría de cada rama. Es lo que la
/// app muestra de un flujo que NO entra en el molde: se lee todo, no se toca.
List<FlowLine> flowNarration(List<FlowStep> flow, DevicesService devices) {
  final out = <FlowLine>[];
  void walk(List<FlowStep> steps, int depth) {
    for (final s in steps) {
      switch (s) {
        case FlowDoStep():
          for (final a in s.actions) {
            final legacy = AutomationAction.fromJson(flowActionToLegacy(a));
            out.add(FlowLine(FlowLineKind.action,
                actionPhrase(legacy, devices),
                depth: depth));
          }
        case FlowIfStep():
          out.add(FlowLine(FlowLineKind.condition,
              'Si ${condClause(s.cond, devices)}',
              depth: depth));
          walk(s.then, depth + 1);
          if (s.hasElse) {
            out.add(FlowLine(FlowLineKind.branch, 'Si no', depth: depth));
            walk(s.otherwise!, depth + 1);
          }
        case FlowWaitStep():
          out.add(FlowLine(FlowLineKind.wait,
              _ucFirst(waitPhrase(s.seconds?.round() ?? 0)),
              depth: depth));
        case FlowWaitForStep():
          final timeout = s.timeoutSeconds?.round();
          out.add(FlowLine(
            FlowLineKind.wait,
            'Esperar hasta que ${condClause(s.cond, devices)}'
            '${timeout != null ? ' (máximo ${durationLabel(timeout)})' : ''}',
            depth: depth,
          ));
          final onTimeout = s.onTimeout;
          if (onTimeout != null && onTimeout.isNotEmpty) {
            out.add(FlowLine(
              FlowLineKind.branch,
              timeout != null
                  ? 'Si no pasa en ${durationLabel(timeout)}'
                  : 'Si no pasa',
              depth: depth,
            ));
            walk(onTimeout, depth + 1);
          }
        case FlowCallStep():
          // CCE#81 — «Llamar al …, esperar a que termine (máximo N)» y una
          // rama por salida presente: las ausentes caen en el paso siguiente
          // y no se cuentan.
          final timeout = s.timeoutSeconds?.round();
          out.add(FlowLine(
            FlowLineKind.call,
            'Llamar ${callTargetPhrase(s)} y esperar a que termine'
            '${timeout != null ? ' (máximo ${durationLabel(timeout)})' : ''}',
            depth: depth,
          ));
          for (final kind in kCallBranches) {
            final steps = s.branches[kind];
            if (steps == null || steps.isEmpty) continue;
            var title = kCallBranchPhrase[kind] ?? kind;
            if (kind == 'onTimeout' && timeout != null) {
              title = 'Si no termina en ${durationLabel(timeout)}';
            }
            out.add(FlowLine(FlowLineKind.branch, title, depth: depth));
            walk(steps, depth + 1);
          }
        case FlowStopStep():
          out.add(FlowLine(FlowLineKind.stop, 'Fin', depth: depth));
        case FlowUnknownStep():
          out.add(FlowLine(FlowLineKind.unknown,
              'Paso desconocido (${s.type.isEmpty ? '?' : s.type})',
              depth: depth));
      }
    }
  }

  walk(flow, 0);
  return out;
}
