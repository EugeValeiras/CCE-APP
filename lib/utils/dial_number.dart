/// Normalización de lo que se disca. Lógica PURA (sin Flutter) para testearla
/// standalone: es la que decide si un número sale o no del dial pad.
library;

/// Lo que el módem acepta discar: dígitos, `+` (prefijo internacional), y `*`
/// y `#` (códigos de operador como `*2447` o `*234#`, y tonos DTMF).
const String _kDialable = '0123456789+*#';

/// Limpia un número pegado desde otra app.
///
/// Un número copiado de WhatsApp, de un contacto o de una web llega con
/// espacios, guiones, paréntesis o un `tel:` adelante. Nada de eso se puede
/// mandar al módem, pero tampoco es motivo para rechazar el pegado: se tira lo
/// que no se puede discar y se conserva lo que sí.
///
/// El `+` sólo sobrevive al principio: `+54 9 (261) 626-0811` → `+5492616260811`,
/// pero un `+` en el medio era basura del formato original.
String sanitizeDialInput(String raw) {
  var text = raw.trim();
  // 'tel:' / 'callto:' de un link copiado.
  final scheme = RegExp(r'^(tel|callto):', caseSensitive: false);
  text = text.replaceFirst(scheme, '');
  // %2B es '+' urlencodeado, que es como viaja en un tel: de una web.
  text = text.replaceAll('%2B', '+').replaceAll('%2b', '+');

  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (!_kDialable.contains(ch)) continue;
    if (ch == '+' && buffer.length > 0) continue;
    buffer.write(ch);
  }
  return buffer.toString();
}

/// ¿Esto se puede discar?
///
/// Mínimo 3 caracteres: alcanza para los cortos reales (`*2447`, `911`) y
/// frena el toque accidental de una sola tecla, que con la línea activa
/// cuesta plata.
bool isDialable(String number) {
  final n = sanitizeDialInput(number);
  if (n.length < 3) return false;
  // Un '+' solo no es un número; tiene que haber algo que discar detrás.
  return n.replaceAll('+', '').isNotEmpty;
}
