import 'dart:convert';

import 'package:collection/collection.dart';

import 'automation.dart';

/// El modelo de FLUJO de una automatización (EugeValeiras/CCE#64): un árbol de
/// steps `do` / `if` / `wait` / `waitFor` / `stop` que el backend prioriza
/// sobre `actions` cuando está persistido.
///
/// Espejo en Dart de `CCE-API/src/automation/flow/flow.types.ts` y de las
/// funciones puras de `flow-derive.ts` (las conversiones acción legacy ↔
/// acción de flujo y `deriveWhen`). Todo lo de acá es puro: sin Flutter, sin
/// red, testeable con `test()` a secas.
///
/// El wizard del teléfono (CCE#66) no edita cualquier árbol: sólo el MOLDE
/// «¿cuándo? → ¿solo si…? → ¿qué hace? → ¿y después?», que en el árbol es
/// `[do]`, `[do, wait, do]` o los mismos dos envueltos en un `if` sin `else`.
/// [wizardShapeOf] es la función pura que decide si un flujo entra en ese
/// molde; lo que no entra se muestra narrado y no se edita desde la app.

Map<String, dynamic> _copy(Map source) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

List<Map<String, dynamic>> _copyList(Iterable<Map> list) =>
    [for (final m in list) _copy(m)];

const DeepCollectionEquality _eq = DeepCollectionEquality();

/// Los `kind` que el executor sabe ejecutar (FLOW_ACTION_KINDS del backend).
const Set<String> kFlowActionKinds = {
  'device',
  'deviceVerb',
  'group',
  'scene',
  'hueScene',
  'hueRoom',
  'notification',
  'announce',
  'automation',
  'jbl',
  'alarm',
  'call',
};

/// Los tipos de condición HOJA. `type` ausente = 'sensor' (las
/// automatizaciones viejas no lo escribían).
const Set<String> kFlowCondLeafTypes = {
  'sensor',
  'timeWindow',
  'modulePower',
  'deviceState',
};

/// Los disparadores que el sheet CUÁNDO de la app sabe editar. Un trigger de
/// llamada o de calendario se narra, no se edita desde el teléfono.
const Set<String> kWizardTriggerTypes = {'manual', 'schedule', 'sensor'};

// ── Condiciones ──────────────────────────────────────────────────────────────

/// El árbol booleano de un `if` / `waitFor`: `{and: [...]}`, `{or: [...]}`,
/// `{not: {...}}` o una hoja [AutomationCondition].
class FlowCond {
  FlowCond(Map json) : raw = _copy(json);

  final Map<String, dynamic> raw;

  bool get isAnd => raw['and'] is List;
  bool get isOr => raw['or'] is List;
  bool get isNot => raw['not'] is Map;
  bool get isLeaf => !isAnd && !isOr && !isNot;

  List<FlowCond> get children {
    final list = isAnd ? raw['and'] : isOr ? raw['or'] : null;
    if (list is List) {
      return [for (final c in list) if (c is Map) FlowCond(c)];
    }
    if (isNot) return [FlowCond(raw['not'] as Map)];
    return const [];
  }

  /// La hoja como condición legacy (sólo tiene sentido con [isLeaf]).
  AutomationCondition get leaf => AutomationCondition.fromJson(raw);

  /// Las hojas de un AND PLANO (o de una hoja sola). null si aparece un `or`,
  /// un `not` o un `and` anidado: eso no se puede mostrar como la lista de
  /// condiciones del sheet SOLO SI, que es un AND.
  List<AutomationCondition>? andLeaves() {
    if (isLeaf) return [leaf];
    if (!isAnd) return null;
    final out = <AutomationCondition>[];
    for (final c in children) {
      if (!c.isLeaf) return null;
      out.add(c.leaf);
    }
    return out;
  }

  /// Todas las hojas, en orden, sin importar cómo estén combinadas (para las
  /// pastillas de la card y la narración de solo lectura).
  List<AutomationCondition> get leaves {
    if (isLeaf) return [leaf];
    return [for (final c in children) ...c.leaves];
  }

  Map<String, dynamic> toJson() => _copy(raw);
}

// ── Steps ────────────────────────────────────────────────────────────────────

