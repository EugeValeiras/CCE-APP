/// El TIPO de alarma y el NIVEL de cada sensor (EugeValeiras/CCE#133).
///
/// La alarma era un booleano y por eso casi no se usaba: con los 20 sensores
/// marcados —16 de apertura y 4 de movimiento— armarla con gente adentro la
/// hacía sonar en cuanto alguien cruzaba el pasillo. En la práctica sólo
/// servía con la casa vacía.
///
/// Ahora la alarma se arma de dos formas —**perimetral** (puertas y accesos) y
/// **total** (todo, incluido el movimiento interior)— y cada sensor dice en
/// cuál participa. El perímetro es un SUBCONJUNTO del total: armada en total
/// dispara todo, exactamente como antes.
library;

/// Qué protege la alarma cuando está armada.
enum AlarmMode {
  perimeter,
  total;

  /// El literal del contrato con la API (`'perimeter'` / `'total'`).
  String get wire => name;

  /// Cómo se nombra en pantalla. En minúscula: se compone con «alarma X».
  String get label => this == AlarmMode.perimeter ? 'perimetral' : 'total';

  /// Para un título o un chip: PERIMETRAL / TOTAL.
  String get shout => label.toUpperCase();

  /// Qué promete cada tipo, en una línea. Es lo que hace que elegir no sea
  /// adivinar: «perimetral» no significa nada por sí solo.
  String get blurb => this == AlarmMode.perimeter
      ? 'Sólo puertas y accesos. Podés estar adentro.'
      : 'Todo, incluido el movimiento adentro de casa.';

  /// El tipo que dice la API, o `null` si no lo dice.
  ///
  /// **`null` no es «total»**: es «este backend no conoce los tipos». El mismo
  /// criterio que `testMode` (CCE#122) — contra una API vieja la pantalla no
  /// dibuja lo que no puede saber, en vez de afirmar algo que no leyó.
  static AlarmMode? fromWire(Object? value) {
    if (value == 'perimeter') return AlarmMode.perimeter;
    if (value == 'total') return AlarmMode.total;
    return null;
  }
}

/// En qué tipos de alarma participa un sensor marcado.
enum SensorAlarmLevel {
  /// Dispara en los dos tipos.
  perimeter,

  /// Sólo en total.
  interior;

  String get wire => name;

  String get label =>
      this == SensorAlarmLevel.perimeter ? 'Perímetro' : 'Interior';

  /// Lo que hay que entender antes de tocar el selector.
  String get blurb => this == SensorAlarmLevel.perimeter
      ? 'Suena en las dos alarmas'
      : 'Sólo en la alarma total';

  /// El nivel que dice la API.
  ///
  /// Lo que no sea uno de los dos literales —incluida la ausencia— vale
  /// `interior`, igual que en el backend: el perímetro protege exactamente lo
  /// que alguien declaró perímetro, nunca un sensor de movimiento que se coló
  /// por omisión y hace sonar la alarma con la familia durmiendo.
  static SensorAlarmLevel fromWire(Object? value) =>
      value == 'perimeter' ? SensorAlarmLevel.perimeter : SensorAlarmLevel.interior;
}

/// LA decisión, la misma que el backend: ¿este sensor hace sonar la alarma con
/// este tipo armado? Perímetro ⊂ total.
bool sensorFiresInMode(AlarmMode mode, SensorAlarmLevel level) =>
    mode == AlarmMode.total || level == SensorAlarmLevel.perimeter;
