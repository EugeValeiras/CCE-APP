/// Etiquetas legibles (ES) para los verbos del catálogo de capabilities.
/// Compartido entre la vista unificada y el resumen de automatizaciones.
const Map<String, String> kVerbLabels = {
  'play': 'Play',
  'pause': 'Pausa',
  'stop': 'Stop',
  'next': 'Siguiente',
  'prev': 'Anterior',
  'clean': 'Limpiar',
  'resume': 'Reanudar',
  'dock': 'Al dock',
  'setCleanMode': 'Modo',
  'setFanSpeed': 'Potencia',
  'cleanRooms': 'Limpiar rooms',
  'setInput': 'Entrada',
  'launchApp': 'App',
  'setChannel': 'Canal',
  'channelUp': 'Canal +',
  'channelDown': 'Canal -',
  'modeTv': 'TV',
  'modeRadio': 'Radio',
  'playPause': 'Play/Pausa',
  'setNightMode': 'Modo noche',
  'setVolume': 'Volumen',
  'volumeUp': 'Volumen +',
  'volumeDown': 'Volumen -',
  'mute': 'Mute',
};

String verbLabel(String verb) => kVerbLabels[verb] ?? verb;
