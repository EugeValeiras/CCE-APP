import '../models/device.dart';
import 'verb_labels.dart';

/// Una opción de un enum del catálogo de capabilities: lo que VIAJA y cómo se
/// LEE (CCE#100).
///
/// Antes los dos editores (la vista unificada y el sheet de acciones de las
/// automatizaciones) usaban el mismo string para las dos cosas. Eso alcanza
/// para los modos de limpieza del robot —cuyo valor ES el label real— pero no
/// para lo que trajo el Hexagon:
///
///  - las ESCENAS viajan por su `id` de config (`tuyascene_a`) y se leen por el
///    nombre que les puso el dueño («Aurora»). Que el id sea estable es lo que
///    permite renombrar una escena sin romper las automatizaciones que la usan;
///  - los MODOS viajan como los nombra el aparato (`colour`) y se leen en
///    castellano («Color»).
class EnumOption {
  final String value;
  final String label;
  const EnumOption(this.value, this.label);
}

/// Opciones de un enum del catálogo para un device.
///
/// Los enums DINÁMICOS salen del estado del device: el backend los manda
/// vacíos a propósito, porque sus valores no son del schema sino del aparato
/// (los modos que declara su producto) o de la config (las escenas guardadas).
/// [catalogValues] resuelve los estáticos (teclas del remoto, acciones de
/// reproducción) contra el catálogo bajado.
List<EnumOption> resolveEnumOptions(
  String ref,
  DeviceState state,
  List<String> Function(String ref) catalogValues,
) {
  switch (ref) {
    case 'VACUUM_CLEAN_MODES':
      return _plain(state.cleanModes);
    case 'VACUUM_FAN_SPEEDS':
      return _plain(state.fanSpeeds);
    case 'VACUUM_ROOMS':
      // El backend acepta nombres o segmentIds; se mandan nombres.
      return _plain((state.rooms ?? const []).map((r) => r.name).toList());
    case 'LIGHT_MODES':
      return (state.lightModes ?? const [])
          .map((m) => EnumOption(m, lightModeLabel(m)))
          .toList();
    case 'LIGHT_SCENES':
      return (state.lightScenes ?? const [])
          .map((sc) => EnumOption(sc.id, sc.name))
          .toList();
    default:
      return _plain(catalogValues(ref));
  }
}

/// Etiqueta = valor: los enums donde el valor ya es legible.
List<EnumOption> _plain(List<String>? values) =>
    (values ?? const []).map((v) => EnumOption(v, v)).toList();

/// Cómo se lee un valor ya guardado de un enum (para el resumen de una acción
/// guardada: la escena se muestra por su nombre, no por su id).
String enumOptionLabel(String ref, String value, DeviceState state) {
  for (final o in resolveEnumOptions(ref, state, (_) => const [])) {
    if (o.value == value) return o.label;
  }
  // Un valor que ya no está entre las opciones (escena borrada, modo que el
  // producto dejó de declarar) se muestra crudo antes que en blanco.
  return value;
}
