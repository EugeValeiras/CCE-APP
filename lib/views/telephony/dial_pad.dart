import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_press.dart';

/// Una tecla del teclado: el dígito y, cuando corresponde, su leyenda.
class _Key {
  final String digit;
  final String legend;
  const _Key(this.digit, [this.legend = '']);
}

const List<List<_Key>> _rows = [
  [_Key('1'), _Key('2', 'ABC'), _Key('3', 'DEF')],
  [_Key('4', 'GHI'), _Key('5', 'JKL'), _Key('6', 'MNO')],
  [_Key('7', 'PQRS'), _Key('8', 'TUV'), _Key('9', 'WXYZ')],
  [_Key('*'), _Key('0'), _Key('#')],
];

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
        const gap = 12.0;
        final byWidth = (constraints.maxWidth - gap * 2) / 3;
        // Sin alto acotado (dentro de un scroll) el ancho manda: es el caso de
        // las pantallas muy bajas, donde igual no queremos teclas gigantes.
        final byHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - gap * 3) / 4
            : byWidth;
        // El piso evita un diámetro absurdo (o negativo) cuando el alto que
        // sobra es mínimo; el FittedBox de abajo se encarga de que, si ni así
        // entra, el teclado se achique entero en vez de desbordar.
        final size =
            math.min(math.min(byWidth, byHeight), 76.0).clamp(34.0, 76.0);

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < _rows.length; r++) ...[
                  if (r > 0) const SizedBox(height: gap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < _rows[r].length; c++) ...[
                        if (c > 0) const SizedBox(width: gap),
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

    return CceNeoPress(
      onTap: enabled ? () => onKey(data.digit) : null,
      onLongPress: enabled && longPressValue != null
          ? () => onKey(longPressValue!)
          : null,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? CceColors.surfaceHigh : CceColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: CceColors.stroke),
          boxShadow: enabled ? CceShadows.raised : null,
        ),
        // Red de seguridad: con una tecla en su tamaño mínimo, y según la
        // métrica de la fuente, dígito + leyenda pueden pasarse del círculo por
        // uno o dos píxeles. Antes que una franja de overflow, se achica.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.digit,
                style: TextStyle(
                  fontSize: size * 0.42,
                  height: 1.05,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  color: ink,
                ),
              ),
              if (legend.isNotEmpty)
                Text(
                  legend,
                  style: TextStyle(
                    fontSize: math.max(8, size * 0.14),
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color:
                        enabled ? CceColors.textTertiary : CceColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
