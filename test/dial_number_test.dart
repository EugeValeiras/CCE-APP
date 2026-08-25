// Normalización de lo que se disca desde el dial pad de la app.
//
// Lo que protege: un número pegado de otra app (WhatsApp, un contacto, una
// web) llega con espacios, guiones, paréntesis o un `tel:` adelante. Nada de
// eso se puede mandar al módem — pero rechazar el pegado sería peor, porque
// pegar un número es un criterio de aceptación del issue #10. Y del otro lado
// está el gasto: la línea está activa, así que un toque suelto NO puede
// convertirse en una llamada.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/dial_number.dart';

void main() {
  group('sanitizeDialInput', () {
    test('un número copiado con formato queda discable', () {
      expect(sanitizeDialInput('+54 9 (261) 626-0811'), '+5492616260811');
      expect(sanitizeDialInput('  261 626 0811  '), '2616260811');
    });

    test('el + sólo sobrevive al principio', () {
      // Un '+' en el medio era basura del formato original, no un prefijo.
      expect(sanitizeDialInput('+549+261+6260811'), '+5492616260811');
      expect(sanitizeDialInput('261+6260811'), '2616260811');
    });

    test('los códigos de operador se conservan enteros', () {
      // `*2447` y `*234#` son números reales de la línea: si el saneado se
      // comiera el '*' o el '#', el dial pad no podría discarlos.
      expect(sanitizeDialInput('*2447'), '*2447');
      expect(sanitizeDialInput('*234#'), '*234#');
    });

    test('links tel: y callto:', () {
      expect(sanitizeDialInput('tel:+5492616260811'), '+5492616260811');
      expect(sanitizeDialInput('TEL:2616260811'), '2616260811');
      expect(sanitizeDialInput('callto:%2B5492616260811'), '+5492616260811');
    });

    test('el texto sin nada discable queda vacío', () {
      expect(sanitizeDialInput('llamame'), '');
      expect(sanitizeDialInput(''), '');
    });
  });

  group('isDialable', () {
    test('acepta lo que el módem puede discar', () {
      expect(isDialable('+5492616260811'), isTrue);
      expect(isDialable('*2447'), isTrue);
      expect(isDialable('911'), isTrue);
      expect(isDialable('261 626 0811'), isTrue);
    });

    test('frena el toque accidental', () {
      // Con la línea activa, discar cuesta plata: una o dos teclas sueltas no
      // alcanzan para mandar una llamada.
      expect(isDialable(''), isFalse);
      expect(isDialable('1'), isFalse);
      expect(isDialable('26'), isFalse);
      expect(isDialable('+'), isFalse);
      expect(isDialable('llamame'), isFalse);
    });
  });
}