/// Un step del árbol. Conserva su JSON ([raw]) para que lo que la app no
/// modela sobreviva intacto.
sealed class FlowStep {
  FlowStep(Map json) : raw = _copy(json);

  final Map<String, dynamic> raw;

  String get type => (raw['type'] as String?) ?? '';

  static FlowStep parse(Map json) {
    switch (json['type']) {
      case 'do':
        return FlowDoStep(json);
      case 'if':
        return FlowIfStep(json);
      case 'wait':
        return FlowWaitStep(json);
      case 'waitFor':
        return FlowWaitForStep(json);
      case 'call':
        return FlowCallStep(json);
      case 'stop':
        return FlowStopStep(json);
      default:
        return FlowUnknownStep(json);
    }
  }

  /// Parsea `flow` tal como viene del JSON. Cualquier cosa que no sea una
  /// lista de mapas se trata como "sin flujo".
  static List<FlowStep> parseList(Object? list) {
    if (list is! List) return const [];
    return [for (final s in list) if (s is Map) FlowStep.parse(s)];
  }

  Map<String, dynamic> toJson() => _copy(raw);
}

/// Las acciones corren entre sí como siempre: en paralelo, con el
/// backpressure por device del executor.
class FlowDoStep extends FlowStep {
  FlowDoStep(super.json);

  /// Las acciones de flujo (`kind` explícito, target con nombre real).
  List<Map<String, dynamic>> get actions {
    final list = raw['actions'];
    if (list is! List) return const [];
    return [for (final a in list) if (a is Map) Map<String, dynamic>.from(a)];
  }
}

class FlowIfStep extends FlowStep {
  FlowIfStep(super.json)
      : cond = FlowCond(json['cond'] is Map ? json['cond'] as Map : const {}),
        then = FlowStep.parseList(json['then']),
        otherwise =
            json.containsKey('else') ? FlowStep.parseList(json['else']) : null;

  final FlowCond cond;
  final List<FlowStep> then;

  /// La rama «si no». null = no hay; `[]` no debería venir (el backend rechaza
  /// ramas vacías) pero se tolera como "sin rama".
  final List<FlowStep>? otherwise;

  bool get hasElse => otherwise != null && otherwise!.isNotEmpty;
}

class FlowWaitStep extends FlowStep {
  FlowWaitStep(super.json);

  num? get seconds => raw['seconds'] is num ? raw['seconds'] as num : null;
}

class FlowWaitForStep extends FlowStep {
  FlowWaitForStep(super.json)
      : cond = FlowCond(json['cond'] is Map ? json['cond'] as Map : const {}),
        onTimeout = json.containsKey('onTimeout')
            ? FlowStep.parseList(json['onTimeout'])
            : null;

  final FlowCond cond;
  final List<FlowStep>? onTimeout;

  num? get timeoutSeconds =>
      raw['timeoutSeconds'] is num ? raw['timeoutSeconds'] as num : null;
}

/// Las cinco salidas del `call`, en el orden en que se narran. Espejo de
/// `CALL_BRANCHES` del backend.
const List<String> kCallBranches = [
  'onAnswered',
  'onMissed',
  'onRejected',
  'onFailed',
  'onTimeout',
];

/// CCE#81 — Llama, ESPERA a que la llamada termine y sigue por la rama del
/// resultado. Es el primer step con más de dos salidas. La app sólo lo NARRA:
/// el wizard no lo edita (un flujo con `call` se abre en solo lectura).
class FlowCallStep extends FlowStep {
  FlowCallStep(super.json)
      : branches = {
          for (final k in kCallBranches)
            if (json.containsKey(k)) k: FlowStep.parseList(json[k]),
        };

  /// Las salidas PRESENTES en el JSON, por nombre. Una ausente no está en el
  /// mapa: el motor la hace caer en el paso siguiente.
  final Map<String, List<FlowStep>> branches;

  String? get number => raw['number'] is String ? raw['number'] as String : null;
  String? get contactId =>
      raw['contactId'] is String ? raw['contactId'] as String : null;
  num? get timeoutSeconds =>
      raw['timeoutSeconds'] is num ? raw['timeoutSeconds'] as num : null;

  /// La salida `kind`, o `[]` si no está.
  List<FlowStep> branch(String kind) => branches[kind] ?? const [];

