import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/device.dart';

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
  /// (MdiIcons.fromString) — así cualquier ícono mdi del dashboard resuelve.
  static IconData? _mdiByName(String name) {
    final n = _normalize(name);
    final mapped = _mdiMap[n];
    if (mapped != null) return mapped;
    return MdiIcons.fromString(_kebabToCamel(n));
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

    // Sensors
    if (device.isContactSensor) {
      return (device.sensor?.contact == true) ? MdiIcons.doorOpen : MdiIcons.door;
    }
    if (device.isMotionSensor) {
      return (device.sensor?.motion == true) ? MdiIcons.motionSensor : MdiIcons.motionSensorOff;
    }
    if (device.sensor?.temperature != null) return MdiIcons.thermometer;
    if (device.sensor?.humidity != null) return MdiIcons.waterPercent;

    // Switches / buttons
    if (t.contains('button') || t.contains('switch') || t.contains('remote') || n.contains('button')) {
      return MdiIcons.gestureTapButton;
    }

    // Plugs / outlets
    if (t.contains('plug') || t.contains('outlet') || t.contains('on/off') || n.contains('enchufe')) {
      return MdiIcons.powerSocket;
    }

    // Name hints
    if (n.contains('velador') || n.contains('mesita') || n.contains('lamp') || n.contains('table')) {
      return MdiIcons.lampOutline;
    }
    if (n.contains('piso') || n.contains('floor')) {
      return MdiIcons.floorLamp;
    }
    if (n.contains('techo') || n.contains('ceiling') || n.contains('plafón') || n.contains('plafon')) {
      return MdiIcons.ceilingLight;
    }
    if (n.contains('dicroica') || n.contains('spot')) {
      return MdiIcons.spotlightBeam;
    }
    if (n.contains('tira') || n.contains('strip')) {
      return MdiIcons.ledStrip;
    }

    // Light default
    if (t.contains('color') || t.contains('rgb')) return MdiIcons.lightbulbOn;
    if (t.contains('dimmable')) return MdiIcons.lightbulb;
    return MdiIcons.lightbulbOutline;
  }
}

/// Manual mapping of the most commonly-configured CCE icon names to MDI IconData.
/// Covers ~60 icons that cover most home-automation use cases.
final Map<String, IconData> _mdiMap = {
  'lightbulb': MdiIcons.lightbulb,
  'lightbulb-outline': MdiIcons.lightbulbOutline,
  'lightbulb-on': MdiIcons.lightbulbOn,
  'lightbulb-on-outline': MdiIcons.lightbulbOnOutline,
  'lightbulb-multiple': MdiIcons.lightbulbMultiple,
  'lightbulb-group': MdiIcons.lightbulbGroup,
  'ceiling-light': MdiIcons.ceilingLight,
  'ceiling-light-outline': MdiIcons.ceilingLightOutline,
  'floor-lamp': MdiIcons.floorLamp,
  'floor-lamp-outline': MdiIcons.floorLampOutline,
  'lamp': MdiIcons.lamp,
  'lamps': MdiIcons.lamps,
  'lamp-outline': MdiIcons.lampOutline,
  'desk-lamp': MdiIcons.deskLamp,
  'wall-sconce': MdiIcons.wallSconce,
  'wall-sconce-flat': MdiIcons.wallSconceFlat,
  'wall-sconce-round': MdiIcons.wallSconceRound,
  'track-light': MdiIcons.trackLight,
  'string-lights': MdiIcons.stringLights,
  'spotlight': MdiIcons.spotlight,
  'spotlight-beam': MdiIcons.spotlightBeam,
  'led-strip': MdiIcons.ledStrip,
  'led-strip-variant': MdiIcons.ledStripVariant,
  'power-socket': MdiIcons.powerSocket,
  'power-socket-eu': MdiIcons.powerSocketEu,
  'power-socket-us': MdiIcons.powerSocketUs,
  'power-plug': MdiIcons.powerPlug,
  'power-plug-outline': MdiIcons.powerPlugOutline,
  'dial-switch': MdiIcons.dipSwitch,
  'light-switch': MdiIcons.lightSwitch,
  'toggle-switch': MdiIcons.toggleSwitch,
  'gesture-tap-button': MdiIcons.gestureTapButton,
  'gesture-tap': MdiIcons.gestureTap,
  'remote': MdiIcons.remote,
  'door': MdiIcons.door,
  'door-open': MdiIcons.doorOpen,
  'door-closed': MdiIcons.doorClosed,
  'door-closed-lock': MdiIcons.doorClosedLock,
  'window-open': MdiIcons.windowOpen,
  'window-closed': MdiIcons.windowClosed,
  'motion-sensor': MdiIcons.motionSensor,
  'motion-sensor-off': MdiIcons.motionSensorOff,
  'thermometer': MdiIcons.thermometer,
  'water-percent': MdiIcons.waterPercent,
  'shield': MdiIcons.shield,
  'shield-outline': MdiIcons.shieldOutline,
  'shield-home': MdiIcons.shieldHome,
  'fan': MdiIcons.fan,
  'television': MdiIcons.television,
  'air-conditioner': MdiIcons.airConditioner,
  'coffee': MdiIcons.coffee,
  'sofa': MdiIcons.sofa,
  'bed': MdiIcons.bed,
  'bathtub': MdiIcons.bathtub,
  'stove': MdiIcons.stove,
  'fridge': MdiIcons.fridge,
  'desk': MdiIcons.desk,
  'chair-rolling': MdiIcons.chairRolling,
  'garage': MdiIcons.garage,
  'garage-open': MdiIcons.garageOpen,
  'home': MdiIcons.home,
  'home-outline': MdiIcons.homeOutline,
};
