import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_press.dart';

/// Una tecla del teclado: el dígito y, cuando corresponde, su leyenda.
class _Key {
  final String digit;
  final String legend;

  /// `*` y `#`. No son dígitos: van más grandes y centrados en su círculo, en
  /// vez de compartir la línea base (y el hueco de la leyenda) con los
  /// dígitos de su fila. El `1` NO es una tecla de función: no tiene letras,
  /// pero es un dígito y tiene que quedar a la altura del `2` y el `3`.
  final bool isFunction;

  const _Key(this.digit, [this.legend = '']) : isFunction = false;
  const _Key.function(this.digit) : legend = '', isFunction = true;
}

/// La disposición de toda la vida (ITU E.161): el `1` sin letras, el `0` con
/// el `+`, y `*`/`#` pelados.
const List<List<_Key>> _rows = [
  [_Key('1'), _Key('2', 'ABC'), _Key('3', 'DEF')],
  [_Key('4', 'GHI'), _Key('5', 'JKL'), _Key('6', 'MNO')],
  [_Key('7', 'PQRS'), _Key('8', 'TUV'), _Key('9', 'WXYZ')],
  [_Key.function('*'), _Key('0'), _Key.function('#')],
];

/// Proporciones del teclado, en múltiplos del diámetro de una tecla.
///
/// El AIRE es lo que separa un teléfono de una grilla de botones: las teclas
/// no se tocan entre sí, y el hueco horizontal es más generoso que el vertical
/// (una columna de teclas pegadas se lee como una sola pieza vertical).
///
/// El hueco vertical es un PISO: cuando la pantalla le da al teclado más alto
/// del que necesita (en reposo, con los bloques de estado fuera de la mitad de
/// arriba — CCE#14), las filas se separan hasta [_gapYMaxRatio] en vez de
/// dejar el teclado apretado en el medio de un hueco muerto.
const double _gapXRatio = 0.34;
const double _gapYRatio = 0.20;
const double _gapYMaxRatio = 0.42;

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
        // El alto que sobra se reparte entre las filas, hasta el tope.
        final gapY = constraints.maxHeight.isFinite
            ? ((constraints.maxHeight - 4 * size) / 3)
                .clamp(size * _gapYRatio, size * _gapYMaxRatio)
            : size * _gapYRatio;

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
    // dígitos a la misma altura dentro de su círculo, incluido el 1 (que no
    // tiene letras). Las teclas de función no pasan por acá: no tienen
    // leyenda y se centran solas en el círculo ([_functionGlyph]).
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
        final glyphInk = Color.lerp(ink, CceColors.accent, press * 0.5)!;

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
          child: data.isFunction
              ? _functionGlyph(size: size, ink: glyphInk)
              // Red de seguridad: con una tecla en su tamaño mínimo, y según
              // la métrica de la fuente, dígito + leyenda pueden pasarse del
              // círculo por uno o dos píxeles. Antes que una franja de
              // overflow, se achica.
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _glyph(fontSize: size * _digitScale, ink: glyphInk),
                      SizedBox(
                        height: legendBox,
                        child: legend.isEmpty
                            ? null
                            : Text(
                                legend,
                                style: CceText.section.copyWith(
                                  fontSize: legendSize,
                                  fontWeight: isPlus
                                      ? FontWeight.w400
                                      : FontWeight.w600,
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

  Widget _glyph({required double fontSize, required Color ink}) => Text(
    data.digit,
    style: CceText.display.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.0,
      color: ink,
    ),
  );

  /// El `*` y el `#` van más grandes que un dígito, como en el teclado del
  /// iPhone: a tamaño de dígito el asterisco es una mota y el numeral se lee
  /// como un dígito más; los dos son teclas de función y tienen que verse.
  ///
  /// Y van CENTRADOS en el círculo, no en la caja de texto: centrar la caja
  /// deja a los dos flotando arriba, porque la tinta de estos glifos no está
  /// en el medio de su línea. El centrado sale de la métrica del glifo
  /// ([_FunctionGlyph]): se ubica la línea base —que Flutter calcula de la
  /// fuente real— a la distancia del centro que la tinta sube sobre ella.
  /// Es el único ajuste vertical que tienen: ni hueco de leyenda ni offset.
  Widget _functionGlyph({required double size, required Color ink}) {
    final metrics = _FunctionGlyph.of(data.digit);
    final fontSize = size * metrics.scale;
    // El área útil no es el diámetro: el [Container] descuenta su borde como
    // padding. Se centra en lo que la tecla le da, no en el tamaño nominal.
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) => Baseline(
          baseline: constraints.maxHeight / 2 + metrics.inkCenter * fontSize,
          baselineType: TextBaseline.alphabetic,
          child: Center(
            heightFactor: 1.0,
            child: _glyph(fontSize: fontSize, ink: ink),
          ),
        ),
      ),
    );
  }
}

/// Tamaño de fuente de un dígito, en múltiplos del diámetro de la tecla.
const double _digitScale = 0.40;

/// Cómo se dibuja una tecla de función: el tamaño de fuente (en múltiplos del
/// diámetro) y el tramo que ocupa su tinta sobre la línea base, en ems.
///
/// Los tramos son la métrica de los glifos en SF Pro (la fuente del sistema
/// en iOS), medida sobre el glifo dibujado —rasterizado con un [TextPainter]
/// y contando las filas con tinta respecto de la línea base—: los dos cuelgan
/// del tope de las mayúsculas (0.70 em, igual que un dígito), el `#` baja
/// hasta la línea base como un dígito y el asterisco se queda a mitad de
/// camino. Por eso el asterisco necesita más tamaño de fuente para verse
/// igual de grande: su tinta es un tercio de la línea.
class _FunctionGlyph {
  final double scale;
  final double inkTop;
  final double inkBottom;
  const _FunctionGlyph({
    required this.scale,
    required this.inkTop,
    required this.inkBottom,
  });

  static _FunctionGlyph of(String digit) => switch (digit) {
    '*' => const _FunctionGlyph(scale: 0.80, inkTop: 0.70, inkBottom: 0.35),
    '#' => const _FunctionGlyph(scale: 0.56, inkTop: 0.70, inkBottom: 0.0),
    _ => throw ArgumentError.value(digit, 'digit', 'no es tecla de función'),
  };

  /// Centro de la tinta, en ems sobre la línea base.
  double get inkCenter => (inkTop + inkBottom) / 2;
}
