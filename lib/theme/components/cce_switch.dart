import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Switch canónico de la app en clave NEUMÓRFICA: pista HUNDIDA (neoSunken +
/// inner-shadow) y perilla CONVEXA que sobresale (gradiente + sombra neo).
/// Encendido: la perilla se corre a la derecha, se ilumina y suma un glow
/// suave. Mismo contrato de API (value / onChanged); onChanged null = disabled.
class CceSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged; // null => deshabilitado (no togglea)
  const CceSwitch({super.key, required this.value, required this.onChanged});

  static const double _w = 50;
  static const double _h = 28;
  static const double _knob = 22;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
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
            // Pista hundida (well) en la goma.
            color: CceColors.neoSunken,
            borderRadius: BorderRadius.circular(999),
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
                  // Perilla convexa: encendida más clara (neoLight), apagada neoBase.
                  gradient: CceGradients.convex(
                    value ? CceColors.neoLight : CceColors.neoBase,
                  ),
                  boxShadow: [
                    ...CceShadows.neo(blur: 5, offset: 2),
                    if (value)
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.22),
                        blurRadius: 10,
                        spreadRadius: -1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