  /// Todas las listas de pasos que cuelgan, para caminar el árbol.
  List<List<FlowStep>> get allBranches => [
        for (final k in kCallBranches) branch(k),
      ];
}

class FlowStopStep extends FlowStep {
  FlowStopStep(super.json);
}

/// Un `type` que esta versión de la app no conoce: se narra como desconocido y
/// jamás se edita.
class FlowUnknownStep extends FlowStep {
  FlowUnknownStep(super.json);
}

// ── Acciones: legacy (`on` + sentinelas) ↔ flujo (`kind` + target) ───────────

/// Acción de flujo → acción legacy, la que los sheets de la app y el executor
/// entienden. Port de `flowActionToLegacy` (flow-derive.ts): `lightId` sale
/// VACÍO en todo lo que no es `kind:'device'` porque en esas ramas el executor
/// rutea por `on` y no lo mira. Los campos ausentes no se escriben (en TS los
/// `undefined` se caen al serializar; acá hay que omitirlos a mano para que la
/// vuelta sea idéntica).
Map<String, dynamic> flowActionToLegacy(Map<String, dynamic> a) {
  final out = <String, dynamic>{'lightId': ''};
  void put(String key, Object? value) {
    if (value != null) out[key] = value;
  }

  switch (a['kind']) {
    case 'device':
      out['lightId'] = a['deviceId'] ?? '';
      put('on', a['on']);
      put('bri', a['bri']);
      put('briDelta', a['briDelta']);
      put('hue', a['hue']);
      put('sat', a['sat']);
      put('ct', a['ct']);
    case 'deviceVerb':
      out['on'] = 'device';
      put('deviceId', a['deviceId']);
      put('verb', a['verb']);
      put('args', a['args']);
    case 'group':
      out['on'] = 'group';
      put('groupId', a['groupId']);
      put('groupAction', a['action']);
    case 'hueRoom':
      out['on'] = 'hueRoom';
      put('hueRoomId', a['hueRoomId']);
      put('hueRoomAction', a['action']);
    case 'scene':
      out['on'] = 'scene';
      put('sceneId', a['sceneId']);
    case 'hueScene':
      out['on'] = 'hueScene';
      put('hueSceneId', a['hueSceneId']);
      put('sceneSmart', a['smart']);
    case 'notification':
      out['on'] = 'notification';
      put('notificationMessage', a['message']);
      put('notificationSound', a['sound']);
      put('notificationType', a['notificationType']);
    case 'alarm':
      out['on'] = 'alarm';
      put('alarmAction', a['action']);
    case 'jbl':
      out['on'] = 'jbl';
      put('jblAction', a['action']);
      put('jblOnMode', a['onMode']);
      put('jblRadioName', a['radioName']);
      put('jblVolume', a['volume']);
      put('jblNightMode', a['nightMode']);
    case 'announce':
      out['on'] = 'announce';
      put('announcerId', a['announcerId']);
    case 'automation':
      out['on'] = 'automation';
      put('automationIds', a['automationIds']);
      put('automationAction', a['action']);
      put('automationNotify', a['notify']);
      put('automationLabel', a['label']);
      put('notificationMessage', a['message']);
      put('notificationSound', a['sound']);
      put('notificationType', a['notificationType']);
    case 'call':
      out['on'] = 'call';
      put('callNumber', a['number']);
      put('callContactId', a['contactId']);
      put('callRingSeconds', a['ringSeconds']);
    default:
      // Un kind que no conocemos: se copia entero para no perderlo. El
      // wizard no lo edita (ver [wizardShapeOf]), sólo lo narra.
      return _copy(a);
  }
  return _copy(out);
}

