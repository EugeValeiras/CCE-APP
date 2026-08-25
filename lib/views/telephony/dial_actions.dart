import 'package:flutter/material.dart';

import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_press.dart';

/// Diámetro del botón de llamar/colgar. Más grande que una tecla del teclado
/// (tope 70): en esta pantalla es LA acción, y se tiene que ver desde el otro
/// lado de la habitación.
const double kPhoneRoundButtonSize = 76;

/// Lado de los botones satélite (contactos, borrar). Neutros y sin fondo: no
/// compiten con el verde del medio.
const double kPhoneSideButtonSize = 52;

/// La botonera del teclado en reposo: contactos a la izquierda, LLAMAR en el
/// centro, borrar a la derecha.
///
/// El borrar aparece SÓLO cuando hay algo escrito. Un backspace permanente al
/// lado del botón de llamar es una trampa: es el vecino del botón que cuesta
/// plata, y estar ahí apagado no aporta nada. Su lugar queda reservado igual
/// para que el botón de llamar no se mueva cuando aparece.
class DialActions extends StatelessWidget {
  const DialActions({
    super.key,
    required this.hasNumber,
    required this.canDial,
    required this.onContacts,
    required this.onCall,
    required this.onBackspace,
    required this.onClear,
  });

  /// Hay algo escrito (aunque todavía no sea discable).
  final bool hasNumber;

  /// El número alcanza para discar y la línea está libre.
  final bool canDial;

  final VoidCallback? onContacts;
  final VoidCallback onCall;
  final VoidCallback onBackspace;

  /// Long-press del borrar: limpia todo el número.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: kPhoneSideButtonSize,
          child: PhoneSideButton(
            tooltip: 'Contactos',
            onPressed: onContacts,
            child: const CceIcon(CceIcons.users, size: 22),
          ),
        ),
        const SizedBox(width: CceSpace.xl),
        PhoneRoundButton(
          icon: CceIcons.phone,
          color: CceColors.ok,
          label: 'Llamar',
          onPressed: canDial ? onCall : null,
        ),
        const SizedBox(width: CceSpace.xl),
        SizedBox(
          width: kPhoneSideButtonSize,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: hasNumber
                ? PhoneSideButton(
                    tooltip: 'Borrar',
                    onPressed: onBackspace,
                    // Mantener apretado borra todo: escribir 12 dígitos y
                    // tener que borrarlos de a uno es la parte molesta de
                    // cualquier dial pad.
                    onLongPress: onClear,
                    child: const Icon(Icons.backspace_outlined, size: 22),
                  )
                : const SizedBox(
                    width: kPhoneSideButtonSize,
                    height: kPhoneSideButtonSize,
                  ),
          ),
        ),
      ],
    );
  }
}

/// El botón que cuesta plata (o que la corta): grande, circular, aislado del
/// teclado y deshabilitado sin un número discable, para que no se dispare de un
/// roce.
class PhoneRoundButton extends StatelessWidget {
  const PhoneRoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
    this.rotate = false,
  });

  final String icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;

  /// Colgar es el mismo tubo, dado vuelta: es el gesto que todo el mundo
  /// reconoce sin leer la etiqueta.
  final bool rotate;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // Apagado NO es gris: es el mismo botón, atenuado. Un círculo neutro en el
    // lugar del botón de llamar se lee como un hueco en la pantalla.
    final glyph = CceIcon(
      icon,
      size: 30,
      color: enabled ? CceColors.inkOnAmber : color.withValues(alpha: 0.45),
    );

    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: Tooltip(
        message: label,
        child: CceNeoPress(
          onTap: onPressed,
          child: Container(
            width: kPhoneRoundButtonSize,
            height: kPhoneRoundButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? color : color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              boxShadow: enabled
                  ? [...CceShadows.raised, ...CceShadows.glowOn(color)]
                  : null,
            ),
            child: rotate ? Transform.rotate(angle: 2.356, child: glyph) : glyph,
          ),
        ),
      ),
    );
  }
}

/// Acción secundaria al lado del botón de llamar: sin fondo, sólo el glifo.
class PhoneSideButton extends StatelessWidget {
  const PhoneSideButton({
    super.key,
    required this.child,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: tooltip,
      enabled: enabled,
      child: Tooltip(
        message: tooltip,
        child: CceNeoPress(
          onTap: onPressed,
          onLongPress: enabled ? onLongPress : null,
          child: SizedBox(
            width: kPhoneSideButtonSize,
            height: kPhoneSideButtonSize,
            child: IconTheme(
              data: IconThemeData(
                color: enabled ? CceColors.textSecondary : CceColors.textMuted,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
