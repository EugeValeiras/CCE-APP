import '../../services/devices_service.dart';

/// QUIÉN LO HIZO, en castellano (CCE#75).
///
/// El backend manda el actor DECLARADO tal como nació en el borde:
/// `automation:auto_mq85ppkv1jqiphvn3fj`, `user:app`, `alexa`,
/// `system:power-restore`. Nada de eso se le muestra a nadie crudo: un id de
/// automatización no le dice al dueño de la casa qué prendió la luz.
///
/// Funciones puras (no tocan estado ni UI) para poder testear la traducción
/// sola, que es donde vive el riesgo de mostrar un identificador.

/// Id de la automatización si el actor es una, si no null. Es lo que decide si
/// la fila puede ENLAZAR a la automatización que causó el cambio.
String? automationIdOfActor(String? actor) {
  if (actor == null || !actor.startsWith('automation:')) return null;
  final id = actor.substring('automation:'.length).trim();
  return id.isEmpty ? null : id;
}

/// Frase con preposición incluida: «por «Prender Living con Living
/// Movimiento»», «desde la app», «por Alexa». null cuando no hay actor — y esa
/// ausencia también se cuenta: significa que el cambio pasó solo.
String? actorLabel(String? actor, DevicesService devices) {
  if (actor == null || actor.isEmpty) return null;

  final autoId = automationIdOfActor(actor);
  if (autoId != null) {
    // automationName cae al id cuando la automatización ya no existe (se
    // borró después del evento). Antes que mostrar `auto_mq85…`, se dice que
    // fue una automatización y listo.
    final name = devices.automationName(autoId);
    if (name == autoId) return 'por una automatización';
    return 'por «$name»';
  }

  switch (actor) {
    case 'user:app':
      return 'desde la app';
    case 'user:dashboard':
      return 'desde el panel';
    case 'user:cli':
    case 'cli':
      return 'desde la terminal';
    case 'user':
      return 'por vos';
    case 'alexa':
      return 'por Alexa';
    case 'api:anon':
      return 'desde la API';
  }

  // Políticas del sistema (`system:power-restore`): el nombre de la policy es
  // de adentro, así que se dice el sujeto y no la sigla.
  if (actor.startsWith('system:') || actor == 'system') return 'por el sistema';
  if (actor.startsWith('user:')) return 'por vos';

  // Lo que no se reconoce se muestra tal cual: es preferible a inventarle un
  // nombre, y deja ver que hay un actor nuevo que traducir.
  return 'por $actor';
}