/// Acción legacy → acción de flujo. Port de `legacyActionToFlow`
/// (flow-derive.ts), con una diferencia deliberada: los ids se leen por los
/// getters de [AutomationAction], que caen al sentinel `lightId` cuando la
/// clave explícita falta (`__scene__x` sin `sceneId` — config vieja). El
/// backend en ese caso escribiría `sceneId: ''`; acá sólo se escribe lo que
/// el wizard arma, y conviene que salga completo.
Map<String, dynamic> legacyActionToFlow(Map<String, dynamic> legacy) {
  final act = AutomationAction.fromJson(legacy);
  final a = act.raw;
  final out = <String, dynamic>{};
  void put(String key, Object? value) {
    if (value != null) out[key] = value;
  }

  switch (a['on']) {
    case 'notification':
      out['kind'] = 'notification';
      put('message', a['notificationMessage']);
      put('sound', a['notificationSound']);
      put('notificationType', a['notificationType']);
    case 'alarm':
      out['kind'] = 'alarm';
      put('action', a['alarmAction']);
    case 'jbl':
      out['kind'] = 'jbl';
      put('action', a['jblAction']);
      put('onMode', a['jblOnMode']);
      put('radioName', a['jblRadioName']);
      put('volume', a['jblVolume']);
      put('nightMode', a['jblNightMode']);
    case 'group':
      out['kind'] = 'group';
      out['groupId'] = act.groupId ?? '';
      put('action', a['groupAction']);
    case 'hueRoom':
      out['kind'] = 'hueRoom';
      out['hueRoomId'] = act.hueRoomId ?? '';
      put('action', a['hueRoomAction']);
    case 'scene':
      out['kind'] = 'scene';
      out['sceneId'] = act.sceneId ?? '';
    case 'hueScene':
      out['kind'] = 'hueScene';
      out['hueSceneId'] = act.hueSceneId ?? '';
      put('smart', a['sceneSmart']);
    case 'device':
      out['kind'] = 'deviceVerb';
      out['deviceId'] = a['deviceId'] ?? '';
      out['verb'] = a['verb'] ?? '';
      put('args', a['args']);
    case 'call':
      out['kind'] = 'call';
      put('number', a['callNumber']);
      put('contactId', a['callContactId']);
      put('ringSeconds', a['callRingSeconds']);
    case 'announce':
      out['kind'] = 'announce';
      out['announcerId'] = a['announcerId'] ?? '';
    case 'automation':
      out['kind'] = 'automation';
      out['automationIds'] = a['automationIds'] ?? const <String>[];
      put('action', a['automationAction']);
      put('notify', a['automationNotify']);
      put('label', a['automationLabel']);
      put('message', a['notificationMessage']);
      put('sound', a['notificationSound']);
      put('notificationType', a['notificationType']);
    default:
      // El prender/apagar genérico: `on` es estado (bool o modo relativo) y
      // el target es `lightId`.
      out['kind'] = 'device';
      out['deviceId'] = a['lightId'] ?? '';
      put('on', a['on']);
      put('bri', a['bri']);
      put('briDelta', a['briDelta']);
      put('hue', a['hue']);
      put('sat', a['sat']);
      put('ct', a['ct']);
  }
  return _copy(out);
}

/// Las acciones del CAMINO FELIZ de un árbol, en orden: el `then` de cada `if`
/// y nunca `else` / `onTimeout`. Es lo que el Dashboard escribe como espejo en
/// `actions` cuando persiste un flujo propio (`happyPathActions`,
/// flow-save.ts) y lo que la app muestra en las cards cuando el flujo gana.
List<Map<String, dynamic>> happyPathFlowActions(List<FlowStep> flow) {
  final out = <Map<String, dynamic>>[];
  void walk(List<FlowStep> steps) {
    for (final s in steps) {
      switch (s) {
        case FlowDoStep():
          out.addAll(s.actions);
        case FlowIfStep():
          walk(s.then);
        case FlowCallStep():
          walk(s.branch('onAnswered')); // CCE#81 — la rama feliz es «atendida».
        default:
          break; // wait / waitFor / stop no aportan acciones al espejo.
      }
    }
  }

  walk(flow);
  return out;
}

// ── when: el trigger como entrada de `when[]` ────────────────────────────────

