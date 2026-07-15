class DeviceState {
  final bool on;
  final int bri;
  final int? hue;
  final int? sat;
  final int? ct;
  final bool reachable;
  final String? mode;
  final String? colormode; // 'hs' | 'xy' | 'ct' — solo provider hue
  final List<double>? xy; // [x, y] CIE — solo provider hue

  // ── Termostato (Tuya cat 'wk') — todos opcionales, viajan dentro de state ──
  final double? currentTemp; // °C, lectura del sensor (DP24)
  final double? targetTemp; // °C, setpoint editable (DP3)
  final String? tempMode; // 'Manual' | 'Program' (DP4)
  final String? systemMode; // ej 'heat' (DP28)
  final double? minTemp; // mínimo del setpoint (DP113)
  final double? maxTemp; // máximo del setpoint (DP112)

  // ── Bloque MEDIA (F8/F13) — dispositivos AV: JBL Bar (dev_jbl), Samsung TV
  // (dev_tv). Escala del backend: volume 0-100 (NO 0-31; la vista JBL reescala).
  // Se OMITEN (null) si el device no reporta un valor confiable.
  final int? volume; // 0-100 (escala backend/normalizada)
  final bool? muted;
  final String? mediaInput; // fuente/entrada activa (JBL source, TV input)
  final String? mediaState; // 'playing' | 'paused' | 'stopped'
  final String? mediaApp; // app activa (TV)
  final String? mediaChannel; // canal actual (TV)

  DeviceState({
    this.on = false,
    this.bri = 0,
    this.hue,
    this.sat,
    this.ct,
    this.reachable = true,
    this.mode,
    this.colormode,
    this.xy,
    this.currentTemp,
    this.targetTemp,
    this.tempMode,
    this.systemMode,
    this.minTemp,
    this.maxTemp,
    this.volume,
    this.muted,
    this.mediaInput,
    this.mediaState,
    this.mediaApp,
    this.mediaChannel,
  });

  factory DeviceState.fromJson(Map<String, dynamic> json) {
    return DeviceState(
      on: json['on'] == true,
      bri: (json['bri'] as num?)?.toInt() ?? 0,
      hue: (json['hue'] as num?)?.toInt(),
      sat: (json['sat'] as num?)?.toInt(),
      ct: (json['ct'] as num?)?.toInt(),
      reachable: json['reachable'] != false,
      mode: json['mode'] as String?,
      colormode: json['colormode'] as String?,
      xy: (json['xy'] is List && (json['xy'] as List).length >= 2)
          ? [(json['xy'][0] as num).toDouble(), (json['xy'][1] as num).toDouble()]
          : null,
      currentTemp: (json['currentTemp'] as num?)?.toDouble(),
      targetTemp: (json['targetTemp'] as num?)?.toDouble(),
      tempMode: json['tempMode'] as String?,
      systemMode: json['systemMode'] as String?,
      minTemp: (json['minTemp'] as num?)?.toDouble(),
      maxTemp: (json['maxTemp'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toInt(),
      muted: json['muted'] is bool ? json['muted'] as bool : null,
      mediaInput: json['mediaInput'] as String?,
      mediaState: json['mediaState'] as String?,
      mediaApp: json['mediaApp'] as String?,
      mediaChannel: json['mediaChannel'] as String?,
    );
  }

  // NOTA: el patrón `??` NO puede limpiar un xy/colormode stale (pasar null
  // conserva el valor previo); por eso los setters optimistas de
  // DevicesService pisan `colormode` explícitamente ('hs' en setColor,
  // 'ct' en setCt) para que resolveLightColor ignore el xy viejo.
  DeviceState copyWith({
    bool? on,
    int? bri,
    int? hue,
    int? sat,
    int? ct,
    bool? reachable,
    String? mode,
    String? colormode,
    List<double>? xy,
    double? currentTemp,
    double? targetTemp,
    String? tempMode,
    String? systemMode,
    double? minTemp,
    double? maxTemp,
    int? volume,
    bool? muted,
    String? mediaInput,
    String? mediaState,
    String? mediaApp,
    String? mediaChannel,
  }) {
    return DeviceState(
      on: on ?? this.on,
      bri: bri ?? this.bri,
      hue: hue ?? this.hue,
      sat: sat ?? this.sat,
      ct: ct ?? this.ct,
      reachable: reachable ?? this.reachable,
      mode: mode ?? this.mode,
      colormode: colormode ?? this.colormode,
      xy: xy ?? this.xy,
      currentTemp: currentTemp ?? this.currentTemp,
      targetTemp: targetTemp ?? this.targetTemp,
      tempMode: tempMode ?? this.tempMode,
      systemMode: systemMode ?? this.systemMode,
      minTemp: minTemp ?? this.minTemp,
      maxTemp: maxTemp ?? this.maxTemp,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      mediaInput: mediaInput ?? this.mediaInput,
      mediaState: mediaState ?? this.mediaState,
      mediaApp: mediaApp ?? this.mediaApp,
      mediaChannel: mediaChannel ?? this.mediaChannel,
    );
  }
}

class DeviceSensor {
  final double? temperature;
  final double? humidity;
  final String? battery;
  final bool? motion;
  final bool? contact;
  final String? brightness;
  // Switches multi-botón (Hue Tap Dial / remotes): cantidad de botones y la
  // última tecla pulsada (0=click, 1=doble, 2=long).
  final int? outlets;
  final int? lastKey;

  DeviceSensor({
    this.temperature,
    this.humidity,
    this.battery,
    this.motion,
    this.contact,
    this.brightness,
    this.outlets,
    this.lastKey,
  });

  factory DeviceSensor.fromJson(Map<String, dynamic> json) {
    return DeviceSensor(
      temperature: (json['temperature'] as num?)?.toDouble(),
      humidity: (json['humidity'] as num?)?.toDouble(),
      battery: json['battery'] as String?,
      motion: json['motion'] as bool?,
      contact: json['contact'] as bool?,
      brightness: json['brightness'] as String?,
      outlets: (json['outlets'] as num?)?.toInt(),
      lastKey: (json['lastKey'] as num?)?.toInt(),
    );
  }
}

class Device {
  final String id;
  final String name;
  final String type;
  final String? source;
  final List<String> bindingIds;
  /// Capabilities del descriptor (array de strings: 'switch', 'brightness',
  /// 'color_hsv', 'thermostat', …). Fuente canónica para detectar el tipo.
  final List<String> capabilities;
  final bool hidden;
  DeviceState state;
  DeviceSensor? sensor;
  /// Set by DevicesService when a WS event arrives for this device.
  /// Used by tile widgets to flash a live-update pulse.
  DateTime? lastEventAt;

  Device({
    required this.id,
    required this.name,
    required this.type,
    this.source,
    this.bindingIds = const [],
    this.capabilities = const [],
    this.hidden = false,
    required this.state,
    this.sensor,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    final rawBindings = json['bindings'];
    final bindingIds = <String>[];
    if (rawBindings is List) {
      for (final b in rawBindings) {
        if (b is Map && b['bindingId'] != null) {
          bindingIds.add(b['bindingId'].toString());
        }
      }
    }
    final rawCaps = json['capabilities'];
    final capabilities = rawCaps is List
        ? rawCaps.map((c) => c.toString()).toList()
        : const <String>[];
    return Device(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      source: json['source'] as String?,
      bindingIds: bindingIds,
      capabilities: capabilities,
      hidden: json['hidden'] == true,
      state: DeviceState.fromJson(Map<String, dynamic>.from(json['state'] ?? {})),
      sensor: json['sensor'] == null
          ? null
          : DeviceSensor.fromJson(Map<String, dynamic>.from(json['sensor'] as Map)),
    );
  }

  /// Termostato: capability 'thermostat' en el descriptor (fuente canónica),
  /// con fallbacks por tipo / presencia de setpoint para descriptores legacy.
  bool get isThermostat =>
      capabilities.contains('thermostat') ||
      type.toLowerCase().contains('thermostat') ||
      state.targetTemp != null;

  /// Cerradura: capability 'lock' en el descriptor (fuente canónica) o tipo
  /// que la mencione. Espejo de isLockDevice del dashboard.
  bool get isLock =>
      capabilities.contains('lock') || type.toLowerCase().contains('lock');

  /// Serial EZVIZ para la API /ezviz/devices/:serial: el bindingId con prefijo
  /// 'ezviz_' (devuelve el serial sin ese prefijo); null si no hay binding EZVIZ.
  String? get ezvizSerial {
    for (final bid in bindingIds) {
      if (bid.startsWith('ezviz_')) return bid.substring('ezviz_'.length);
    }
    return null;
  }

  /// Dispositivo AV canónico (dev_jbl/dev_tv): capability 'volume' o
  /// 'media_playback'. Su estado lo renderiza Jbl/TvService (control dedicado),
  /// NO las grillas de luces/sensores — por eso DevicesService los excluye de
  /// esos getters para que no aparezcan como tiles fantasma.
  bool get isMediaDevice =>
      capabilities.contains('volume') || capabilities.contains('media_playback');

  bool get isLight {
    // Heuristic: has bri field or type name suggests light
    if (isThermostat || isLock || isMediaDevice) return false;
    final t = type.toLowerCase();
    return t.contains('light') ||
        t.contains('bulb') ||
        t.contains('plug') ||
        (sensor == null && !_isSwitch() && !_isSensor());
  }

  bool _isSwitch() {
    final t = type.toLowerCase();
    return t.contains('button') ||
        t.contains('switch') ||
        t.contains('remote') ||
        t.contains('dial');
  }

  /// Device tipo switch/control (botón, switch, remote, dial). Pueden caer en
  /// la lista de sensores; son clickeables para abrir su pantalla de switch.
  bool get isSwitch => _isSwitch();

  /// Switch multi-botón (Hue Tap Dial / remote de 4 botones): tiene outlets>1.
  bool get isMultiButton => (sensor?.outlets ?? 0) > 1;
  int get outletCount => sensor?.outlets ?? 1;

  bool _isSensor() {
    if (sensor != null) return true;
    final t = type.toLowerCase();
    return t.contains('sensor') || t.contains('motion') || t.contains('contact');
  }

  bool get isSensorDevice => _isSensor();
  bool get isContactSensor {
    final t = type.toLowerCase();
    return t.contains('contact') || (sensor?.contact != null);
  }
  bool get isMotionSensor {
    final t = type.toLowerCase();
    return t.contains('motion') || (sensor?.motion != null);
  }

  bool get supportsColor {
    final t = type.toLowerCase();
    return t.contains('color light') ||
        t.contains('extended color') ||
        t.contains('rgb') ||
        (state.hue != null && state.hue! > 0) ||
        (state.sat != null && state.sat! > 0);
  }

  bool get supportsBrightness {
    final t = type.toLowerCase();
    return supportsColor ||
        t.contains('dimmable') ||
        t.contains('color temperature') ||
        state.bri > 0;
  }

  bool get supportsCT {
    final t = type.toLowerCase();
    return t.contains('color temperature') ||
        t.contains('extended color') ||
        state.ct != null;
  }
}
