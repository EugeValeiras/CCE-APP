import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import 'phone_surface.dart';

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
/// Con el #14 cambió CUÁNDO aparece, no lo que dice: en reposo la pantalla es
/// teclado, y el aviso entra al tocar el primer dígito —que es el momento en
/// que la pregunta "¿por dónde voy a escuchar?" existe— con la acción de traer
/// el audio al lado ([action]). Ya no es una card naranja aparte: es una
/// [PhoneSurface] más, y el color lo lleva el título, no el fondo.
///
/// Dos formas del mismo aviso:
///  - [AudioRouteNotice]: bloque bajo el número, para saber qué esperar ANTES
///    de discar.
///  - [AudioRouteLine]: línea dentro de la card de la llamada, para el momento
///    en que el usuario se pregunta por qué no escucha nada.
class AudioRouteNotice extends StatelessWidget {
  const AudioRouteNotice({
    super.key,
    required this.status,
    this.onThisPhone = false,
    this.action,
  });

  final PhoneStatus status;

  /// ¿Esta app tiene el audio tomado ahora mismo?
  final bool onThisPhone;

  /// Acción a la derecha del aviso (traer el audio). Va acá y no en otro
  /// bloque porque el aviso plantea la pregunta y el botón es la respuesta.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = onThisPhone ? CceColors.ok : CceColors.accent;
    return PhoneSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: CceIcon(
                  onThisPhone ? CceIcons.volume2 : CceIcons.speaker,
                  size: 18,
                  color: color,
                ),
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
                          ? 'Vas a hablar y escuchar por el celular. Si soltás '
                              'el audio, la voz vuelve al teléfono de la casa.'
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
          // El botón debajo y no al costado: el aviso son dos o tres renglones
          // a todo el ancho, y apretarlo contra un botón lo dejaba en cinco.
          if (action != null) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [action!]),
          ],
        ],
      ),
    );
  }
}

/// Línea compacta del aviso, para meter dentro de la card de la llamada.
///
/// Es una fila (ícono + texto), no una caja: la card que la contiene ya es la
/// superficie, y una caja adentro de otra era parte del ruido del #14.
class AudioRouteLine extends StatelessWidget {
  const AudioRouteLine(this.text, {super.key, this.onThisPhone = false});

  /// Versión de la llamada EN CURSO: dice dónde está saliendo la voz.
  ///
  /// Con el audio tomado por esta app ([onThisPhone]) el mensaje es el
  /// contrario, y es igual de necesario: sin él, alguien con el audio tomado
  /// seguiría leyendo que no se escucha por el celular.
  AudioRouteLine.forCall(PhoneStatus status, {super.key, this.onThisPhone = false})
      : text = onThisPhone
            ? 'Estás hablando por el celular. Soltá el audio para devolverlo al '
                'teléfono de la casa.'
            : '${status.audioNotice} ${status.audioRouteLabel}.';

  /// Versión de la ENTRANTE: atender desde la app no trae el audio al celular
  /// por sí solo — hay que tomarlo, antes o después de atender. Y si ya está
  /// tomado, hay que decir eso: con el audio acá, "hablás por el teléfono de
  /// la casa" sería mentira.
  const AudioRouteLine.forIncoming({super.key, this.onThisPhone = false})
      : text = onThisPhone
            ? 'Si atendés, hablás y escuchás por el celular. Soltá el audio '
                'para que la llamada suene en el teléfono de la casa.'
            : 'Si atendés, hablás por el teléfono de la casa: para escuchar '
                'por el celular hay que traer el audio acá.';

  final String text;

  /// ¿Esta app tiene el audio tomado? Cambia el ícono y su color, además del
  /// texto que eligió el constructor.
  final bool onThisPhone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centrado con la primera línea del texto.
          padding: const EdgeInsets.only(top: 1),
          child: CceIcon(
            onThisPhone ? CceIcons.volume2 : CceIcons.speaker,
            size: 16,
            color: onThisPhone ? CceColors.ok : CceColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: CceText.caption.copyWith(color: CceColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
