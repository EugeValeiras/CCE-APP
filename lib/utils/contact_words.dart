/// EL vocabulario de `contact`: la ÚNICA fuente de las palabras con las que la
/// App le cuenta al dueño que una abertura está abierta o cerrada.
///
/// CONVENCIÓN DE LA CASA — **`contact: true` es ABIERTA**. La fija el backend
/// (el parser de eWeLink hace `contact: lock === 1`, y 1 es la puerta abierta)
/// y la respetan el historial, la alarma, el plano, los destacados de la home
/// y las automatizaciones.
///
/// Existe porque la palabra se decidía suelta en nueve archivos y uno la
/// invirtió: la vista unificada narraba `contact: true` como «Cerrado»
/// (EugeValeiras/CCE#115). Con el par en un solo lugar, invertirlo en una vista
/// deja de ser posible sin invertirlo en todas.
///
/// Son DOS vocabularios, no uno: el ADJETIVO ([label]) con el que las vistas
/// cuentan cómo está la puerta, y el VERBO ([verb]) con el que las
/// automatizaciones cuentan lo que le pasa. Centralizar sólo el primero deja
/// afuera al editor de disparadores, que es el único que ESCRIBE el valor.
///
/// El género es FEMENINO porque el sujeto es la abertura ("la puerta", "la
/// ventana"), no el sensor; [masculine] existe sólo para las frases que ponen
/// el nombre del device de sujeto ("Sensor cocina está abierto").
///
/// Una vista nueva que narre una apertura toma las palabras de acá:
/// `test/contact_vocabulary_test.dart` recorre las que ya existen y falla si
/// alguna se inventa las suyas.
abstract final class ContactWords {
  /// Etiqueta de estado, la palabra corta de tiles, filas y badges.
  /// `contact: true` ⇒ [open].
  static const open = 'Abierta';
  static const closed = 'Cerrada';

  /// La etiqueta que le corresponde al booleano. ÉSTE es el mapeo que fija la
  /// convención: true ⇒ «Abierta».
  static String label(bool isOpen) => isOpen ? open : closed;

  /// En minúscula, para cerrar una frase cuyo sujeto es la abertura:
  /// «Puerta de la cocina abierta».
  static String feminine(bool isOpen) => isOpen ? 'abierta' : 'cerrada';

  /// En minúscula y en masculino, para las frases cuyo sujeto es el nombre del
  /// device: «Sensor cocina está abierto».
  static String masculine(bool isOpen) => isOpen ? 'abierto' : 'cerrado';

  /// Contador de aberturas abiertas de un encabezado de sección
  /// («1 abierta», «3 abiertas»). Sólo se dice el lado que urge: con cero
  /// abiertas no hay nada que contar y devuelve null, así el llamador no
  /// vuelve a decidir por afuera lo que este helper vino a absorber.
  static String? openCount(int count) => switch (count) {
        <= 0 => null,
        1 => '1 abierta',
        _ => '$count abiertas',
      };

  /// Frase entera para lectores de pantalla y tooltips, donde la palabra corta
  /// sola no dice de qué se habla.
  static const openSemantics = 'Puerta abierta';

  // ── El vocabulario VERBAL: el HECHO, no el estado ──────────────────────────
  //
  // Las automatizaciones no hablan de cómo está la puerta sino de lo que pasa
  // con ella, y ahí la convención pesa MÁS que en las vistas de estado: el
  // editor de disparadores no la lee, la ESCRIBE. Si «Se cierra» guardara
  // `sensorValue: true`, el dueño terminaría con una automatización que hace lo
  // contrario de lo que eligió — y la App no tendría cómo notarlo.

  /// El disparador tal como se elige en el editor. `sensorValue: true` ⇒ [opens].
  static const opens = 'Se abre';
  static const closes = 'Se cierra';

  static String verb(bool isOpen) => isOpen ? opens : closes;

  /// En subjuntivo y minúscula, para la cláusula que sigue a «Cuando»:
  /// «Cuando se abra la puerta de la cocina».
  static String verbSubjunctive(bool isOpen) => isOpen ? 'se abra' : 'se cierre';
}
