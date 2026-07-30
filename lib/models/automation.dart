import 'dart:convert';
import 'dart:math' as math;

/// Modelo de automatización con round-trip SIN PÉRDIDA a dos niveles:
/// el objeto raíz y cada acción guardan su JSON original ([raw]) y las
/// ediciones se aplican como overlay sobre ese mapa — campos que la UI no
/// modela (mode, planId, futuros) sobreviven byte a byte al PUT.
///
/// Shape espejado del backend (`CceConfig['automations']`, ver informe
/// automations-api): el server NO valida el body, así que TODA la
/// validación vive en el cliente ([validationError]).

Map<String, dynamic> _jsonCopy(Map source) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

/// Genera un id client-side con la convención del dashboard:
/// "auto_" + random base36.
String newAutomationId() {
  final rnd = math.Random();
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  final buf = StringBuffer('auto_');
  buf.write(DateTime.now().millisecondsSinceEpoch.toRadixString(36));
  for (var i = 0; i < 6; i++) {
    buf.write(chars[rnd.nextInt(chars.length)]);
  }
  return buf.toString();
}

class Automation {
  Automation.fromJson(Map<String, dynamic> json)
      : raw = _jsonCopy(json),
        _original = _jsonCopy(json),
        trigger = AutomationTrigger.fromJson(
          json['trigger'] is Map
              ? Map<String, dynamic>.from(json['trigger'] as Map)
              : const <String, dynamic>{},
        ),
        actions = json['actions'] is List
            ? [
                for (final a in json['actions'] as List)
                  if (a is Map)
                    AutomationAction.fromJson(Map<String, dynamic>.from(a)),
              ]
            : <AutomationAction>[];

  /// Automation nueva con los defaults requeridos por el server
  /// (id client-side + `mode: 'toggle'`).
  factory Automation.blank() => Automation.fromJson({
        'id': newAutomationId(),
        'name': '',
        'icon': '⚡',
        'enabled': true,
        'source': 'custom',
        'mode': 'toggle',
        'trigger': {'type': 'sensor'},
        'actions': <Map<String, dynamic>>[],
      });

  /// Overlay editable: las ediciones escriben acá; los campos no modelados
  /// quedan intactos.
  final Map<String, dynamic> raw;

  /// Snapshot INMUTABLE del JSON con el que se construyó este objeto.
  /// Es la base de la detección de conflictos (deep-equal contra el GET
  /// fresco del server al guardar).
  final Map<String, dynamic> _original;
  Map<String, dynamic> get original => _original;

  AutomationTrigger trigger;
  List<AutomationAction> actions;

  String get id => (raw['id'] ?? '').toString();
  String get name => (raw['name'] ?? '').toString();
  set name(String v) => raw['name'] = v;
  String get icon => (raw['icon'] ?? '').toString();
  set icon(String v) => raw['icon'] = v;
  bool get enabled => raw['enabled'] == true;
  set enabled(bool v) => raw['enabled'] = v;

  /// 'scene' | 'group' | 'custom' | 'hueScene' (default efectivo 'custom').
  String get source {
    final s = raw['source'];
    return (s is String && s.isNotEmpty) ? s : 'custom';
  }

  set source(String v) => raw['source'] = v;

  String? get sourceId {
    final s = raw['sourceId'];
    return s is String && s.isNotEmpty ? s : null;
  }

  set sourceId(String? v) {
    if (v == null) {
      raw.remove('sourceId');
    } else {
      raw['sourceId'] = v;
    }
  }

  /// Solo source 'group': 'on' | 'off' (default 'on').
  String get sourceAction => (raw['sourceAction'] as String?) ?? 'on';
  set sourceAction(String v) => raw['sourceAction'] = v;

  /// Solo source 'hueScene': smart scene del bridge.
  bool get sourceSmart => raw['sourceSmart'] == true;
  set sourceSmart(bool v) => raw['sourceSmart'] = v;

  String? get planId => raw['planId'] as String?;

