/// REGISTRY PURO capability → kind de renderer (port 1:1 de
/// `capability-renderers.ts` del Dashboard). Sin dependencias de UI para
/// testearlo standalone.
///
/// El UnifiedDeviceScreen itera `capabilityRenderersFor(caps)` y monta el
/// control de cada kind. Agregar una capability = registrar su kind acá + su
/// render en el detail; el contenedor no cambia.
library;

/// Kinds de control que el detalle sabe renderizar.
enum CapabilityRendererKind {
  vacuum,
  vacuumRooms,
  onoff,
  brightness,
  colorTemperature,
  colorHsv,
  volume,
  soundMode,
  lock,
  thermostat,
  alarm,
  mediaPlayback,
  inputSelect,
  appLauncher,
  channel,
  button,
  dial,
  sensor,
  detach,
  // CCE#100 — la luz con MODOS (Tuya work_mode) y con ESCENAS propias. Van
  // juntos y justo después del color: elegir «escena» es lo que hace que el
  // color deje de mandar.
  lightMode,
  scene,
}

class CapabilityRendererEntry {
  final String capability;
  final CapabilityRendererKind kind;
  const CapabilityRendererEntry(this.capability, this.kind);
}

/// capability (string del descriptor) → kind del renderer.
const Map<String, CapabilityRendererKind> _kindByCapability = {
  'vacuum': CapabilityRendererKind.vacuum,
  'vacuum_rooms': CapabilityRendererKind.vacuumRooms,
  'switch': CapabilityRendererKind.onoff,
  'brightness': CapabilityRendererKind.brightness,
  'color_temperature': CapabilityRendererKind.colorTemperature,
  'color_hsv': CapabilityRendererKind.colorHsv,
  'volume': CapabilityRendererKind.volume,
  'sound_mode': CapabilityRendererKind.soundMode,
  'lock': CapabilityRendererKind.lock,
  'thermostat': CapabilityRendererKind.thermostat,
  'alarm': CapabilityRendererKind.alarm,
  'media_playback': CapabilityRendererKind.mediaPlayback,
  'input_select': CapabilityRendererKind.inputSelect,
  'app_launcher': CapabilityRendererKind.appLauncher,
  'channel': CapabilityRendererKind.channel,
  // Sensores read-only → un mismo readout.
  'sensor': CapabilityRendererKind.sensor,
  'motion': CapabilityRendererKind.sensor,
  'contact': CapabilityRendererKind.sensor,
  'button': CapabilityRendererKind.button,
  'dial': CapabilityRendererKind.dial,
  'detach_relay': CapabilityRendererKind.detach,
  'light_mode': CapabilityRendererKind.lightMode,
  'scene': CapabilityRendererKind.scene,
};

/// Orden canónico de aparición: estado primario arriba, sensores al final.
const List<CapabilityRendererKind> _renderOrder = [
  CapabilityRendererKind.vacuum,
  CapabilityRendererKind.vacuumRooms,
  CapabilityRendererKind.onoff,
  CapabilityRendererKind.lock,
  CapabilityRendererKind.alarm,
  CapabilityRendererKind.thermostat,
  CapabilityRendererKind.brightness,
  CapabilityRendererKind.colorTemperature,
  CapabilityRendererKind.colorHsv,
  // El modo primero: es lo que decide si el color o la escena mandan.
  CapabilityRendererKind.lightMode,
  CapabilityRendererKind.scene,
  CapabilityRendererKind.volume,
  CapabilityRendererKind.soundMode,
  CapabilityRendererKind.mediaPlayback,
  CapabilityRendererKind.inputSelect,
  CapabilityRendererKind.channel,
  CapabilityRendererKind.appLauncher,
  CapabilityRendererKind.button,
  CapabilityRendererKind.dial,
  CapabilityRendererKind.sensor,
  // Configuración del device, no un control de uso diario: va último.
  CapabilityRendererKind.detach,
];

/// GUARD del `on` polisémico: si el device es cerradura o alarma, el toggle
/// genérico de `switch` NO se renderiza (lock/alarm interpretan `on` en su
/// propio renderer). Evita mostrar "Encendido" sobre una cerradura.
bool _switchIsClaimed(List<String> caps) =>
    caps.contains('lock') || caps.contains('alarm');

/// Lista ORDENADA de renderers para las capabilities de un device (deduplicada
/// por kind). Aplica el guard del `on` polisémico. Capabilities desconocidas se
/// ignoran (forward-compat).
List<CapabilityRendererEntry> capabilityRenderersFor(List<String> caps) {
  final seen = <CapabilityRendererKind>{};
  final entries = <CapabilityRendererEntry>[];

  for (final cap in caps) {
    final kind = _kindByCapability[cap];
    if (kind == null) continue; // cap no soportada por el registry → ignorar
    if (kind == CapabilityRendererKind.onoff && _switchIsClaimed(caps)) {
      continue; // guard on polisémico
    }
    if (seen.contains(kind)) continue; // dedupe
    seen.add(kind);
    entries.add(CapabilityRendererEntry(cap, kind));
  }

  entries.sort(
    (a, b) => _renderOrder.indexOf(a.kind) - _renderOrder.indexOf(b.kind),
  );
  return entries;
}
