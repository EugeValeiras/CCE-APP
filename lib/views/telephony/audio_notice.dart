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
    this.color,
  });

  final PhoneStatus status;

  /// ¿Esta app tiene el audio tomado ahora mismo?
  final bool onThisPhone;

  /// Acción a la derecha del aviso (traer el audio). Va acá y no en otro
  /// bloque porque el aviso plantea la pregunta y el botón es la respuesta.
  final Widget? action;

  /// Superficie. Sobre un sheet (que ya es `surface`) va un escalón arriba.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = onThisPhone ? CceColors.ok : CceColors.accent;
    return PhoneSurface(
      color: this.color,
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
  const AudioRouteLine(
    this.text, {
    super.key,
    this.onThisPhone = false,
    this.stalled = false,
  });

  /// Versión de la llamada EN CURSO: dice dónde está saliendo la voz.
  ///
  /// Con el audio tomado por esta app ([onThisPhone]) el mensaje es el
  /// contrario, y es igual de necesario: sin él, alguien con el audio tomado
  /// seguiría leyendo que no se escucha por el celular. Y con el audio tomado
  /// pero el motor parado ([stalled], CCE#18) es la TERCERA verdad: está
  /// ruteado acá y no suena en ningún lado — decir "estás hablando por el
  /// celular" sería exactamente la mentira que el #18 vino a sacar.
  AudioRouteLine.forCall(
    PhoneStatus status, {
    super.key,
    this.onThisPhone = false,
    this.stalled = false,
  }) : text = stalled
            ? 'El audio está en este celular, pero ahora no suena: hasta que '
                'vuelva, no lo escucha nadie.'
            : onThisPhone
                ? 'Estás hablando por el celular. Soltá el audio para '
                    'devolverlo al teléfono de la casa.'
                : '${status.audioNotice} ${status.audioRouteLabel}.';

  /// Versión de la ENTRANTE. Desde CCE#20 atender TRAE el audio al celular
  /// (se toma dentro del gesto, antes del `answer`, como en el dashboard), así
  /// que en el caso normal no hay nada que ofrecer: se dice que vas a hablar
  /// por acá. Las otras tres verdades siguen haciendo falta: ya tomado
  /// ([onThisPhone]), tomado pero mudo ([stalled], CCE#18) y traerlo FALLÓ
  /// ([failed]: micrófono negado, red, desalojo) — la única en la que vuelve a
  /// tener sentido el botón de traerlo, y la card lo muestra sólo ahí.
  const AudioRouteLine.forIncoming({
    super.key,
    this.onThisPhone = false,
    this.stalled = false,
    bool failed = false,
  }) : text = stalled
            ? 'El audio está en este celular, pero ahora no suena. Si atendés, '
                'reintentá o soltalo para que suene en el teléfono de la casa.'
            : onThisPhone
                ? 'Si atendés, hablás y escuchás por el celular. Soltá el audio '
                    'para que la llamada suene en el teléfono de la casa.'
                : failed
                    ? 'El audio no está en este celular. Al atender se intenta '
                        'traerlo; si no se puede, hablás por el teléfono de la '
                        'casa.'
                    : 'Al atender, el audio viene a este celular: hablás y '
                        'escuchás por acá. Después podés soltarlo para que '
                        'suene en el teléfono de la casa.';

  final String text;

  /// ¿Esta app tiene el audio tomado? Cambia el ícono y su color, además del
  /// texto que eligió el constructor.
  final bool onThisPhone;

  /// ¿Tomado pero mudo? Manda sobre [onThisPhone]: ícono de silencio en rojo.
  final bool stalled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centrado con la primera línea del texto.
          padding: const EdgeInsets.only(top: 1),
          child: stalled
              ? const Icon(Icons.volume_off, size: 16, color: CceColors.danger)
              : CceIcon(
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