  /// Serializa: raw + overrides. JAMÁS strippea campos desconocidos.
  Map<String, dynamic> toJson() {
    final out = _jsonCopy(raw);
    out['trigger'] = trigger.toJson();
    out['actions'] = [for (final a in actions) a.toJson()];
    // El tipo del server lo declara requerido ('toggle'|'full').
    out['mode'] ??= 'toggle';
    return out;
  }

  /// Copia editable: el snapshot [original] de la copia es el estado actual
  /// del item (lo que el editor abrió), base del chequeo de conflicto.
  Automation copyForEdit() => Automation.fromJson(raw);

  /// Validación dura client-side (el server acepta cualquier cosa).
  /// Devuelve el motivo visible en español, o null si se puede guardar.
  String? validationError() {
    if (name.trim().isEmpty) return 'Poné un nombre a la automatización';
    switch (trigger.type) {
      case 'sensor':
        if (trigger.sensorTriggers.isEmpty) {
          return 'Elegí al menos un sensor en CUÁNDO';
        }
        if (trigger.sensorTriggers.any((t) => t.sensorId.isEmpty)) {
          return 'Hay un sensor sin configurar en CUÁNDO';
        }
      case 'schedule':
        if (trigger.scheduleMode == 'interval') {
          if (trigger.interval < 1) {
            return 'El intervalo debe ser de al menos 1 minuto';
          }
        } else {
          final t = trigger.time;
          if (t == null || !RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
            return 'Elegí una hora válida en CUÁNDO';
          }
        }
    }
    if (source == 'custom') {
      if (actions.isEmpty) return 'Agregá al menos una acción en ENTONCES';
    } else if (sourceId == null) {
      return 'Elegí una escena o grupo en ENTONCES';
    }
    return null;
  }
}

/// Una entrada de `trigger.sensorTriggers[]`.
class SensorTrigger {
  SensorTrigger({
    required this.sensorId,
    required this.sensorField,
    required this.sensorValue,
    this.sensorOperator,
    this.sensorOutlet,
    this.sensorBindingId,
  });

  factory SensorTrigger.fromJson(Map<String, dynamic> json) => SensorTrigger(
        sensorId: (json['sensorId'] ?? '').toString(),
        sensorField: (json['sensorField'] ?? '').toString(),
        sensorValue: json['sensorValue'],
        sensorOperator: json['sensorOperator'] as String?,
        sensorOutlet: (json['sensorOutlet'] as num?)?.toInt(),
        sensorBindingId: json['sensorBindingId'] as String?,
      );

  String sensorId; // ID canónico dev_*
  String sensorField; // 'motion'|'contact'|'lastKey'|'temperature'|'humidity'
  dynamic sensorValue; // bool | num | String
  String? sensorOperator; // 'eq'|'gt'|'lt'|'gte'|'lte' (ausente = igualdad)
  int? sensorOutlet; // botones multi-outlet
  String? sensorBindingId;

  Map<String, dynamic> toJson() => {
        'sensorId': sensorId,
        'sensorField': sensorField,
        'sensorValue': sensorValue,
        'sensorOperator': ?sensorOperator,
        'sensorOutlet': ?sensorOutlet,
        'sensorBindingId': ?sensorBindingId,
      };
}

/// Condición adicional (AND): variante sensor (`field`/`value` — OJO, NO
/// `sensorField`/`sensorValue`) o `timeWindow`. Conserva su raw.
class AutomationCondition {
  AutomationCondition.fromJson(Map<String, dynamic> json)
      : raw = _jsonCopy(json);

  AutomationCondition.sensor({
    required String sensorId,
    required String field,
    required dynamic value,
    String? operator,
  }) : raw = {
          'type': 'sensor',
          'sensorId': sensorId,
          'field': field,
          'value': value,
          'operator': ?operator,
        };

  AutomationCondition.timeWindow({
    required String fromTime,
    required String toTime,
  }) : raw = {
          'type': 'timeWindow',
          'fromTime': fromTime,
          'toTime': toTime,
        };

  final Map<String, dynamic> raw;

