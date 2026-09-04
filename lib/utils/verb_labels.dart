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
  'setTargetTemp': 'Temperatura',
  'setPower': 'Encendido',
  'setTempMode': 'Modo',
  // CCE#101 — como el dueño piensa la acción: prender + objetivo que caliente,
  // y apagar.
  'startHeating': 'Calentar',
  'stopHeating': 'Dejar de calentar',
  // CCE#100 — la luz con modos y escenas propias (Hexagon).
  'setMode': 'Modo',
  'setScene': 'Escena',
  'setVolume': 'Volumen',
  'volumeUp': 'Volumen +',
  'volumeDown': 'Volumen -',
  'mute': 'Mute',
};

String verbLabel(String verb) => kVerbLabels[verb] ?? verb;

/// Etiquetas (ES) de los modos del termostato (enum THERMOSTAT_TEMP_MODES).
const Map<String, String> kTempModeLabels = {
  'Manual': 'Manual',
  'Program': 'Programa',
};

String tempModeLabel(String mode) => kTempModeLabels[mode] ?? mode;

/// Etiquetas (ES) de los modos de una luz con `light_mode` (Tuya `work_mode`).
///
/// El valor que VIAJA es el del aparato (`white`/`colour`/…); esto es sólo cómo
/// se lee. Un modo que no esté acá se muestra crudo: un producto con un modo
/// que todavía no vimos no puede quedar con el chip vacío.
const Map<String, String> kLightModeLabels = {
  'white': 'Blanco',
  'colour': 'Color',
  'scene': 'Escena',
  'music': 'Música',
};

String lightModeLabel(String mode) => kLightModeLabels[mode] ?? mode;

/// Ícono de un modo de luz (o una lámpara genérica para uno que no conocemos).
const Map<String, String> kLightModeIcons = {
  'white': '⚪',
  'colour': '🎨',
  'scene': '✨',
  'music': '🎵',
};

String lightModeIcon(String mode) => kLightModeIcons[mode] ?? '💡';