/// Port de `deriveWhen` (flow-derive.ts) para UN trigger: desduplica los
/// escalares `sensorId/sensorField/sensorValue/sensorOperator/sensorOutlet/
/// sensorBindingId` contra `sensorTriggers[]` (con array presente, los
/// escalares se borran; sin array, se promueven a `sensorTriggers[0]`). Todo
/// lo demás del trigger viaja intacto.
Map<String, dynamic> deriveWhenEntry(Map<String, dynamic> trigger) {
  final t = _copy(trigger);
  final existing = t['sensorTriggers'];
  List<dynamic>? entries;
  if (existing is List && existing.isNotEmpty) {
    entries = existing;
  } else if (t['sensorId'] is String && (t['sensorId'] as String).isNotEmpty) {
    final e = <String, dynamic>{'sensorId': t['sensorId']};
    if (t['sensorBindingId'] is String && (t['sensorBindingId'] as String).isNotEmpty) {
      e['sensorBindingId'] = t['sensorBindingId'];
    }
    e['sensorField'] = t['sensorField'] ?? '';
    if (t.containsKey('sensorValue')) e['sensorValue'] = t['sensorValue'];
    if (t['sensorOperator'] is String && (t['sensorOperator'] as String).isNotEmpty) {
      e['sensorOperator'] = t['sensorOperator'];
    }
    if (t['sensorOutlet'] != null) e['sensorOutlet'] = t['sensorOutlet'];
    entries = [e];
  }
  for (final k in const [
    'sensorId',
    'sensorBindingId',
    'sensorField',
    'sensorValue',
    'sensorOperator',
    'sensorOutlet',
  ]) {
    t.remove(k);
  }
  if (entries != null) {
    t['sensorTriggers'] = entries;
  } else {
    t.remove('sensorTriggers');
  }
  return t;
}

// ── El molde del wizard ──────────────────────────────────────────────────────

/// Lo que el wizard edita, ya desarmado en sus cuatro pantallas:
/// condiciones (el `if`), acciones (el primer `do`), la espera y las acciones
/// de después (`wait` + segundo `do`).
class WizardShape {
  const WizardShape({
    this.conditions = const [],
    this.condWrapped = false,
    this.actions = const [],
    this.waitSeconds,
    this.afterActions = const [],
    this.trailingStop = false,
  });

  /// Las hojas del AND del `if`. Vacío = sin `if`.
  final List<AutomationCondition> conditions;

  /// true si la condición venía como `{and: [hoja]}` con UNA sola hoja. Se
  /// conserva al reconstruir para que abrir y guardar sin tocar no cambie el
  /// árbol (el backend no envuelve una hoja sola; alguien pudo haberlo hecho).
  final bool condWrapped;

  /// Las acciones de flujo (`kind` + target) del primer `do`.
  final List<Map<String, dynamic>> actions;

  /// Segundos del `wait`. null = no hay «¿y después?».
  final int? waitSeconds;

  /// Las acciones del `do` que sigue a la espera.
  final List<Map<String, dynamic>> afterActions;

  /// El árbol terminaba en un `stop` a nivel raíz. Es un no-op (el flujo
  /// termina igual) pero está en dos de las 26 de la casa, y borrarlo
  /// cambiaría su JSON al guardar.
  final bool trailingStop;

  bool get hasAfter => waitSeconds != null && afterActions.isNotEmpty;
}

bool _actionsFit(List<Map<String, dynamic>> actions) =>
    actions.isNotEmpty &&
    actions.every((a) => kFlowActionKinds.contains(a['kind']));

/// ¿Entra este flujo en el molde del wizard? Devuelve la forma desarmada, o
/// null si el árbol tiene algo que las cinco pantallas no pueden expresar
/// (ramas anidadas, `si no` con contenido, `waitFor`, más de un `wait`, una
/// condición con `or`/`not`, acciones desconocidas). Pura: sin UI.
///
/// Un `flow` vacío ENTRA (es una automatización sin acciones todavía).
WizardShape? wizardShapeOf(List<FlowStep> flow) {
  var steps = flow;
  var trailingStop = false;
  if (steps.isNotEmpty && steps.last is FlowStopStep) {
    trailingStop = true;
    steps = steps.sublist(0, steps.length - 1);
  }
  if (steps.isEmpty) return WizardShape(trailingStop: trailingStop);

  var conditions = const <AutomationCondition>[];
  var condWrapped = false;
  var seq = steps;
  if (steps.length == 1 && steps.first is FlowIfStep) {
    final ifStep = steps.first as FlowIfStep;
    if (ifStep.hasElse) return null;
    final leaves = ifStep.cond.andLeaves();
    if (leaves == null || leaves.isEmpty) return null;
    if (leaves.any((c) => !kFlowCondLeafTypes.contains(c.type))) return null;
    conditions = leaves;
    condWrapped = ifStep.cond.isAnd && leaves.length == 1;
    seq = ifStep.then;
  }

  if (seq.isEmpty || seq.first is! FlowDoStep) return null;
  final first = seq.first as FlowDoStep;
  if (!_actionsFit(first.actions)) return null;
  if (seq.length == 1) {
    return WizardShape(
      conditions: conditions,
      condWrapped: condWrapped,
      actions: first.actions,
      trailingStop: trailingStop,
    );
  }
  if (seq.length != 3 || seq[1] is! FlowWaitStep || seq[2] is! FlowDoStep) {
    return null;
  }
  final wait = (seq[1] as FlowWaitStep).seconds;
  if (wait == null || wait < 0 || wait != wait.roundToDouble()) return null;
  final after = (seq[2] as FlowDoStep).actions;
  if (!_actionsFit(after)) return null;
  return WizardShape(
    conditions: conditions,
    condWrapped: condWrapped,
    actions: first.actions,
    waitSeconds: wait.toInt(),
    afterActions: after,
    trailingStop: trailingStop,
  );
}