  /// 'type' ausente = sensor.
  String get type => (raw['type'] as String?) ?? 'sensor';
  String? get sensorId => raw['sensorId'] as String?;
  String? get field => raw['field'] as String?;
  dynamic get value => raw['value'];
  String? get operator => raw['operator'] as String?;
  String? get fromTime => raw['fromTime'] as String?;
  String? get toTime => raw['toTime'] as String?;

  bool get isDarkPreset => type == 'sensor' && field == 'brightness';

  Map<String, dynamic> toJson() => _jsonCopy(raw);
}

/// Tipo de acción para la UI (color del círculo, editor a abrir).
enum AutomationActionKind {
  light,
  group,
  hueRoom,
  scene,
  hueScene,
  device,
  notification,
  alarm,
  jbl,
  advanced,
}

class AutomationAction {
  AutomationAction.fromJson(Map<String, dynamic> json)
      : raw = _jsonCopy(json),
        edited = false;

  /// Acción nueva creada por el editor (ya nace "editada").
  AutomationAction.blank(Map<String, dynamic> initial)
      : raw = _jsonCopy(initial),
        edited = true;

  factory AutomationAction.light(String lightId) =>
      AutomationAction.blank({'lightId': lightId, 'on': true, 'bri': 254});

  factory AutomationAction.group(String groupId) => AutomationAction.blank({
        'lightId': '__group__$groupId',
        'on': 'group',
        'groupId': groupId,
        'groupAction': 'on',
      });

  /// Room de Hue entero (grouped_light) como target de acción — contrato del
  /// backend: on:'hueRoom' + hueRoomId + hueRoomAction ('on'|'off'|'toggle').
  factory AutomationAction.hueRoom(String hueRoomId) => AutomationAction.blank({
        'lightId': '__hueRoom__$hueRoomId',
        'on': 'hueRoom',
        'hueRoomId': hueRoomId,
        'hueRoomAction': 'on',
      });

  /// Escena CCE como acción del modo Personalizado — contrato del backend:
  /// on:'scene' + sceneId. El lightId sentinel es solo local (la API lo
  /// ignora): distingue la fila en la UI sin campo extra.
  factory AutomationAction.scene(String sceneId) => AutomationAction.blank({
        'lightId': '__scene__$sceneId',
        'on': 'scene',
        'sceneId': sceneId,
      });

  /// Escena Hue como acción — contrato: on:'hueScene' + hueSceneId +
  /// sceneSmart (recall dinámico vs estático; sale del flag real de la
  /// escena en la lista del bridge, no lo elige el usuario).
  factory AutomationAction.hueScene(
    String hueSceneId, {
    bool sceneSmart = false,
  }) =>
      AutomationAction.blank({
        'lightId': '__hueScene__$hueSceneId',
        'on': 'hueScene',
        'hueSceneId': hueSceneId,
        'sceneSmart': sceneSmart,
      });

  /// Acción por CAPABILITY sobre cualquier device: POST /actions/:verb con args
  /// (contrato del backend: on:'device' + deviceId + verb + args). Cubre
  /// media/tv/vacuum/sound_mode/etc. El lightId sentinel permite N verbos por
  /// device sin colisión.
  factory AutomationAction.device(
    String deviceId,
    String verb, [
    Map<String, dynamic> args = const {},
  ]) =>
      AutomationAction.blank({
        'lightId': '__dev__${deviceId}__$verb',
        'on': 'device',
        'deviceId': deviceId,
        'verb': verb,
        if (args.isNotEmpty) 'args': args,
      });

  factory AutomationAction.notification() => AutomationAction.blank({
        'lightId': '__notification__',
        'on': 'notification',
        'notificationMessage': 'Alerta de automatización',
        'notificationSound': 'doorbell',
        'notificationType': 'info',
      });

  factory AutomationAction.alarm() => AutomationAction.blank({
        'lightId': '__alarm__',
        'on': 'alarm',
        'alarmAction': 'arm',
      });

