import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Switch canónico de la app.
///
/// Apagado: hueco oscuro con hairline y perilla atenuada. Encendido: pista de
/// acento con perilla clara. El estado se lee por VALOR además de por color —
/// la perilla salta de gris apagado a claro — así funciona igual con poca luz
/// y para quien no distingue el ámbar.
///
/// El borde del estado apagado no es decorativo: sin él, la pista oscura se
/// funde con la card y el control desaparece.
class CceSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged; // null => deshabilitado (no togglea)

  /// Color con el que "prende" la pista. Default: el acento del sistema.
  final Color? accent;
  const CceSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  /// Ancho del control. Público para que una fila que NO lo muestra pueda
  /// reservar su lugar y mantener alineado lo que tiene al lado (RoomCard).
  static const double width = 50;
  static const double _h = 30;
  static const double _knob = 24;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final Color on = accent ?? CceColors.accent;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CceRadii.pill),
            color: value ? on : CceColors.surfaceSunken,
            border: Border.all(
              color: value ? Colors.transparent : CceColors.strokeStrong,
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _knob,
                height: _knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? CceColors.textPrimary : CceColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El hueco del switch, SIN perilla: lo que ve una fila que no tiene nada que
/// togglear (una habitación sin luces, en [RoomCard]).
///
/// Vive acá y no en la card a propósito: toma la pista prestada del control de
/// arriba — mismo [CceSwitch.width], mismo alto, mismo radio, mismo relleno
/// ([CceColors.surfaceSunken]) y mismo hairline ([CceColors.strokeStrong]) —
/// para que el día que el switch cambie de medida o de color el riel vacío
/// cambie con él. Dibujado a mano en la card, se irían separando en silencio.
///
/// NO es un switch deshabilitado. [CceSwitch] con `onChanged: null` baja la
/// opacidad al 40% y DEJA la perilla puesta: dice "el control existe pero está
/// bloqueado un momento". Acá el control no existe, y la ausencia de la perilla
/// es todo el mensaje — a opacidad plena, porque el riel es tan real como el de
/// la fila de al lado. Tampoco se confunde con APAGADO, que sí tiene perilla
/// (gris, a la izquierda).
///
/// Es inerte: sin GestureDetector, sin animación y sin estado. Para un lector
/// de pantalla es una etiqueta, no un control: un óvalo vacío no dice nada por
/// sí solo, así que lo dice [semanticLabel].
class CceSwitchEmptyTrack extends StatelessWidget {
  const CceSwitchEmptyTrack({super.key, this.semanticLabel = 'Sin luces'});

  /// Lo que anuncia el lector de pantalla en lugar del control ausente.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      container: true,
      child: Container(
        width: CceSwitch.width,
        height: CceSwitch._h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CceRadii.pill),
          color: CceColors.surfaceSunken,
          border: Border.all(color: CceColors.strokeStrong, width: 1),
        ),
      ),
    );
  }
}
