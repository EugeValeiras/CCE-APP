/// EL vocabulario de `contact`: la ÚNICA fuente de las palabras con las que la
/// App le cuenta al dueño que una abertura está abierta o cerrada.
///
/// CONVENCIÓN DE LA CASA — **`contact: true` es ABIERTA**. La fija el backend
/// (el parser de eWeLink hace `contact: lock === 1`, y 1 es la puerta abierta)
/// y la respetan el historial, la alarma, el plano, los destacados de la home
/// y las automatizaciones.
///
/// Existe porque la palabra se decidía suelta en ocho archivos y uno la
/// invirtió: la vista unificada narraba `contact: true` como «Cerrado»
/// (EugeValeiras/CCE#115). Con el par en un solo lugar, invertirlo en una vista
/// deja de ser posible sin invertirlo en todas.
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
  /// («1 abierta», «3 abiertas»). Sólo se dice el lado que urge.
  static String openCount(int count) =>
      count == 1 ? '1 abierta' : '$count abiertas';

  /// Frase entera para lectores de pantalla y tooltips, donde la palabra corta
  /// sola no dice de qué se habla.
  static const openSemantics = 'Puerta abierta';
}