  factory AutomationAction.jbl() => AutomationAction.blank({
        'lightId': '__jbl__',
        'on': 'jbl',
        'jblAction': 'on',
        'jblOnMode': 'resume',
      });

  /// JSON propio de la acción; las acciones NO tocadas por el editor
  /// re-serializan este mapa intacto.
  final Map<String, dynamic> raw;

  /// true solo si el editor tocó ESTA fila.
  bool edited;

  String get lightId => (raw['lightId'] ?? '').toString();
  dynamic get on => raw['on'];

  int? get bri => (raw['bri'] as num?)?.toInt();
  int? get hue => (raw['hue'] as num?)?.toInt();
  int? get sat => (raw['sat'] as num?)?.toInt();
  int? get ct => (raw['ct'] as num?)?.toInt();

  /// Solo con 'bri_up'/'bri_down' (default 25 si ausente).
  int get briDelta => (raw['briDelta'] as num?)?.toInt() ?? 25;

  String? get groupId {
    final g = raw['groupId'];
    if (g is String && g.isNotEmpty) return g;
    if (lightId.startsWith('__group__')) {
      return lightId.substring('__group__'.length);
    }
    return null;
  }

  String get groupAction => (raw['groupAction'] as String?) ?? 'on';

  String? get hueRoomId {
    final r = raw['hueRoomId'];
    if (r is String && r.isNotEmpty) return r;
    if (lightId.startsWith('__hueRoom__')) {
      final id = lightId.substring('__hueRoom__'.length);
      return id.isEmpty ? null : id;
    }
    return null;
  }

  String get hueRoomAction => (raw['hueRoomAction'] as String?) ?? 'on';

  /// Acción escena CCE (on:'scene'): id con fallback al sentinel, espejo
  /// de [groupId]/[hueRoomId].
  String? get sceneId {
    final s = raw['sceneId'];
    if (s is String && s.isNotEmpty) return s;
    if (lightId.startsWith('__scene__')) {
      final id = lightId.substring('__scene__'.length);
      return id.isEmpty ? null : id;
    }
    return null;
  }

  /// Acción escena Hue (on:'hueScene').
  String? get hueSceneId {
    final s = raw['hueSceneId'];
    if (s is String && s.isNotEmpty) return s;
    if (lightId.startsWith('__hueScene__')) {
      final id = lightId.substring('__hueScene__'.length);
      return id.isEmpty ? null : id;
    }
    return null;
  }

  /// Smart scene del bridge (solo on:'hueScene').
  bool get sceneSmart => raw['sceneSmart'] == true;

  String get notificationMessage =>
      (raw['notificationMessage'] as String?) ?? 'Alerta de automatización';
  String get notificationSound =>
      (raw['notificationSound'] as String?) ?? 'alarm';

  /// 'critical' | 'alert' | 'info' — migra el deprecated
  /// notificationCritical (false ⇒ 'info', si no ⇒ 'critical').
  String get notificationType {
    final t = raw['notificationType'];
    if (t is String && t.isNotEmpty) return t;
    if (raw.containsKey('notificationCritical')) {
      return raw['notificationCritical'] == false ? 'info' : 'critical';
    }
    return 'critical';
  }

  String get alarmAction => (raw['alarmAction'] as String?) ?? 'toggle';

  /// Acción por capability (on:'device').
  String get deviceId => (raw['deviceId'] ?? '').toString();
  String get verb => (raw['verb'] ?? '').toString();
  Map<String, dynamic> get args =>
      raw['args'] is Map ? Map<String, dynamic>.from(raw['args'] as Map) : {};

  String get jblAction => (raw['jblAction'] as String?) ?? 'on';
  String? get jblOnMode => raw['jblOnMode'] as String?;
  String? get jblRadioName => raw['jblRadioName'] as String?;
  /// Volumen de arranque (escala display 0..31). null = no fijar volumen.
  int? get jblVolume => (raw['jblVolume'] as num?)?.toInt();
  /// Iniciar en modo noche al prender. false = no tocar.
  bool get jblNightMode => raw['jblNightMode'] == true;