/// Por qué un flujo NO entra en el molde, en una frase para el aviso de solo
/// lectura. null si entra. Se recorre el árbol buscando la primera causa; el
/// orden es el de qué le resulta más reconocible a quien lo armó en el
/// diagrama.
String? wizardUnsupportedReason(List<FlowStep> flow) {
  if (wizardShapeOf(flow) != null) return null;
  bool has(bool Function(FlowStep) test, List<FlowStep> steps) {
    for (final s in steps) {
      if (test(s)) return true;
      if (s is FlowIfStep &&
          (has(test, s.then) || has(test, s.otherwise ?? const []))) {
        return true;
      }
      if (s is FlowWaitForStep && has(test, s.onTimeout ?? const [])) {
        return true;
      }
      if (s is FlowCallStep && s.allBranches.any((b) => has(test, b))) {
        return true;
      }
    }
    return false;
  }

  int count(bool Function(FlowStep) test, List<FlowStep> steps) {
    var n = 0;
    for (final s in steps) {
      if (test(s)) n++;
      if (s is FlowIfStep) {
        n += count(test, s.then) + count(test, s.otherwise ?? const []);
      }
      if (s is FlowWaitForStep) n += count(test, s.onTimeout ?? const []);
      if (s is FlowCallStep) {
        for (final b in s.allBranches) {
          n += count(test, b);
        }
      }
    }
    return n;
  }

  bool condComplex(FlowCond c) =>
      c.isOr || c.isNot || (c.isAnd && c.children.any((x) => !x.isLeaf));

  if (has((s) => s is FlowCallStep, flow)) {
    return 'llama y sigue según cómo termine la llamada';
  }
  if (has((s) => s is FlowWaitForStep, flow)) {
    return 'espera a que se cumpla una condición';
  }
  if (has((s) => s is FlowIfStep && s.hasElse, flow)) {
    return 'tiene una rama «si no»';
  }
  if (flow.any((s) => s is FlowIfStep &&
      (s.then.any((t) => t is FlowIfStep) ||
          (s.otherwise ?? const []).any((t) => t is FlowIfStep)))) {
    return 'tiene condiciones anidadas';
  }
  if (count((s) => s is FlowIfStep, flow) > 1) {
    return 'tiene más de una condición en secuencia';
  }
  if (count((s) => s is FlowWaitStep, flow) > 1) {
    return 'tiene más de una espera';
  }
  if (has((s) => s is FlowIfStep && condComplex(s.cond), flow)) {
    return 'combina condiciones con «o» / «no»';
  }
  if (has((s) => s is FlowUnknownStep, flow)) {
    return 'tiene pasos que esta versión de la app no conoce';
  }
  if (has(
      (s) => s is FlowDoStep &&
          s.actions.any((a) => !kFlowActionKinds.contains(a['kind'])),
      flow)) {
    return 'tiene acciones que esta versión de la app no conoce';
  }
  return 'tiene una estructura que el wizard no cubre';
}

