import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../services/telephony_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';

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
                  padding: EdgeInsets.fromLTRB(
                    CceSpace.lg,
                    0,
                    CceSpace.lg,
                    CceSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('Contactos', style: CceText.title)),
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
                    padding: EdgeInsets.fromLTRB(
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
                      padding: EdgeInsets.fromLTRB(
                        CceSpace.lg,
                        0,
                        CceSpace.lg,
                        CceSpace.lg,
                      ),
                      itemCount: contacts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
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
    return CceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  style: CceText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(c.number, style: CceText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () async {
              final ok = await _confirmCall(context, c);
              if (!ok || !context.mounted) return;
              Navigator.of(context).pop(ContactPick(c, callNow: true));
            },
            icon: const CceIcon(CceIcons.phone, size: 20, color: CceColors.ok),
            tooltip: 'Llamar a ${c.displayName}',
          ),
        ],
      ),
    );
  }

  /// Llamar desde la libreta es UN tap sobre una lista: con la línea activa,
  /// ese tap cuesta plata. Discar desde el teclado no pregunta (el número lo
  /// acabás de escribir), pero acá sí.
  Future<bool> _confirmCall(BuildContext context, PhoneContact c) async {
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
          '${c.number}\n\nLa llamada sale del teléfono de la casa y el audio '
          'se queda allá: por el celular no vas a escuchar ni hablar.',
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