  AutomationActionKind get kind {
    if (lightId == '__notification__' || on == 'notification') {
      return AutomationActionKind.notification;
    }
    if (lightId == '__alarm__' || on == 'alarm') {
      return AutomationActionKind.alarm;
    }
    if (lightId == '__jbl__' || on == 'jbl') return AutomationActionKind.jbl;
    if (on == 'device') return AutomationActionKind.device;
    if (lightId.startsWith('__hueRoom__') || on == 'hueRoom') {
      return AutomationActionKind.hueRoom;
    }
    // hueScene ANTES que scene: los sentinels no colisionan, pero el orden
    // deja explícito que el chequeo más específico gana.
    if (lightId.startsWith('__hueScene__') || on == 'hueScene') {
      return AutomationActionKind.hueScene;
    }
    if (lightId.startsWith('__scene__') || on == 'scene') {
      return AutomationActionKind.scene;
    }
    if (lightId.startsWith('__group__') || on == 'group') {
      return AutomationActionKind.group;
    }
    // Acción de luz: la UI modela on bool y 'toggle'; verbos bri_up/bri_down
    // u otros valores quedan como "Acción avanzada" (solo reorden/borrar).
    if (on is bool || on == 'toggle') return AutomationActionKind.light;
    return AutomationActionKind.advanced;
  }

  // === Mutadores del editor: actualizan SOLO los campos modelados, los
  // desconocidos del raw sobreviven. ====================================

  void _setOrRemove(String key, Object? value) {
    if (value == null) {
      raw.remove(key);
    } else {
      raw[key] = value;
    }
  }

  void updateLight({
    required String lightId,
    required dynamic on,
    int? bri,
    int? hue,
    int? sat,
    int? ct,
  }) {
    raw['lightId'] = lightId;
    raw['on'] = on;
    _setOrRemove('bri', bri);
    _setOrRemove('hue', hue);
    _setOrRemove('sat', sat);
    _setOrRemove('ct', ct);
    edited = true;
  }

  void updateGroup({required String groupId, required String groupAction}) {
    raw['lightId'] = '__group__$groupId';
    raw['on'] = 'group';
    raw['groupId'] = groupId;
    raw['groupAction'] = groupAction;
    edited = true;
  }

  void updateHueRoom({
    required String hueRoomId,
    required String hueRoomAction,
  }) {
    raw['lightId'] = '__hueRoom__$hueRoomId';
    raw['on'] = 'hueRoom';
    raw['hueRoomId'] = hueRoomId;
    raw['hueRoomAction'] = hueRoomAction;
    edited = true;
  }

  void updateScene({required String sceneId}) {
    raw['lightId'] = '__scene__$sceneId';
    raw['on'] = 'scene';
    raw['sceneId'] = sceneId;
    // El editor permite cambiar Hue→CCE en la misma fila: limpiar las claves
    // del otro contrato para emitir el JSON exacto que espera la API.
    raw.remove('hueSceneId');
    raw.remove('sceneSmart');
    edited = true;
  }

  void updateHueScene({
    required String hueSceneId,
    required bool sceneSmart,
  }) {
    raw['lightId'] = '__hueScene__$hueSceneId';
    raw['on'] = 'hueScene';
    raw['hueSceneId'] = hueSceneId;
    raw['sceneSmart'] = sceneSmart;
    // Cambio CCE→Hue en la misma fila: ver updateScene.
    raw.remove('sceneId');
    edited = true;
  }

  void updateDevice({
    required String deviceId,
    required String verb,
    Map<String, dynamic> args = const {},
  }) {
    raw['deviceId'] = deviceId;
    raw['verb'] = verb;
    raw['on'] = 'device';
    raw['lightId'] = '__dev__${deviceId}__$verb';
    _setOrRemove('args', args.isEmpty ? null : args);
    edited = true;
  }

