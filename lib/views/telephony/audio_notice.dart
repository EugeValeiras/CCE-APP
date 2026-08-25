import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';

/// EL aviso de la pantalla del teléfono: **la app no lleva audio**.
///
/// La llamada sale de verdad y el teléfono del destino suena, pero la voz va al
/// jack del HAT (en la casa) o al navegador del dashboard — nunca al celular.
/// Quien disca desde la app y no escucha nada concluye que está rota, así que
/// esto es criterio de aceptación del issue #10 y no un detalle de diseño: vive
/// en widgets propios, a la vista, y con tests que lo cubren.
///
/// Dos formas del mismo aviso:
///  - [AudioRouteNotice]: bloque en reposo, para saber qué esperar ANTES de
///    discar.
///  - [AudioRouteLine]: línea dentro de la card de la llamada, para el momento
///    en que el usuario se pregunta por qué no escucha nada.
class AudioRouteNotice extends StatelessWidget {
  const AudioRouteNotice({super.key, required this.status});

  final PhoneStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CceColors.accentWash,
        borderRadius: BorderRadius.circular(CceRadii.control),
        border: Border.all(color: CceColors.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CceIcon(CceIcons.speaker, size: 18, color: CceColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El audio se queda en la casa',
                  style: CceText.label.copyWith(
                    fontSize: 13,
                    color: CceColors.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La llamada sale y el destino suena, pero por el celular no '
                  'vas a escuchar ni hablar. ${status.audioRouteLabel}.',
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

  /// Versión de la llamada EN CURSO: dice que el audio no está en el celular
  /// **y** por dónde está saliendo, que es lo que el issue pide mostrar
  /// mientras la llamada vive.
  AudioRouteLine.forCall(PhoneStatus status, {super.key})
      : text = '${status.audioNotice} ${status.audioRouteLabel}.';

  /// Versión de la ENTRANTE: atender desde la app no trae el audio al celular.
  const AudioRouteLine.forIncoming({super.key})
      : text = 'Si atendés, hablás por el teléfono de la casa: el celular no '
            'lleva el audio.';

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
