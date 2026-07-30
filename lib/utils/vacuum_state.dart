/// Estado del robot en texto, en un solo lugar (Dart puro, testeable).
///
/// Espejo de `core/vacuum-state.ts` del Dashboard: lo consumen el plano
/// (marcador), el tile, la home card y el VacuumScreen; antes cada superficie
/// tenía su propia tabla y se desincronizaban solas (el tile decía "En base"
/// mientras el plano decía "Lavando la mopa").
///
/// REGLA: se lee `vacuumActivity`, NO `vacuumState`. El segundo sale del
/// cluster RVC de Matter y falla de dos formas — sólo define siete valores
/// (mete cargar, lavar la mopa y vaciarse dentro de 'docked') y se queda
/// pegado: el 2026-07-29 decía 'cleaning' con el robot quieto cargando en la
/// base. `vacuumActivity` lo emite el sidecar leyendo el código real del
/// robot. `vacuumState` queda de fallback para cuando el sidecar no tiene
/// sesión.
library;

import '../models/device.dart';

/// Slug de actividad del sidecar → label español.
const vacuumActivityLabel = {
  'starting': 'Arrancando',
  'cleaning': 'Limpiando',
  'segment_cleaning': 'Limpiando la habitación',
  'zoned_cleaning': 'Limpiando la zona',
  'spot_cleaning': 'Limpieza puntual',
  'going_to_target': 'Moviéndose',
  'returning': 'Volviendo a la base',
  'docking': 'Yendo a la base',
  'going_to_wash': 'Yendo a lavar la mopa',
  'washing_mop': 'Lavando la mopa',
  'emptying_bin': 'Vaciándose',
  'charging': 'Cargando',
  'charge_complete': 'Carga completa',
  'charging_error': 'Problema de carga',
  'paused': 'En pausa',
  'idle': 'En reposo',
  'manual': 'Control manual',
  'remote_control': 'Control remoto',
  'updating': 'Actualizándose',
  'shutting_down': 'Apagándose',
  'offline': 'Sin conexión',
  'error': 'Con error',
};

/// Estados que ocurren DENTRO de una habitación: se les puede poner nombre.
const vacuumRoomAware = {
  'going_to_target',
  'segment_cleaning',
  'cleaning',
  'zoned_cleaning',
  'spot_cleaning',
};

/// Estados en los que el robot está TRABAJANDO (≠ quieto en la base).
const vacuumWorkingActivities = {
  'starting',
  'cleaning',
  'segment_cleaning',
  'zoned_cleaning',
  'spot_cleaning',
  'going_to_target',
  'returning',
  'docking',
  'going_to_wash',
  'washing_mop',
  'emptying_bin',
  'manual',
  'remote_control',
  'paused',
};

/// Fallback de estados de Matter, para cuando el sidecar no tiene sesión.
const _vacuumBusyStates = {'cleaning', 'paused', 'returning'};

/// Texto del estado del robot, o null si no hay nada que decir.
String? vacuumStateLabel(Device d) {
  final act = d.state.vacuumActivity;
  final detalle = act == null ? null : vacuumActivityLabel[act];
  if (detalle != null) {
    // El robot dice en qué habitación está: "Limpiando Kitchen" es mucho más
    // útil que "Limpiando la habitación". El nombre de la cola es el fallback.
    final q = d.state.roomQueue;
    final room = d.state.vacuumRoomName ??
        (q != null && q.current >= 0 && q.current < q.names.length
            ? q.names[q.current]
            : null);
    if (room != null && vacuumRoomAware.contains(act)) {
      return act == 'going_to_target' ? 'Moviéndose a $room' : 'Limpiando $room';
    }
    return detalle;
  }
  return switch (d.state.vacuumState) {
    'cleaning' => 'Limpiando',
    'returning' => 'Volviendo a la base',
    'paused' => 'En pausa',
    'docked' => 'En la base',
    'error' => 'Con error',
    _ => null,
  };
}

/// ¿El robot está trabajando? Cuenta moverse por la casa y las faenas en la
/// base: para el dueño es lo mismo.
///
/// NO mira `state.on`: el robot no usa ese campo —Matter lo maneja por el
/// cluster RVC— y reporta `on: false` incluso limpiando, que es lo que dejaba
/// su marcador gris en el plano.
bool vacuumWorking(Device d) {
  final act = d.state.vacuumActivity;
  // Manda el detalle; vacuumState es el fallback y no se le cree por encima:
  // es el campo que se queda pegado en 'cleaning'.
  if (act != null) return vacuumWorkingActivities.contains(act);
  return _vacuumBusyStates.contains(d.state.vacuumState);
}
