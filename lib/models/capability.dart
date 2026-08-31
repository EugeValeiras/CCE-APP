/// Modelo del catálogo de capabilities (GET /api/capabilities), espejo del
/// backend (`capability-catalog.ts`) y del cliente del Dashboard
/// (`capability-catalog.service.ts`).
///
/// Convierte a la app en un INTÉRPRETE del schema: dado un device, sabemos qué
/// campos posee cada capability y qué verbos/args acepta, para elegir y
/// parametrizar el control genérico sin lógica de dominio hardcodeada.
library;

/// Un argumento de una acción del catálogo (espejo de ArgSpec).
class CatalogArgSpec {
  final String name;

  /// 'boolean' | 'number' | 'string'
  final String type;

  /// Espejo del backend: un arg es requerido salvo que diga lo contrario
  /// (`required: false`), y el catálogo omite la clave cuando lo es.
  final bool required;
  final num? min;
  final num? max;

  /// Campos de state de los que sale el rango REAL del device cuando los
  /// reporta (CCE#62): el setpoint de un termostato vive entre state.minTemp y
  /// state.maxTemp, que cambian por modelo. Es el análogo numérico de un
  /// enumRef dinámico; [min]/[max] quedan de piso documental.
  final String? minFrom;
  final String? maxFrom;

  /// Paso del control numérico (0.5 = medio grado). null ⇒ de a 1.
  final num? step;

  /// Unidad para rotular el valor ('°C').
  final String? unit;

  /// Referencia a un enum del catálogo (REMOTE_KEY_IDS, TV_INPUTS,
  /// VACUUM_CLEAN_MODES, …). Los dinámicos por-device se hidratan del state.
  final String? enumRef;
  final Object? defaultValue;

  const CatalogArgSpec({
    required this.name,
    required this.type,
    this.required = true,
    this.min,
    this.max,
    this.minFrom,
    this.maxFrom,
    this.step,
    this.unit,
    this.enumRef,
    this.defaultValue,
  });

  factory CatalogArgSpec.fromJson(Map<String, dynamic> json) => CatalogArgSpec(
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? 'string').toString(),
        required: json['required'] != false,
        min: json['min'] is num ? json['min'] as num : null,
        max: json['max'] is num ? json['max'] as num : null,
        minFrom: json['minFrom'] as String?,
        maxFrom: json['maxFrom'] as String?,
        step: json['step'] is num ? json['step'] as num : null,
        unit: json['unit'] as String?,
        enumRef: json['enumRef'] as String?,
        defaultValue: json['default'],
      );
}

/// Una acción del catálogo (espejo de ActionSpec): verbo + args + policy.
class CatalogActionSpec {
  final String verb;
  final List<CatalogArgSpec> args;

  /// 'sensitive' = requiere confirm explícito (p.ej. unlock). null = normal.
  final String? policy;
  final List<String> affects;

  const CatalogActionSpec({
    required this.verb,
    this.args = const [],
    this.policy,
    this.affects = const [],
  });

  bool get isSensitive => policy == 'sensitive';

  factory CatalogActionSpec.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'];
    final rawAffects = json['affects'];
    return CatalogActionSpec(
      verb: (json['verb'] ?? '').toString(),
      args: rawArgs is List
          ? rawArgs
              .whereType<Map>()
              .map((a) => CatalogArgSpec.fromJson(Map<String, dynamic>.from(a)))
              .toList()
          : const [],
      policy: json['policy'] as String?,
      affects: rawAffects is List
          ? rawAffects.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Spec de una capability (espejo de CapabilitySpec): owns (stateFields) + actions.
class CapabilitySpec {
  final String capability;
  final List<String> stateFields;
  final List<String> sensorFields;
  final List<CatalogActionSpec> actions;

  const CapabilitySpec({
    required this.capability,
    this.stateFields = const [],
    this.sensorFields = const [],
    this.actions = const [],
  });

  /// Regla del catálogo: capability con actions ⇒ POST /actions/:verb;
  /// capability sólo con stateFields ⇒ PUT /state.
  bool get isVerbDriven => actions.isNotEmpty;

  factory CapabilitySpec.fromJson(Map<String, dynamic> json) {
    List<String> strs(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    final rawActions = json['actions'];
    return CapabilitySpec(
      capability: (json['capability'] ?? '').toString(),
      stateFields: strs(json['stateFields']),
      sensorFields: strs(json['sensorFields']),
      actions: rawActions is List
          ? rawActions
              .whereType<Map>()
              .map((a) =>
                  CatalogActionSpec.fromJson(Map<String, dynamic>.from(a)))
              .toList()
          : const [],
    );
  }

  CatalogActionSpec? findAction(String verb) {
    for (final a in actions) {
      if (a.verb == verb) return a;
    }
    return null;
  }
}

/// Respuesta completa de GET /api/capabilities.
class CapabilityCatalog {
  final List<String> baseStateFields;
  final Map<String, CapabilitySpec> capabilities;
  final Map<String, List<String>> enums;

  const CapabilityCatalog({
    this.baseStateFields = const [],
    this.capabilities = const {},
    this.enums = const {},
  });

  CapabilitySpec? specFor(String capability) => capabilities[capability];

  /// Valores de un enum del catálogo (estáticos). Los dinámicos por-device
  /// (TV_INPUTS, VACUUM_*) viajan vacíos y se hidratan del state del device.
  List<String> enumValues(String ref) => enums[ref] ?? const [];

  factory CapabilityCatalog.fromJson(Map<String, dynamic> json) {
    final rawCaps = json['capabilities'];
    final caps = <String, CapabilitySpec>{};
    if (rawCaps is Map) {
      for (final e in rawCaps.entries) {
        if (e.value is Map) {
          caps[e.key.toString()] =
              CapabilitySpec.fromJson(Map<String, dynamic>.from(e.value));
        }
      }
    }
    final rawEnums = json['enums'];
    final enums = <String, List<String>>{};
    if (rawEnums is Map) {
      for (final e in rawEnums.entries) {
        if (e.value is List) {
          enums[e.key.toString()] =
              (e.value as List).map((x) => x.toString()).toList();
        }
      }
    }
    final rawBase = json['baseStateFields'];
    return CapabilityCatalog(
      baseStateFields:
          rawBase is List ? rawBase.map((e) => e.toString()).toList() : const [],
      capabilities: caps,
      enums: enums,
    );
  }
}
