import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_press.dart';

/// Una tecla del teclado: el dígito y, cuando corresponde, su leyenda.
class _Key {
  final String digit;
  final String legend;
  const _Key(this.digit, [this.legend = '']);
}

/// La disposición de toda la vida (ITU E.161): el `1` sin letras, el `0` con
/// el `+`, y `*`/`#` pelados.
const List<List<_Key>> _rows = [
  [_Key('1'), _Key('2', 'ABC'), _Key('3', 'DEF')],
  [_Key('4', 'GHI'), _Key('5', 'JKL'), _Key('6', 'MNO')],
  [_Key('7', 'PQRS'), _Key('8', 'TUV'), _Key('9', 'WXYZ')],
  [_Key('*'), _Key('0'), _Key('#')],
];

/// Proporciones del teclado, en múltiplos del diámetro de una tecla.
///
/// El AIRE es lo que separa un teléfono de una grilla de botones: las teclas
/// no se tocan entre sí, y el hueco horizontal es más generoso que el vertical
/// (una columna de teclas pegadas se lee como una sola pieza vertical).
const double _gapXRatio = 0.34;
const double _gapYRatio = 0.20;

/// Tope y piso del diámetro. El tope evita platos en tablet — y deja al botón
/// de llamar (76) como el elemento más grande de la pantalla, que es lo que
/// tiene que ser. El piso evita un diámetro absurdo cuando el alto que sobra
/// es mínimo: ahí entra a jugar el [FittedBox].
const double _maxKey = 70.0;
const double _minKey = 34.0;

/// Teclado telefónico. Se usa para dos cosas distintas con el mismo gesto:
/// escribir el número antes de llamar, y mandar tonos DTMF durante una llamada
/// (que es lo que permite navegar un menú de voz desde el celular aunque el
/// audio del menú esté sonando en la casa).
///
/// El `+` se saca con un long-press del `0`, como en cualquier teléfono. En
/// modo DTMF no aplica: un `+` no es un tono, así que [plusOnZero] lo apaga.
///
/// Se dimensiona solo al espacio que le den ([LayoutBuilder]): las teclas son
/// tan grandes como entren, con un tope para que en tablet no queden platos.
class DialPad extends StatelessWidget {
  const DialPad({
    super.key,
    required this.onKey,
    this.plusOnZero = true,
    this.enabled = true,
  });

  /// Recibe el carácter tocado ('0'-'9', '*', '#', o '+' del long-press).
  final ValueChanged<String> onKey;

  /// Long-press del `0` = `+` (prefijo internacional). Apagado en DTMF.
  final bool plusOnZero;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final byWidth = constraints.maxWidth / (3 + 2 * _gapXRatio);
        // Sin alto acotado (dentro de un scroll) el ancho manda: es el caso de
        // las pantallas muy bajas, donde igual no queremos teclas gigantes.
        final byHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight / (4 + 3 * _gapYRatio)
            : byWidth;
        // Si ni con el piso entra, el FittedBox de abajo achica el teclado
        // entero en vez de dejarlo desbordar.
        final size =
            math.min(math.min(byWidth, byHeight), _maxKey).clamp(_minKey, _maxKey);
        final gapX = size * _gapXRatio;
        final gapY = size * _gapYRatio;

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < _rows.length; r++) ...[
                  if (r > 0) SizedBox(height: gapY),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < _rows[r].length; c++) ...[
                        if (c > 0) SizedBox(width: gapX),
                        _DialKey(
                          data: _rows[r][c],
                          size: size,
                          enabled: enabled,
                          onKey: onKey,
                          // El '0' es la única tecla con segunda función.
                          longPressValue: plusOnZero && _rows[r][c].digit == '0'
                              ? '+'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({
    required this.data,
    required this.size,
    required this.enabled,
    required this.onKey,
    this.longPressValue,
  });

  final _Key data;
  final double size;
  final bool enabled;
  final ValueChanged<String> onKey;
  final String? longPressValue;

  @override
  Widget build(BuildContext context) {
    final legend = longPressValue ?? data.legend;
    final ink = enabled ? CceColors.textPrimary : CceColors.textMuted;

    // La leyenda RESERVA su alto aunque esté vacía: es lo que deja todos los
    // dígitos a la misma altura dentro de su círculo, incluidos el 1, el * y
    // el #. Sin eso, la fila de abajo se lee corrida respecto de las otras.
    //
    // El `+` del 0 no es una leyenda de letras sino un CARÁCTER que se disca:
    // va más grande, o a tamaño de letras no se ve y nadie descubre el
    // long-press que lo saca.
    final isPlus = legend == '+';
    final legendSize =
        isPlus ? size * 0.22 : math.max(7.5, size * 0.125);
    final legendBox = math.max(7.5, size * 0.125) * 1.45;

    return CceNeoPress(
      // El háptico del teclado es más liviano que el del resto de la app: se
      // dispara doce veces seguidas mientras se disca.
      haptic: false,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onKey(data.digit);
            }
          : null,
      onLongPress: enabled && longPressValue != null
          ? () {
              HapticFeedback.mediumImpact();
              onKey(longPressValue!);
            }
          : null,
      builder: (context, t) {
        // `t` es la presión (0 en reposo → 1 apretada): el realce entra rápido
        // y se apaga solo, así que el toque se ve además de sentirse.
        final press = enabled ? t : 0.0;
        final base = enabled ? CceColors.surfaceHigh : CceColors.surface;
        final fill = Color.alphaBlend(
          CceColors.accentWash.withValues(alpha: 0.10 * press),
          Color.lerp(base, CceColors.surfaceTop, press)!,
        );

        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: Color.lerp(CceColors.stroke, CceColors.strokeStrong, press)!,
            ),
            boxShadow: enabled ? CceShadows.raised : null,
          ),
          // Red de seguridad: con una tecla en su tamaño mínimo, y según la
          // métrica de la fuente, dígito + leyenda pueden pasarse del círculo
          // por uno o dos píxeles. Antes que una franja de overflow, se achica.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _digit(size: size, ink: Color.lerp(ink, CceColors.accent, press * 0.5)!),
                SizedBox(
                  height: legendBox,
                  child: legend.isEmpty
                      ? null
                      : Text(
                          legend,
                          style: CceText.section.copyWith(
                            fontSize: legendSize,
                            fontWeight: isPlus ? FontWeight.w400 : FontWeight.w600,
                            letterSpacing: isPlus ? 0 : legendSize * 0.14,
                            height: isPlus ? 1.0 : 1.35,
                            color: enabled
                                ? CceColors.textTertiary
                                : CceColors.textMuted,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _digit({required double size, required Color ink}) {
    final text = Text(
      data.digit,
      style: CceText.display.copyWith(
        fontSize: size * 0.40,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.0,
        color: ink,
      ),
    );
    // El asterisco se dibuja arriba de la línea base (no baja hasta ella como
    // un dígito), así que sin bajarlo queda flotando contra el borde de la
    // tecla en vez de centrado, que es como se ve en un teléfono.
    return data.digit == '*'
        ? Transform.translate(offset: Offset(0, size * 0.07), child: text)
        : text;
  }
}
