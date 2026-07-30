/// Lógica PURA del vacuum Roborock (sin Flutter) — testeable standalone.
///
/// Los cleanModes del robot son labels reales tipo 'Auto, Vacuum and Mop':
/// una matriz potencia × función. Acá se intenta descomponerla para ofrecer
/// dos selectores segmentados en vez de una lista de 9; si los modos del robot
/// no siguen el patrón (otro firmware, otro robot), [VacuumModeMatrix.tryBuild]
/// devuelve null y la UI cae a la lista cruda (mismo criterio que el Dashboard:
/// el label REAL es el value — jamás se inventa un modo).
library;

// El label del estado del robot vive en utils/vacuum_state.dart
// (vacuumStateLabel(Device)): lee `vacuumActivity` del sidecar, igual que el
// Dashboard. El viejo etiquetador por `vacuumState` de Matter que vivía acá
// mostraba "En base" con el robot cargando o lavando la mopa.

/// Matriz potencia × función derivada de los cleanModes reales.
class VacuumModeMatrix {
  /// Primeras partes en orden de aparición (ej. Quiet, Auto, Deep Clean).
  final List<String> powers;

  /// Segundas partes en orden de aparición (ej. Vacuum Only, Mop Only, …).
  final List<String> functions;

  const VacuumModeMatrix._(this.powers, this.functions);

  /// Separador REAL de los labels del robot.
  static const String _sep = ', ';

  /// Construye la matriz si (y solo si) los modos son un producto cruzado
  /// completo de 'A, B'. Cualquier desviación → null (la UI usa lista cruda).
  static VacuumModeMatrix? tryBuild(List<String>? modes) {
    if (modes == null || modes.length < 2) return null;
    final powers = <String>[];
    final functions = <String>[];
    for (final m in modes) {
      final idx = m.indexOf(_sep);
      // Debe partir en exactamente 2 mitades no vacías (un solo separador).
      if (idx <= 0 || m.indexOf(_sep, idx + 1) != -1) return null;
      final p = m.substring(0, idx);
      final f = m.substring(idx + _sep.length);
      if (f.isEmpty) return null;
      if (!powers.contains(p)) powers.add(p);
      if (!functions.contains(f)) functions.add(f);
    }
    // Producto cruzado completo: cada combinación existe en la lista original.
    if (powers.length * functions.length != modes.length) return null;
    for (final p in powers) {
      for (final f in functions) {
        if (!modes.contains(p + _sep + f)) return null;
      }
    }
    return VacuumModeMatrix._(powers, functions);
  }

  /// Compone el label REAL a mandar en setCleanMode.
  String compose(String power, String function) => power + _sep + function;

  /// Descompone el cleanMode activo; null si no pertenece a la matriz.
  ({String power, String function})? split(String? mode) {
    if (mode == null) return null;
    final idx = mode.indexOf(_sep);
    if (idx <= 0) return null;
    final p = mode.substring(0, idx);
    final f = mode.substring(idx + _sep.length);
    if (!powers.contains(p) || !functions.contains(f)) return null;
    return (power: p, function: f);
  }
}

/// Labels español para las mitades conocidas; desconocidas se muestran crudas.
String vacuumPowerLabel(String raw) {
  switch (raw) {
    case 'Quiet':
      return 'Silencioso';
    case 'Auto':
      return 'Auto';
    case 'Deep Clean':
      return 'Profundo';
    default:
      return raw;
  }
}

String vacuumFunctionLabel(String raw) {
  switch (raw) {
    case 'Vacuum Only':
      return 'Aspirar';
    case 'Mop Only':
      return 'Trapear';
    case 'Vacuum and Mop':
      return 'Ambos';
    default:
      return raw;
  }
}
