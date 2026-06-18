import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Switch canónico de la app en clave NEUMÓRFICA: pista HUNDIDA (neoSunken +
/// inner-shadow) y perilla CONVEXA que sobresale (gradiente + sombra neo).
/// Encendido: la pista PRENDE con el color [accent] (p. ej. el del ícono de la
/// card) y la perilla se corre a la derecha. SIN glow que se derrame hacia
/// afuera (la luz queda contenida en la pista). Mismo contrato de API
/// (value / onChanged); onChanged null = disabled.
class CceSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged; // null => deshabilitado (no togglea)
  /// Color con el que "prende" la pista (default: ámbar cálido).
  final Color? accent;
  const CceSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  static const double _w = 50;
  static const double _h = 28;
  static const double _knob = 22;
  static const double _pad = 3;
  static const Color _defaultAccent = Color(0xFFE3A340);

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final Color on = accent ?? _defaultAccent;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            // Apagado: pista hundida (well) oscura. Encendido: la pista PRENDE
            // con el color del ícono (accent). La luz NO sale del botón: sólo
            // la sombra interna (contenida), sin glow externo.
            color: value ? on : CceColors.neoSunken,
            boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: Container(
                width: _knob,
                height: _knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Perilla convexa: encendida blanca, apagada neoBase. Sólo su
                  // relieve neo (contenido); sin glow hacia afuera.
                  gradient: CceGradients.convex(
                    value ? Colors.white : CceColors.neoBase,
                  ),
                  boxShadow: CceShadows.neo(blur: 5, offset: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
