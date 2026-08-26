import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cce_tokens.dart';
import '../../utils/dial_number.dart';
import 'phone_surface.dart';

/// El visor de la pantalla: la superficie, el número que se está discando y
/// el botón de pegar ADENTRO del campo.
///
/// Es el protagonista de la mitad de arriba (CCE#14): la única cosa que el
/// usuario mira mientras toca el teclado, y antes era la franja más chica y
/// apagada de la pantalla, con el botón de pegar flotando afuera. Ahora es una
/// [PhoneSurface] al escalón de los inputs ([CceColors.surfaceHigh]), con el
/// número como el texto más grande de la pantalla.
///
/// Sólo existe en reposo: durante la llamada el acuse de los tonos DTMF va
/// dentro de la card de la llamada, y el lugar del visor se lo lleva el
/// teclado.
class DialDisplay extends StatelessWidget {
  const DialDisplay({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    this.onChanged,
    this.onPaste,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onPaste;

  /// Alto fijo: el número no lo cambia (se achica él), así que el teclado no
  /// se mueve mientras se disca.
  static const double height = 68;

  /// Ancho del botón de pegar y de su contrapeso del otro lado: es lo que deja
  /// el número CENTRADO en la superficie aunque el botón esté sólo a la
  /// derecha.
  static const double _sideWidth = 48;

  @override
  Widget build(BuildContext context) {
    return PhoneSurface(
      color: CceColors.surfaceHigh,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            const SizedBox(width: _sideWidth),
            Expanded(
              child: DialNumberField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: _sideWidth,
              child: IconButton(
                onPressed: enabled ? onPaste : null,
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                color: CceColors.textTertiary,
                tooltip: 'Pegar un número',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El campo del número: grande, centrado y sin placeholder — el teclado que
/// tiene debajo ya dice qué hacer, y un "Número" en gris ocupando el lugar del
/// número es ruido.
///
/// Es EDITABLE: se escribe con el dial pad, pero también se puede tocar para
/// corregir a mano o pegar con el menú del sistema. Lo que entre por cualquiera
/// de esas vías pasa por [sanitizeDialInput] vía [DialInputFormatter].
///
/// SE ACHICA SOLO. Un número internacional con prefijo (`+5492616260811`) no
/// entra a 34px en un teléfono angosto: antes que cortarlo con puntos
/// suspensivos — un número a medias es inservible — baja la tipografía hasta
/// que entra entero.
///
/// No pinta superficie propia: la pinta [DialDisplay]. Por eso el `filled` del
/// tema de inputs se apaga acá — era lo que dejaba el rectángulo gris sin radio
/// del #14.
class DialNumberField extends StatelessWidget {
  const DialNumberField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  /// Tamaño de reposo: el número es lo más grande de la mitad de arriba.
  static const double maxFontSize = 34;

  /// Piso. Por debajo, un número deja de leerse de un vistazo; a esta altura
  /// entran de sobra los 15 dígitos de un E.164 en la pantalla más angosta.
  static const double minFontSize = 17;

  /// Estilo del número a un tamaño dado. El tracking es PROPORCIONAL para que
  /// el ancho del texto escale linealmente con el tamaño: es lo que hace que
  /// [fontSizeFor] pueda resolver el encaje de una sola pasada.
  static TextStyle styleAt(double fontSize) => CceText.display.copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        letterSpacing: fontSize * 0.04,
        height: 1.2,
      );

  /// El tamaño más grande al que [text] entra entero en [maxWidth].
  static double fontSizeFor(String text, double maxWidth) {
    if (text.isEmpty || maxWidth <= 0) return maxFontSize;
    final painter = TextPainter(
      text: TextSpan(text: text, style: styleAt(maxFontSize)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (painter.width <= maxWidth) return maxFontSize;
    // 0.96 deja lugar para el cursor y para el redondeo del layout: quedar
    // clavado en el ancho exacto es quedar un pelo afuera.
    return (maxFontSize * maxWidth * 0.96 / painter.width)
        .clamp(minFontSize, maxFontSize);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = fontSizeFor(controller.text, constraints.maxWidth);
        return Center(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.phone,
            cursorColor: CceColors.accent,
            inputFormatters: const [DialInputFormatter()],
            onChanged: onChanged,
            style: styleAt(size),
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        );
      },
    );
  }
}

/// Todo lo que entra al campo pasa por [sanitizeDialInput], venga del dial pad,
/// del teclado del sistema o de un pegado. El cursor se lleva al final sólo
/// cuando el texto CAMBIÓ al limpiarlo: si no, se respeta la selección del
/// usuario para que pueda editar en el medio.
class DialInputFormatter extends TextInputFormatter {
  const DialInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = sanitizeDialInput(newValue.text);
    if (clean == newValue.text) return newValue;
    return TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
  }
}
