import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../services/telephony_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_press.dart';
import 'phone_surface.dart';

/// Lo que el usuario eligió en la libreta.
///
/// Dos caminos a propósito: tocar la fila TRAE el número al teclado (gesto
/// barato, reversible) y el botón verde LLAMA (gesto caro, con confirmación).
/// Un solo camino obligaría a elegir entre un tap que gasta plata sin querer o
/// no poder llamar a un contacto de una.
class ContactPick {
  final PhoneContact contact;

  /// true = llamar ya; false = sólo cargar el número en el teclado.
  final bool callNow;

  const ContactPick(this.contact, {required this.callNow});
}

/// Libreta del backend para discar. El ABM sigue siendo del dashboard: acá no
/// se crea ni se edita nada.
Future<ContactPick?> showContactsSheet(
  BuildContext context,
  TelephonyService telephony,
) {
  // Puede estar ya cacheada: `loadContacts` no vuelve a pedirla si la tiene.
  telephony.loadContacts();
  return showModalBottomSheet<ContactPick>(
    context: context,
    backgroundColor: CceColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (_) => _ContactsSheet(telephony: telephony),
  );
}

class _ContactsSheet extends StatelessWidget {
  const _ContactsSheet({required this.telephony});

  final TelephonyService telephony;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: telephony,
      builder: (context, _) {
        final contacts = telephony.contacts;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CceSpace.lg,
                    0,
                    CceSpace.sm,
                    CceSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Contactos', style: CceText.title),
                            Text(
                              'Tocá uno para cargarlo en el teclado',
                              style: CceText.caption,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => telephony.loadContacts(force: true),
                        icon: const Icon(Icons.refresh, size: 20),
                        color: CceColors.textSecondary,
                        tooltip: 'Actualizar',
                      ),
                    ],
                  ),
                ),
                if (contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CceSpace.lg,
                      CceSpace.sm,
                      CceSpace.lg,
                      CceSpace.xl,
                    ),
                    child: Text(
                      'La libreta está vacía o no se pudo leer. Los contactos '
                      'se crean desde el dashboard.',
                      style: CceText.caption,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        CceSpace.lg,
                        CceSpace.xs,
                        CceSpace.lg,
                        CceSpace.lg,
                      ),
                      itemCount: contacts.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: CceSpace.sm),
                      itemBuilder: (context, i) => _row(context, contacts[i]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, PhoneContact c) {
    // El sheet ya es `surface`: las filas van un escalón arriba o no se ven.
    return PhoneSurface(
      color: CceColors.surfaceHigh,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      onTap: () =>
          Navigator.of(context).pop(ContactPick(c, callNow: false)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.displayName,
                  style: CceText.label.copyWith(
                    fontSize: 15,
                    color: CceColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(c.number, style: CceText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CallButton(
            label: 'Llamar a ${c.displayName}',
            onPressed: () async {
              final ok = await _confirmCall(context, c);
              if (!ok || !context.mounted) return;
              Navigator.of(context).pop(ContactPick(c, callNow: true));
            },
          ),
        ],
      ),
    );
  }

  /// Llamar desde la libreta es UN tap sobre una lista: con la línea activa,
  /// ese tap cuesta plata. Discar desde el teclado no pregunta (el número lo
  /// acabás de escribir), pero acá sí.
  ///
  /// Y dice dónde va a sonar la voz, en la dirección que corresponda: con el
  /// audio ya tomado por este celular, "se queda allá" sería mentira (CCE#12).
  Future<bool> _confirmCall(BuildContext context, PhoneContact c) async {
    final onThisPhone = telephony.audio.isOn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CceRadii.card),
        ),
        title: Text(
          'Llamar a ${c.displayName}',
          style: const TextStyle(color: CceColors.textPrimary),
        ),
        content: Text(
          onThisPhone
              ? '${c.number}\n\nLa llamada sale del teléfono de la casa y el '
                  'audio ya está en este celular: vas a hablar y escuchar '
                  'por acá.'
              : '${c.number}\n\nLa llamada sale del teléfono de la casa y el '
                  'audio se queda allá: por el celular no vas a escuchar ni '
                  'hablar.',
          style: CceText.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Llamar',
              style: TextStyle(color: CceColors.ok),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// El "llamar" de una fila: el mismo tubo verde de la pantalla, en chico y
/// sobre un disco tenue, para que se lea como botón y no como un ícono
/// suelto — pero sin ser un botón de llamar lleno por cada contacto.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: CceNeoPress(
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: CceColors.ok.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: CceColors.ok.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: const CceIcon(CceIcons.phone, size: 18, color: CceColors.ok),
          ),
        ),
      ),
    );
  }
}