/// El árbol que produce el molde. Sin acciones no hay flujo válido (el backend
/// exige al menos una por `do`), así que devuelve `[]`; la validación del
/// wizard frena el guardado antes de llegar acá.
///
/// Con condición: `[{if, cond, then: [do, wait, do]}]`; sin condición:
/// `[do, wait, do]`. Sin «¿y después?» se omiten `wait` y el segundo `do`.
List<Map<String, dynamic>> buildWizardFlow(WizardShape s) {
  if (s.actions.isEmpty) return const [];
  final seq = <Map<String, dynamic>>[
    {'type': 'do', 'actions': _copyList(s.actions)},
  ];
  if (s.hasAfter) {
    seq.add({'type': 'wait', 'seconds': s.waitSeconds});
    seq.add({'type': 'do', 'actions': _copyList(s.afterActions)});
  }
  List<Map<String, dynamic>> out;
  if (s.conditions.isNotEmpty) {
    final leaves = [for (final c in s.conditions) c.toJson()];
    final cond = leaves.length == 1 && !s.condWrapped
        ? leaves.first
        : <String, dynamic>{'and': leaves};
    out = [
      {'type': 'if', 'cond': cond, 'then': seq},
    ];
  } else {
    out = seq;
  }
  if (s.trailingStop) out.add({'type': 'stop'});
  return out;
}

/// ¿Dos árboles son el mismo? Igualdad profunda sobre el JSON.
bool sameFlow(List<dynamic> a, List<dynamic> b) => _eq.equals(a, b);

/// El trigger "normalizado" para comparar (lo que emite el modelo tras
/// parsearlo) SIN sus `conditions`, que en el modelo de flujo viven en el
/// `if` y no en el trigger.
Map<String, dynamic> normalizedTriggerWithoutConditions(
    Map<String, dynamic> trigger) {
  final t = AutomationTrigger.fromJson(trigger).toJson();
  t.remove('conditions');
  return t;
}

// ── El draft del wizard ──────────────────────────────────────────────────────

/// El estado editable del wizard sobre un [Automation] draft. Es la capa entre
/// las cinco pantallas y el árbol: los sheets existentes mutan
/// `automation.trigger` (CUÁNDO y SOLO SI) y `automation.actions` (¿QUÉ HACE?),
/// la espera y las acciones de después viven acá, y [buildFlow] los vuelve a
/// juntar en el `flow` que se persiste.
///
/// Sin Flutter: lo que el wizard decide (¿entra en el molde?, ¿cambió algo?,
/// ¿qué se va a guardar?) se prueba con `test()` a secas.
class WizardDraft {
  WizardDraft(this.automation) {
    _originalFlow = automation.raw['flow'] is List
        ? _copyList([
            for (final s in automation.raw['flow'] as List)
              if (s is Map) s
          ])
        : null;

    WizardShape? shape;
    if (_originalFlow != null) {
      shape = wizardShapeOf(FlowStep.parseList(_originalFlow));
      _unsupportedReason =
          shape == null ? wizardUnsupportedReason(automation.flow) : null;
    } else {
      // Sin `flow` en el JSON (una automatización nueva, o un server viejo):
      // el molde sale del formato plano, que siempre entra.
      shape = WizardShape(
        conditions: automation.trigger.conditions,
        actions: [
          for (final a in automation.actions) legacyActionToFlow(a.toJson()),
        ],
      );
    }
    if (shape != null && automation.when.length > 1) {
      shape = null;
      _unsupportedReason = 'tiene más de un disparador';
    }
    if (shape != null &&
        !kWizardTriggerTypes.contains(automation.trigger.type)) {
      shape = null;
      _unsupportedReason = 'su disparador (${automation.trigger.type}) '
          'no se edita desde la app';
    }
    _shape = shape;
    if (shape == null) return;

    // Las cuatro secciones, ya en el shape legacy que los sheets editan.
    //
    // Con flujo PROPIO las condiciones y las acciones se toman del árbol:
    // `trigger.conditions` viene vacío y `actions` es sólo un espejo que otro
    // cliente pudo dejar viejo. Con flujo PROYECTADO (o sin `flow`) se dejan
    // las que vinieron: son, por construcción, las mismas que el árbol
    // derivado — y así un draft sin tocar re-serializa byte a byte.
    if (automation.hasOwnFlow) {
      automation.trigger.conditions = [
        for (final c in shape.conditions)
          AutomationCondition.fromJson(c.toJson()),
      ];
      automation.actions = [
        for (final a in shape.actions)
          AutomationAction.fromJson(flowActionToLegacy(a)),
      ];
    }
    waitSeconds = shape.waitSeconds;
    afterShell.actions = [
      for (final a in shape.afterActions)
        AutomationAction.fromJson(flowActionToLegacy(a)),
    ];
  }