  void updateNotification({
    required String message,
    required String sound,
    required String type,
  }) {
    raw['lightId'] = '__notification__';
    raw['on'] = 'notification';
    raw['notificationMessage'] = message;
    raw['notificationSound'] = sound;
    raw['notificationType'] = type;
    raw.remove('notificationCritical'); // migrado a notificationType
    edited = true;
  }

  void updateAlarm(String alarmAction) {
    raw['lightId'] = '__alarm__';
    raw['on'] = 'alarm';
    raw['alarmAction'] = alarmAction;
    edited = true;
  }

  void updateJbl({
    required String action,
    String? onMode,
    String? radioName,
    int? volume,
    bool nightMode = false,
  }) {
    raw['lightId'] = '__jbl__';
    raw['on'] = 'jbl';
    raw['jblAction'] = action;
    _setOrRemove('jblOnMode', action == 'on' ? onMode : null);
    _setOrRemove(
      'jblRadioName',
      action == 'on' && onMode == 'radio' ? radioName : null,
    );
    // Volumen de arranque: solo con 'on'; null lo remueve (no fijar).
    _setOrRemove('jblVolume', action == 'on' ? volume : null);
    // Modo noche: solo con 'on' y true; false/off lo remueve (no tocar).
    _setOrRemove('jblNightMode', action == 'on' && nightMode ? true : null);
    edited = true;
  }

  /// edited==false → raw INTACTO byte a byte; las ediciones ya viven en raw.
  Map<String, dynamic> toJson() => _jsonCopy(raw);
}

class AutomationTrigger {
  AutomationTrigger.fromJson(Map<String, dynamic> json)
      : raw = _jsonCopy(json) {
    final rawTriggers = raw['sensorTriggers'];
    sensorTriggers = rawTriggers is List
        ? [
            for (final t in rawTriggers)
              if (t is Map)
                SensorTrigger.fromJson(Map<String, dynamic>.from(t)),
          ]
        : <SensorTrigger>[];
    // Config vieja: solo escalares legacy → sintetizar la entrada [0].
    if (sensorTriggers.isEmpty &&
        type == 'sensor' &&
        raw['sensorId'] is String &&
        (raw['sensorId'] as String).isNotEmpty) {
      sensorTriggers.add(SensorTrigger.fromJson(raw));
    }
    final rawConds = raw['conditions'];
    conditions = rawConds is List
        ? [
            for (final c in rawConds)
              if (c is Map)
                AutomationCondition.fromJson(Map<String, dynamic>.from(c)),
          ]
        : <AutomationCondition>[];
  }

  final Map<String, dynamic> raw;

  late List<SensorTrigger> sensorTriggers;
  late List<AutomationCondition> conditions;

  /// 'manual' | 'schedule' | 'sensor'.
  String get type => (raw['type'] as String?) ?? 'manual';
  set type(String v) => raw['type'] = v;

  // --- schedule ---
  String get scheduleMode => (raw['scheduleMode'] as String?) ?? 'fixed';
  set scheduleMode(String v) => raw['scheduleMode'] = v;

  String? get time => raw['time'] as String?;
  set time(String? v) {
    if (v == null) {
      raw.remove('time');
    } else {
      raw['time'] = v;
    }
  }

  /// 0=domingo..6=sábado. Vacío = todos los días.
  List<int> get days {
    final d = raw['days'];
    if (d is! List) return const [];
    return [for (final v in d) if (v is num) v.toInt()];
  }

  set days(List<int> v) => raw['days'] = v;

  int get interval => (raw['interval'] as num?)?.toInt() ?? 15;
  set interval(int v) => raw['interval'] = v;

  String? get fromTime => raw['fromTime'] as String?;
  set fromTime(String? v) {
    if (v == null) {
      raw.remove('fromTime');
    } else {
      raw['fromTime'] = v;
    }
  }

  String? get toTime => raw['toTime'] as String?;
  set toTime(String? v) {
    if (v == null) {
      raw.remove('toTime');
    } else {
      raw['toTime'] = v;
    }
  }

