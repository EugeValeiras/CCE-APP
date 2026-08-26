import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';

/// EL aviso de la pantalla del teléfono: **dónde se escucha esta llamada**.
///
/// Nació en el issue #10, cuando la respuesta era siempre "en la casa": la
/// llamada salía de verdad y el destino sonaba, pero la voz iba al jack del HAT
/// o al navegador del dashboard, nunca al celular. Quien discaba desde la app y
/// no escuchaba nada concluía que estaba rota.
///
/// Con el #12 el celular **sí** puede llevar el audio, y el aviso se da vuelta
/// según [onThisPhone]: cuando el audio está acá, decir "no vas a escuchar"
/// sería el peor mensaje posible. Sigue siendo criterio de aceptación en las dos
/// direcciones, y por eso vive en widgets propios con tests que lo cubren.
///
/// Dos formas del mismo aviso:
///  - [AudioRouteNotice]: bloque en reposo, para saber qué esperar ANTES de
///    discar.
///  - [AudioRouteLine]: línea dentro de la card de la llamada, para el momento
///    en que el usuario se pregunta por qué no escucha nada.
class AudioRouteNotice extends StatelessWidget {
  const AudioRouteNotice({
    super.key,
    required this.status,
    this.onThisPhone = false,
  });

  final PhoneStatus status;

  /// ¿Esta app tiene el audio tomado ahora mismo?
  final bool onThisPhone;

  @override
  Widget build(BuildContext context) {
    final color = onThisPhone ? CceColors.ok : CceColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: onThisPhone
            ? CceColors.ok.withValues(alpha: 0.12)
            : CceColors.accentWash,
        borderRadius: BorderRadius.circular(CceRadii.control),
        border: Border.all(color: CceColors.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CceIcon(
            onThisPhone ? CceIcons.volume2 : CceIcons.speaker,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  onThisPhone
                      ? 'El audio está en este celular'
                      : 'El audio se queda en la casa',
                  style: CceText.label.copyWith(fontSize: 13, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  onThisPhone
                      ? 'Vas a hablar y escuchar por el celular. Si soltás el '
                          'audio, la voz vuelve al teléfono de la casa.'
                      : 'La llamada sale y el destino suena, pero por el '
                          'celular no vas a escuchar ni hablar. '
                          '${status.audioRouteLabel}.',
                  style: CceText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Línea compacta del aviso, para meter dentro de una card.
class AudioRouteLine extends StatelessWidget {
  const AudioRouteLine(this.text, {super.key});

  /// Versión de la llamada EN CURSO: dice dónde está saliendo la voz.
  ///
  /// Con el audio tomado por esta app ([onThisPhone]) el mensaje es el
  /// contrario, y es igual de necesario: sin él, alguien con el audio tomado
  /// seguiría leyendo que no se escucha por el celular.
  AudioRouteLine.forCall(PhoneStatus status, {super.key, bool onThisPhone = false})
      : text = onThisPhone
            ? 'Estás hablando por el celular. Soltá el audio para devolverlo al '
                'teléfono de la casa.'
            : '${status.audioNotice} ${status.audioRouteLabel}.';

  /// Versión de la ENTRANTE: atender desde la app no trae el audio al celular
  /// por sí solo — hay que tomarlo, antes o después de atender.
  const AudioRouteLine.forIncoming({super.key})
      : text = 'Si atendés, hablás por el teléfono de la casa: para escuchar '
            'por el celular hay que traer el audio acá.';

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CceColors.accentWash,
        borderRadius: BorderRadius.circular(CceRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CceIcon(CceIcons.speaker, size: 16, color: CceColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: CceText.caption.copyWith(color: CceColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
