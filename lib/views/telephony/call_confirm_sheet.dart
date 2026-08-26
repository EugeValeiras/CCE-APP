import 'package:flutter/material.dart';

import '../../services/telephony_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import 'audio_notice.dart';

/// Qué eligió el usuario en el aviso previo a la llamada.
enum CallChoice {
  /// Tomar el audio en este celular y después discar.
  takeAudioAndCall,

  /// Discar sin tocar el audio: suena en la casa. Sirve para hacer sonar un
  /// número a propósito, sin intención de hablar.
  callAnyway,
}

/// El aviso ANTES de discar, cuando el audio no está en este celular. Es el
/// espejo en la app de lo que CCE#15 hace en el dashboard.
///
/// Hasta acá el aviso estaba a la vista mientras se discaba, pero el momento
/// en que importa es el de apretar LLAMAR: la llamada sale, el destino suena,
/// y el usuario que no escucha nada da la app por rota. Acá se le pregunta
/// antes, y se aprovecha el gesto: elegir "Escuchar acá y llamar" trae el
/// audio y disca de una.
///
/// Reglas heredadas de #15:
///  - Con el audio ya en este celular **no aparece**: agregar un toque al caso
///    normal sería un retroceso. El que llama decide si lo muestra.
///  - Las dos opciones discan: nunca deja al usuario sin llamar.
///  - Cerrar sin elegir no disca nada (`null`).
Future<CallChoice?> showCallConfirmSheet(
  BuildContext context, {
  required TelephonyService telephony,
  required String who,
  String? number,
}) {
  return showModalBottomSheet<CallChoice>(
    context: context,
    backgroundColor: CceColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (_) => _CallConfirmSheet(
      telephony: telephony,
      who: who,
      number: number,
    ),
  );
}

class _CallConfirmSheet extends StatelessWidget {
  const _CallConfirmSheet({
    required this.telephony,
    required this.who,
    this.number,
  });

  final TelephonyService telephony;
  final String who;
  final String? number;

  @override
  Widget build(BuildContext context) {
    // Con un contacto el número va debajo del nombre; discando a mano, el
    // número ES el título y no hay que repetirlo.
    final showNumber = number != null && number!.isNotEmpty && number != who;

    return SafeArea(
      // En un teléfono el sheet entra entero; en una pantalla baja (apaisado)
      // scrollea antes que desbordar.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          CceSpace.lg,
          0,
          CceSpace.lg,
          CceSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: CceColors.ok.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const CceIcon(
                    CceIcons.phoneOutgoing,
                    size: 20,
                    color: CceColors.ok,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Llamar a $who',
                        style: CceText.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showNumber) ...[
                        const SizedBox(height: 2),
                        Text(number!, style: CceText.caption),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: CceSpace.lg),
            // EL aviso, tal cual: es el mismo bloque que se ve al discar.
            AudioRouteNotice(
              status: telephony.status,
              color: CceColors.surfaceHigh,
            ),
            const SizedBox(height: CceSpace.lg),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(CallChoice.takeAudioAndCall),
              style: FilledButton.styleFrom(
                backgroundColor: CceColors.accent,
                foregroundColor: CceColors.inkOnAmber,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CceRadii.control),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const CceIcon(
                CceIcons.volume2,
                size: 18,
                color: CceColors.inkOnAmber,
              ),
              label: const Text('Escuchar acá y llamar'),
            ),
            const SizedBox(height: CceSpace.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(CallChoice.callAnyway),
              style: FilledButton.styleFrom(
                backgroundColor: CceColors.surfaceHigh,
                foregroundColor: CceColors.textPrimary,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: CceColors.stroke),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CceRadii.control),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Llamar igual'),
            ),
            const SizedBox(height: CceSpace.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: CceColors.textSecondary,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
