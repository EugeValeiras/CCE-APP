import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/device.dart';
import '../theme/mdi.dart';

/// Resuelve el ícono de un device — del lightIcons configurado en el dashboard
/// (nombre MDI, id `icons0:<prefix>:<name>` con SVG vendoreado, o emoji), o un
/// default inteligente por tipo. Misma lógica que el dashboard para que el
/// ícono coincida en la lista de luces, los sensores y el plano.
class IconResolver {
  /// Strip prefixes like "mdi-" / "mdi:" and normalize kebab-case.
  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('mdi:')) s = s.substring(4);
    if (s.startsWith('mdi-')) s = s.substring(4);
    return s;
  }

  static String _kebabToCamel(String s) {
    final parts = s.split(RegExp(r'[-_]')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return s;
    return parts.first +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  /// MDI por nombre: primero el mapa curado, luego el set COMPLETO de MDI
  /// (Mdi.byName, vendoreado) — así cualquier ícono mdi del dashboard resuelve.
  static IconData? _mdiByName(String name) {
    final n = _normalize(name);
    final mapped = _mdiMap[n];
    if (mapped != null) return mapped;
    return Mdi.byName[n] ?? Mdi.byName[_kebabToCamel(n)];
  }

  /// Un id parece identificador de ícono (no emoji/texto) si es ascii kebab.
  static bool _looksLikeId(String s) =>
      RegExp(r'^[a-z0-9:_-]+$').hasMatch(s.toLowerCase());

  /// Si [configuredIcon] es un id `icons0:mdi:<name>`, devuelve el `<name>`;
  /// si no, lo devuelve tal cual (o null si es un icons0 no-mdi).
  static String? _mdiNameFrom(String cfg) {
    if (!cfg.startsWith('icons0:')) return cfg;
    final parts = cfg.split(':');
    return (parts.length >= 3 && parts[1] == 'mdi')
        ? parts.sublist(2).join(':')
        : null;
  }

  /// Resolve an icon for a device, preferring user-configured.
  /// [displayName] is the user-facing name (custom or default) used for heuristics.
  static IconData resolve(Device device,
      {String? configuredIcon, String? displayName}) {
    final raw = configuredIcon?.trim();
    if (raw != null && raw.isNotEmpty) {
      final name = _mdiNameFrom(raw);
      if (name != null && name.isNotEmpty) {
        final icon = _mdiByName(name);
        if (icon != null) return icon;
      }
    }
    return _defaultFor(device, displayName: displayName);
  }

  /// Versión que devuelve un Widget: soporta MDI (Icon), `icons0:` con SVG
  /// vendoreado (SvgPicture tintado con [color]) y emoji (Text). [customIcons]
  /// es el mapa `icons0:<prefix>:<name>` -> SVG del dashboard.
  static Widget widget(
    Device device, {
    String? configuredIcon,
    Map<String, String> customIcons = const {},
    String? displayName,
    double size = 24,
    Color? color,
  }) {
    final raw = configuredIcon?.trim();
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('icons0:')) {
        final svg = customIcons[raw];
        if (svg != null && svg.contains('<svg')) {
          return SvgPicture.string(
            svg,
            width: size,
            height: size,
            colorFilter: color != null
                ? ColorFilter.mode(color, BlendMode.srcIn)
                : null,
          );
        }
        // icons0:mdi:* sin SVG cacheado → resolver por MDI.
      } else if (!_looksLikeId(raw)) {
        // Emoji o texto: se muestra tal cual.
        return Text(raw,
            style: TextStyle(fontSize: size * 0.92, height: 1.0));
      }
    }
    final data = resolve(device, configuredIcon: raw, displayName: displayName);
    return Icon(data, size: size, color: color);
  }

  static IconData _defaultFor(Device device, {String? displayName}) {
    final t = device.type.toLowerCase();
    final n = (displayName ?? device.name).toLowerCase();

    // Capabilities canónicas ANTES de cualquier heurística por nombre/tipo:
    // sin estas ramas un TV, el robot o la cerradura caían al fallback
    // lamparita ("todos son dispositivos": el default respeta lo que el
    // device declara en su descriptor).
    if (device.isMediaDevice) {
      // TV vs parlante: media_playback/app_launcher son del TV (mismo criterio
      // que el historial en event_presenter); el resto de los media son audio.
      final tvLike = device.hasCapability('media_playback') ||
          device.hasCapability('app_launcher') ||
          t.contains('tv');
      return tvLike ? Mdi.television : Mdi.speaker;
    }
    if (device.isVacuum) return Mdi.robotVacuum;
    if (device.isLock) return Mdi.lock;
    if (device.isThermostat) return Mdi.thermometer;

    // Sensors
    if (device.isContactSensor) {
      return (device.sensor?.contact == true) ? Mdi.doorOpen : Mdi.door;
    }
    if (device.isMotionSensor) {
      return (device.sensor?.motion == true) ? Mdi.motionSensor : Mdi.motionSensorOff;
    }
    if (device.sensor?.temperature != null) return Mdi.thermometer;
    if (device.sensor?.humidity != null) return Mdi.waterPercent;

    // Switches / buttons
    if (t.contains('button') || t.contains('switch') || t.contains('remote') || n.contains('button')) {
      return Mdi.gestureTapButton;
    }

    // Plugs / outlets
    if (t.contains('plug') || t.contains('outlet') || t.contains('on/off') || n.contains('enchufe')) {
      return Mdi.powerSocket;
    }

    // Name hints
    if (n.contains('velador') || n.contains('mesita') || n.contains('lamp') || n.contains('table')) {
      return Mdi.lampOutline;
    }
    if (n.contains('piso') || n.contains('floor')) {
      return Mdi.floorLamp;
    }
    if (n.contains('techo') || n.contains('ceiling') || n.contains('plafón') || n.contains('plafon')) {
      return Mdi.ceilingLight;
    }
    if (n.contains('dicroica') || n.contains('spot')) {
      return Mdi.spotlightBeam;
    }
    if (n.contains('tira') || n.contains('strip')) {
      return Mdi.ledStrip;
    }

    // Light default
    if (t.contains('color') || t.contains('rgb')) return Mdi.lightbulbOn;
    if (t.contains('dimmable')) return Mdi.lightbulb;
    return Mdi.lightbulbOutline;
  }
}