  final Automation automation;

  /// Un [Automation] cascarón cuya lista `actions` son las acciones de
  /// «¿y después?»: el sheet ENTONCES sólo toca `draft.actions`, así que sirve
  /// tal cual para editar esta segunda lista sin duplicar 1.700 líneas.
  final Automation afterShell = Automation.fromJson(const {});

  List<Map<String, dynamic>>? _originalFlow;
  WizardShape? _shape;
  String? _unsupportedReason;

  /// Segundos de la espera de «¿y después?». null = no hay después.
  int? waitSeconds;

  /// null = el flujo no entra en el molde: la app lo muestra narrado y no lo
  /// edita (ver [unsupportedReason]).
  WizardShape? get shape => _shape;
  bool get readOnly => _shape == null;
  String? get unsupportedReason => _unsupportedReason;

  List<AutomationAction> get afterActions => afterShell.actions;

  /// El molde con el estado ACTUAL de las cuatro pantallas.
  WizardShape currentShape() => WizardShape(
        conditions: automation.trigger.conditions,
        condWrapped: _shape?.condWrapped ?? false,
        actions: [
          for (final a in automation.actions) legacyActionToFlow(a.toJson()),
        ],
        waitSeconds: waitSeconds,
        afterActions: [
          for (final a in afterActions) legacyActionToFlow(a.toJson()),
        ],
        trailingStop: _shape?.trailingStop ?? false,
      );

  /// El `flow` que se persistiría ahora. En solo lectura es el que vino: la
  /// app jamás reconstruye un árbol que no entra en el molde.
  List<Map<String, dynamic>> buildFlow() => readOnly
      ? _copyList(_originalFlow ?? const [])
      : buildWizardFlow(currentShape());

  /// ¿El árbol cambió respecto del que vino? Compara el árbol RECONSTRUIDO
  /// con el original: abrir y no tocar tiene que dar false para las 26.
  bool get flowChanged =>
      !readOnly && !sameFlow(buildFlow(), _originalFlow ?? const []);

  /// ¿El disparador cambió? Se compara normalizado (lo que el modelo emite
  /// tras parsear cada lado) y sin `conditions`, que se comparan con el flujo.
  bool get triggerChanged {
    final orig = automation.original['trigger'];
    final before = orig is Map
        ? normalizedTriggerWithoutConditions(Map<String, dynamic>.from(orig))
        : const <String, dynamic>{};
    final now = automation.trigger.toJson()..remove('conditions');
    return !_eq.equals(now, before);
  }

  bool get headerChanged {
    final o = automation.original;
    return automation.name != ((o['name'] ?? '').toString()) ||
        automation.icon != ((o['icon'] ?? '').toString()) ||
        automation.enabled != (o['enabled'] == true);
  }

  /// ¿Hay algo que guardar? En solo lectura, nunca.
  bool get dirty =>
      !readOnly && (headerChanged || triggerChanged || flowChanged);

  /// Motivo por el que no se puede guardar, o null. Reusa la validación del
  /// modelo (nombre, disparador, al menos una acción) y agrega la del paso
  /// «¿y después?».
  String? validationError({bool ignoreName = false}) {
    final base = automation.validationError(ignoreName: ignoreName);
    if (base != null) return base;
    if (waitSeconds != null && afterActions.isEmpty) {
      return 'Elegí qué hacer después de la espera';
    }
    return null;
  }

  /// Vuelca las cuatro pantallas al draft: a partir de acá `toJson()` emite
  /// `when` + `flow` (ver [Automation.setOwnFlow]). Idempotente: se puede
  /// llamar de nuevo tras un conflicto sin perder nada.
  ///
  /// Sin cambios NO hace nada: una automatización proyectada que se abre y se
  /// guarda tal cual no pasa a tener flujo propio (eso sí cambiaría su JSON).
  void commit() {
    if (readOnly || !dirty) return;
    automation.setOwnFlow(buildFlow());
  }
}