  // --- sensor ---
  /// 'any' (OR, default) | 'all'.
  String get sensorTriggersMode =>
      (raw['sensorTriggersMode'] as String?) ?? 'any';
  set sensorTriggersMode(String v) => raw['sensorTriggersMode'] = v;

  /// Segundos de espera antes de ejecutar (0 = inmediato).
  int get sensorDelay => (raw['sensorDelay'] as num?)?.toInt() ?? 0;
  set sensorDelay(int v) => raw['sensorDelay'] = v;

  /// 'any' | 'armed' | 'disarmed' — migra el deprecated requireAlarmArmed.
  String get alarmCondition {
    final c = raw['alarmCondition'];
    if (c is String && c.isNotEmpty) return c;
    return raw['requireAlarmArmed'] == true ? 'armed' : 'any';
  }

  set alarmCondition(String v) {
    raw['alarmCondition'] = v;
    raw.remove('requireAlarmArmed');
  }

  static const _scheduleKeys = [
    'scheduleMode',
    'time',
    'days',
    'interval',
    'fromTime',
    'toTime',
  ];
  static const _sensorKeys = [
    'sensorTriggers',
    'sensorTriggersMode',
    'sensorId',
    'sensorBindingId',
    'sensorField',
    'sensorValue',
    'sensorOperator',
    'sensorOutlet',
    'sensorDelay',
  ];

  Map<String, dynamic> toJson() {
    final out = _jsonCopy(raw);
    out['type'] = type;
    out['alarmCondition'] = alarmCondition;
    out.remove('requireAlarmArmed'); // deprecated, migrado
    if (conditions.isNotEmpty) {
      out['conditions'] = [for (final c in conditions) c.toJson()];
    } else {
      out.remove('conditions');
    }
    switch (type) {
      case 'sensor':
        for (final k in _scheduleKeys) {
          out.remove(k);
        }
        out['sensorTriggers'] = [for (final t in sensorTriggers) t.toJson()];
        out['sensorTriggersMode'] = sensorTriggersMode;
        out['sensorDelay'] = sensorDelay;
        // Espejar [0] en los escalares legacy (compat dashboard/engine viejo).
        if (sensorTriggers.isNotEmpty) {
          final first = sensorTriggers.first;
          out['sensorId'] = first.sensorId;
          out['sensorField'] = first.sensorField;
          out['sensorValue'] = first.sensorValue;
          if (first.sensorOperator != null) {
            out['sensorOperator'] = first.sensorOperator;
          } else {
            out.remove('sensorOperator');
          }
          if (first.sensorOutlet != null) {
            out['sensorOutlet'] = first.sensorOutlet;
          } else {
            out.remove('sensorOutlet');
          }
          if (first.sensorBindingId != null) {
            out['sensorBindingId'] = first.sensorBindingId;
          } else {
            out.remove('sensorBindingId');
          }
        }
      case 'schedule':
        for (final k in _sensorKeys) {
          out.remove(k);
        }
        out['scheduleMode'] = scheduleMode;
        if (scheduleMode == 'interval') {
          out['interval'] = interval;
          out.remove('time');
          // El server SÍ honra days en modo intervalo (daysPart del cron en
          // toIntervalCronExpression): misma regla que el modo fijo, jamás
          // strippear la restricción de días de una automation existente.
          if (days.isNotEmpty && days.length < 7) {
            out['days'] = days;
          } else {
            out.remove('days');
          }
          if (fromTime != null) {
            out['fromTime'] = fromTime;
          } else {
            out.remove('fromTime');
          }
          if (toTime != null) {
            out['toTime'] = toTime;
          } else {
            out.remove('toTime');
          }
        } else {
          if (time != null) out['time'] = time;
          if (days.isNotEmpty && days.length < 7) {
            out['days'] = days;
          } else {
            out.remove('days');
          }
          out.remove('interval');
          out.remove('fromTime');
          out.remove('toTime');
        }
      default: // manual
        for (final k in [..._scheduleKeys, ..._sensorKeys]) {
          out.remove(k);
        }
    }
    return out;
  }
}