/// Manual mapping of the most commonly-configured CCE icon names to MDI IconData.
/// Covers ~60 icons that cover most home-automation use cases.
final Map<String, IconData> _mdiMap = {
  'lightbulb': Mdi.lightbulb,
  'lightbulb-outline': Mdi.lightbulbOutline,
  'lightbulb-on': Mdi.lightbulbOn,
  'lightbulb-on-outline': Mdi.lightbulbOnOutline,
  'lightbulb-multiple': Mdi.lightbulbMultiple,
  'lightbulb-group': Mdi.lightbulbGroup,
  'ceiling-light': Mdi.ceilingLight,
  'ceiling-light-outline': Mdi.ceilingLightOutline,
  'floor-lamp': Mdi.floorLamp,
  'floor-lamp-outline': Mdi.floorLampOutline,
  'lamp': Mdi.lamp,
  'lamps': Mdi.lamps,
  'lamp-outline': Mdi.lampOutline,
  'desk-lamp': Mdi.deskLamp,
  'wall-sconce': Mdi.wallSconce,
  'wall-sconce-flat': Mdi.wallSconceFlat,
  'wall-sconce-round': Mdi.wallSconceRound,
  'track-light': Mdi.trackLight,
  'string-lights': Mdi.stringLights,
  'spotlight': Mdi.spotlight,
  'spotlight-beam': Mdi.spotlightBeam,
  'led-strip': Mdi.ledStrip,
  'led-strip-variant': Mdi.ledStripVariant,
  'power-socket': Mdi.powerSocket,
  'power-socket-eu': Mdi.powerSocketEu,
  'power-socket-us': Mdi.powerSocketUs,
  'power-plug': Mdi.powerPlug,
  'power-plug-outline': Mdi.powerPlugOutline,
  'dial-switch': Mdi.dipSwitch,
  'light-switch': Mdi.lightSwitch,
  'toggle-switch': Mdi.toggleSwitch,
  'gesture-tap-button': Mdi.gestureTapButton,
  'gesture-tap': Mdi.gestureTap,
  'remote': Mdi.remote,
  'door': Mdi.door,
  'door-open': Mdi.doorOpen,
  'door-closed': Mdi.doorClosed,
  'door-closed-lock': Mdi.doorClosedLock,
  'window-open': Mdi.windowOpen,
  'window-closed': Mdi.windowClosed,
  'motion-sensor': Mdi.motionSensor,
  'motion-sensor-off': Mdi.motionSensorOff,
  'thermometer': Mdi.thermometer,
  'water-percent': Mdi.waterPercent,
  'shield': Mdi.shield,
  'shield-outline': Mdi.shieldOutline,
  'shield-home': Mdi.shieldHome,
  'fan': Mdi.fan,
  'television': Mdi.television,
  'air-conditioner': Mdi.airConditioner,
  'coffee': Mdi.coffee,
  'sofa': Mdi.sofa,
  'bed': Mdi.bed,
  'bathtub': Mdi.bathtub,
  'stove': Mdi.stove,
  'fridge': Mdi.fridge,
  'desk': Mdi.desk,
  'chair-rolling': Mdi.chairRolling,
  'garage': Mdi.garage,
  'garage-open': Mdi.garageOpen,
  'home': Mdi.home,
  'home-outline': Mdi.homeOutline,
};
