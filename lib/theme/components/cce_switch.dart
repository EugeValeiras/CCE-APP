import 'package:flutter/material.dart';

/// Switch canónico de la app (CONTRATO: tamaño = natural de Switch.adaptive,
/// SIN SizedBox/FittedBox/Transform). Look Hue: track activo blanco@0.45,
/// thumb siempre blanco. Es el recipe que ya usaba la card del JBL.
///
/// Nota de paridad iOS: `activeColor` se pasa además de `activeTrackColor`
/// porque en `CupertinoSwitch` (lo que rinde `Switch.adaptive` en iOS) el
/// track activo se controla por `activeColor` en versiones de Flutter donde
/// `activeTrackColor` no se propaga al track Cupertino.
class CceSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged; // null => deshabilitado (no togglea)
  const CceSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeColor: Colors.white.withValues(alpha: 0.45),
      activeTrackColor: Colors.white.withValues(alpha: 0.45),
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
    );
  }
}
