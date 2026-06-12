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
    );
  }

  // NOTA: el patrón `??` NO puede limpiar un xy/colormode stale (pasar null
  // conserva el valor previo); por eso los setters optimistas de
  // DevicesService pisan `colormode` explícitamente ('hs' en setColor,
  // 'ct' en setCt) para que resolveLightColor ignore el xy viejo.
  DeviceState copyWith({bool? on, int? bri, int? hue, int? sat, int? ct, bool? reachable, String? mode, String? colormode, List<double>? xy}) {
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

  DeviceSensor({this.temperature, this.humidity, this.battery, this.motion, this.contact, this.brightness});

  factory DeviceSensor.fromJson(Map<String, dynamic> json) {
    return DeviceSensor(
      temperature: (json['temperature'] as num?)?.toDouble(),
      humidity: (json['humidity'] as num?)?.toDouble(),
      battery: json['battery'] as String?,
      motion: json['motion'] as bool?,
      contact: json['contact'] as bool?,
      brightness: json['brightness'] as String?,
    );
  }
}

class Device {
  final String id;
  final String name;
  final String type;
  final String? source;
  final List<String> bindingIds;
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
    return Device(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      source: json['source'] as String?,
      bindingIds: bindingIds,
      hidden: json['hidden'] == true,
      state: DeviceState.fromJson(Map<String, dynamic>.from(json['state'] ?? {})),
      sensor: json['sensor'] == null
          ? null
          : DeviceSensor.fromJson(Map<String, dynamic>.from(json['sensor'] as Map)),
    );
  }

  bool get isLight {
    // Heuristic: has bri field or type name suggests light
    final t = type.toLowerCase();
    return t.contains('light') ||
        t.contains('bulb') ||
        t.contains('plug') ||
        (sensor == null && !_isSwitch() && !_isSensor());
  }

  bool _isSwitch() {
    final t = type.toLowerCase();
    return t.contains('button') || t.contains('switch') || t.contains('remote');
  }

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
