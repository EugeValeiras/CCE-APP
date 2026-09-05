import 'vacuum_map.dart';

/// Habitación reportada por el sidecar Roborock (capability vacuum_rooms).
/// `segmentId` es el id numérico que consume el verbo cleanRooms.
/// Una escena de CCE aplicable a una luz con capability `scene` (CCE#100).
///
/// El `id` es de la config de CCE, NO un índice del firmware: el aparato no
/// expone un catálogo de escenas — la escena es el payload de un DP, que CCE
/// captura tal como está puesto y guarda con un nombre. Que el id sea estable es
/// lo que permite renombrar la escena sin romper las automatizaciones.
class LightScene {
  final String id;
  final String name;
  final String? icon;

  const LightScene({required this.id, required this.name, this.icon});

  factory LightScene.fromJson(Map<String, dynamic> json) => LightScene(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        icon: json['icon'] as String?,
      );
}

class VacuumRoom {
  final String id;
  final String name;
  final int segmentId;

  const VacuumRoom({required this.id, required this.name, required this.segmentId});

  factory VacuumRoom.fromJson(Map<String, dynamic> json) {
    return VacuumRoom(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      segmentId: (json['segmentId'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Progreso de la cola de habitaciones (el backend las manda de a una porque
/// el robot ignora el orden si van juntas). Ausente si no hay cola en curso.
class VacuumRoomQueue {
  final List<int> segments;
  final List<String> names;
  final int current;
  final String phase; // 'starting' | 'running'

  const VacuumRoomQueue({
    required this.segments,
    required this.names,
    required this.current,
    required this.phase,
  });

  /// Segmento que se está limpiando ahora, o null si el índice quedó fuera de
  /// rango (defensivo: el progreso llega por push y podría venir desfasado).
  int? get currentSegment =>
      (current >= 0 && current < segments.length) ? segments[current] : null;

  static VacuumRoomQueue? fromJson(dynamic json) {
    if (json is! Map) return null;
    final segments = (json['segments'] is List)
        ? (json['segments'] as List)
            .whereType<num>()
            .map((e) => e.toInt())
            .toList()
        : <int>[];
    if (segments.isEmpty) return null;
    return VacuumRoomQueue(
      segments: segments,
      names: (json['names'] is List)
          ? (json['names'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      current: (json['current'] as num?)?.toInt() ?? 0,
      phase: (json['phase'] ?? 'running').toString(),
    );
  }
}

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

  /// Relé con capability `detach_relay` (SONOFF ZBMINIR2): true si la tecla de
  /// la pared está desacoplada de la carga. null en todo lo demás.
  final bool? detached;

  // ── Termostato (Tuya cat 'wk') — todos opcionales, viajan dentro de state ──
  final double? currentTemp; // °C, lectura del sensor (DP24)
  final double? targetTemp; // °C, setpoint editable (DP3)
  final String? tempMode; // 'Manual' | 'Program' (DP4)
  final String? systemMode; // ej 'heat' (DP28)
  final double? minTemp; // mínimo del setpoint (DP113)
  final double? maxTemp; // máximo del setpoint (DP112)
  /// true mientras el relé está dando calor (DP102, CCE#101). `systemMode:
  /// 'heat'` es el MODO configurado; esto es la actividad de ahora. null si
  /// la API no lo manda.
  final bool? heating;
  /// Código de falla del equipo (DP12); 0 = sin falla. null si no vino.
  final int? fault;
  /// Bloqueo de teclas del panel (DP6). null si no vino.
  final bool? childLock;

  // ── Luz con MODOS y ESCENAS propias (capabilities light_mode / scene) ──────
  // CCE#100 — El Hexagon Tuya: `mode` es el modo ACTIVO (campo base, ya estaba)
  // y estos tres son el abanico. Los modos son del PRODUCTO (specs del cloud) y
  // las escenas, de la config de CCE: el firmware no tiene catálogo de escenas
  // —la escena es el payload de un DP—, así que CCE lo captura del aparato y lo
  // guarda con un nombre. Enums DINÁMICOS por-device, como `cleanModes`.
  final List<String>? lightModes;
  final List<LightScene>? lightScenes;
  /// Id de la escena de CCE que coincide con el payload puesto AHORA. null
  /// cuando la luz no está en escena, o cuando tiene una que CCE no capturó.
  final String? sceneId;

  // ── Bloque MEDIA (F8/F13) — dispositivos AV: JBL Bar (dev_jbl), Samsung TV
  // (dev_tv). Escala del backend: volume 0-100 (NO 0-31; la vista JBL reescala).
  // Se OMITEN (null) si el device no reporta un valor confiable.
  final int? volume; // 0-100 (escala backend/normalizada)
  final bool? muted;
  final String? mediaInput; // fuente/entrada activa (JBL source, TV input)
  final String? mediaState; // 'playing' | 'paused' | 'stopped'
  final String? mediaApp; // app activa (TV)
  final String? mediaChannel; // canal actual (TV)

  // ── Bloque VACUUM (Roborock vía Matter RVC + sidecar) ──
  // Matter emite vacuumState/cleanMode/cleanModes/battery; el sidecar (cuando
  // tiene sesión) agrega rooms/fanSpeed/fanSpeeds (capability vacuum_rooms).
  final String? vacuumState; // 'cleaning' | 'docked' | 'paused' | 'returning' | 'error' | 'stopped'
  final String? cleanMode; // label REAL del robot, ej 'Auto, Vacuum and Mop'
  final List<String>? cleanModes; // los modos soportados (labels reales)
  final int? battery; // 0-100 (numérico; distinto de DeviceSensor.battery String)
  final List<VacuumRoom>? rooms; // habitaciones nombradas (sidecar)
  final String? fanSpeed; // potencia de succión activa (label real)
  final List<String>? fanSpeeds; // potencias soportadas
  final VacuumRoomQueue? roomQueue; // cola de habitaciones en orden (sidecar)
  /// Faena de mantenimiento en curso: 'washing_mop' | 'emptying_bin' |
  /// 'going_to_wash'. COMPLEMENTA a [vacuumState]: el cluster RVC de Matter
  /// sólo tiene siete estados y mete lavar la mopa y vaciar el depósito dentro
  /// de 'docked', así que sin esto un robot trabajando en la base se ve igual
  /// que uno durmiendo enchufado.
  final String? vacuumActivity;
  /// Habitación en la que el robot trabaja AHORA, ya resuelta a nombre. Sale
  /// del status del propio robot, así que sirve aunque la limpieza no haya
  /// salido de CCE — a diferencia de [roomQueue], que sólo sabe de las colas
  /// que armamos nosotros.
  final String? vacuumRoomName;

  /// Vida útil restante de los consumibles, 0-100 por pieza: `mainBrush`,
  /// `sideBrush`, `filter`, `sensor`. El sidecar ya los publicaba y la app los
  /// tiraba: son la única forma de enterarse de que hay que limpiar un sensor
  /// o cambiar un cepillo antes de que el robot empiece a fallar.
  final Map<String, int>? consumables;

  /// Resumen histórico del robot (`count` = limpiezas completadas).
  final Map<String, num>? cleanSummary;

  /// Dónde está el robot AHORA, en píxeles absolutos del lienzo del RRMap.
  /// Sólo viaja mientras trabaja; la consume la capa en vivo del plano cruzada
  /// con `floorPlans[].vacuumAnchor`.
  final VacuumPosition? vacuumPosition;

  // ── Bloque PHONE (telefonía 4G, device `dev_phone`) ──
  // El HAT SIM7600G-H con su propia línea. La app disca desde su propio dial
  // pad (issue #10); lo que no lleva es el AUDIO, que se queda en la casa.
  /// 'idle' | 'dialing' | 'ringing' | 'active' | 'ended'.
  final String? callState;
  /// 'in' = entrante, 'out' = saliente. Ausente sin llamada.
  final String? callDirection;
  /// Número del otro extremo.
  final String? peerNumber;
  /// Nombre del contacto, si el número está en la libreta del backend.
  final String? peerName;
  /// Epoch ms del inicio de la llamada en curso.
  final int? callStartedAt;
  /// Cómo terminó la ÚLTIMA llamada (CCE#81): 'answered' | 'missed' |
  /// 'rejected' | 'not-connected' | 'failed'. Ausente hasta la primera que
  /// termina desde que arrancó el backend.
  final String? lastCallResult;
  /// 'in' | 'out' de esa última llamada.
  final String? lastCallDirection;
  /// Epoch ms del inicio de esa última llamada.
  final int? lastCallAt;
  /// ¿La línea CURSA tráfico? 'active' | 'inactive' | 'unknown'.
  ///
  /// NO se deriva del registro de red: una línea sin habilitar reporta
  /// operador y señal impecables y no cursa nada. Sale de una consulta USSD
  /// del backend y vale 'unknown' hasta que se haga.
  final String? lineActive;
  /// Señal 0-5 barras.
  final int? signalBars;
  /// Tecnología en uso ('WCDMA', 'LTE', …).
  final String? networkTech;
  /// Operador registrado.
  final String? networkOperator;

  DeviceState({
    this.on = false,
    this.bri = 0,
    this.hue,
    this.sat,
    this.ct,
    this.reachable = true,
    this.mode,
    this.lightModes,
    this.lightScenes,
    this.sceneId,
    this.colormode,
    this.xy,
    this.detached,
    this.currentTemp,
    this.targetTemp,
    this.tempMode,
    this.systemMode,
    this.minTemp,
    this.maxTemp,
    this.heating,
    this.fault,
    this.childLock,
    this.volume,
    this.muted,
    this.mediaInput,
    this.mediaState,
    this.mediaApp,
    this.mediaChannel,
    this.vacuumState,
    this.cleanMode,
    this.cleanModes,
    this.battery,
    this.rooms,
    this.fanSpeed,
    this.fanSpeeds,
    this.roomQueue,
    this.vacuumActivity,
    this.vacuumRoomName,
    this.consumables,
    this.cleanSummary,
    this.vacuumPosition,
    this.callState,
    this.callDirection,
    this.peerNumber,
    this.peerName,
    this.callStartedAt,
    this.lastCallResult,
    this.lastCallDirection,
    this.lastCallAt,
    this.lineActive,
    this.signalBars,
    this.networkTech,
    this.networkOperator,
  });

  /// Lee un campo NUMÉRICO del estado por su nombre del catálogo. Lo usa el
  /// editor de acciones para resolver `minFrom`/`maxFrom` (CCE#62): el rango
  /// del control sale del propio device (minTemp/maxTemp del termostato) en vez
  /// del rango documental del catálogo.
  num? numField(String? field) {
    switch (field) {
      case 'bri':
        return bri;
      case 'hue':
        return hue;
      case 'sat':
        return sat;
      case 'ct':
        return ct;
      case 'currentTemp':
        return currentTemp;
      case 'targetTemp':
        return targetTemp;
      case 'minTemp':
        return minTemp;
      case 'maxTemp':
        return maxTemp;
      case 'volume':
        return volume;
      case 'battery':
        return battery;
      default:
        return null;
    }
  }

  factory DeviceState.fromJson(Map<String, dynamic> json) {
    return DeviceState(
      on: json['on'] == true,
      bri: (json['bri'] as num?)?.toInt() ?? 0,
      hue: (json['hue'] as num?)?.toInt(),
      sat: (json['sat'] as num?)?.toInt(),
      ct: (json['ct'] as num?)?.toInt(),
      reachable: json['reachable'] != false,
      mode: json['mode'] as String?,
      lightModes: (json['lightModes'] is List)
          ? (json['lightModes'] as List).map((m) => m.toString()).toList()
          : null,
      lightScenes: (json['lightScenes'] is List)
          ? (json['lightScenes'] as List)
              .whereType<Map<String, dynamic>>()
              .map(LightScene.fromJson)
              .toList()
          : null,
      sceneId: json['sceneId'] as String?,
      colormode: json['colormode'] as String?,
      detached: json['detached'] is bool ? json['detached'] as bool : null,
      xy: (json['xy'] is List && (json['xy'] as List).length >= 2)
          ? [(json['xy'][0] as num).toDouble(), (json['xy'][1] as num).toDouble()]
          : null,
      currentTemp: (json['currentTemp'] as num?)?.toDouble(),
      targetTemp: (json['targetTemp'] as num?)?.toDouble(),
      tempMode: json['tempMode'] as String?,
      systemMode: json['systemMode'] as String?,
      minTemp: (json['minTemp'] as num?)?.toDouble(),
      maxTemp: (json['maxTemp'] as num?)?.toDouble(),
      heating: json['heating'] is bool ? json['heating'] as bool : null,
      fault: (json['fault'] as num?)?.toInt(),
      childLock: json['childLock'] is bool ? json['childLock'] as bool : null,
      volume: (json['volume'] as num?)?.toInt(),
      muted: json['muted'] is bool ? json['muted'] as bool : null,
      mediaInput: json['mediaInput'] as String?,
      mediaState: json['mediaState'] as String?,
      mediaApp: json['mediaApp'] as String?,
      mediaChannel: json['mediaChannel'] as String?,
      vacuumState: json['vacuumState'] as String?,
      cleanMode: json['cleanMode'] as String?,
      cleanModes: (json['cleanModes'] is List)
          ? (json['cleanModes'] as List).map((m) => m.toString()).toList()
          : null,
      battery: (json['battery'] as num?)?.toInt(),
      rooms: (json['rooms'] is List)
          ? (json['rooms'] as List)
              .whereType<Map>()
              // Sin segmentId numérico la room no es accionable (cleanRooms
              // manda segmentIds) y el default 0 colapsaría la selección de
              // varias rooms en una sola key — se descarta al parsear.
              .where((r) => r['segmentId'] is num)
              .map((r) => VacuumRoom.fromJson(Map<String, dynamic>.from(r)))
              .toList()
          : null,
      fanSpeed: json['fanSpeed'] as String?,
      roomQueue: VacuumRoomQueue.fromJson(json['roomQueue']),
      vacuumActivity: json['vacuumActivity'] as String?,
      vacuumRoomName: json['vacuumRoomName'] as String?,
      consumables: json['consumables'] is Map
          ? {
              for (final e in (json['consumables'] as Map).entries)
                if (e.value is num) e.key.toString(): (e.value as num).round(),
            }
          : null,
      cleanSummary: json['cleanSummary'] is Map
          ? {
              for (final e in (json['cleanSummary'] as Map).entries)
                if (e.value is num) e.key.toString(): e.value as num,
            }
          : null,
      vacuumPosition: VacuumPosition.fromJson(json['vacuumPosition']),
      fanSpeeds: (json['fanSpeeds'] is List)
          ? (json['fanSpeeds'] as List).map((m) => m.toString()).toList()
          : null,
      callState: json['callState'] as String?,
      callDirection: json['callDirection'] as String?,
      peerNumber: json['peerNumber'] as String?,
      peerName: json['peerName'] as String?,
      callStartedAt: (json['callStartedAt'] as num?)?.toInt(),
      lastCallResult: json['lastCallResult'] as String?,
      lastCallDirection: json['lastCallDirection'] as String?,
      lastCallAt: (json['lastCallAt'] as num?)?.toInt(),
      lineActive: json['lineActive'] as String?,
      signalBars: (json['signalBars'] as num?)?.toInt(),
      networkTech: json['networkTech'] as String?,
      networkOperator: json['networkOperator'] as String?,
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
    List<String>? lightModes,
    List<LightScene>? lightScenes,
    String? sceneId,
    String? colormode,
    List<double>? xy,
    double? currentTemp,
    double? targetTemp,
    String? tempMode,
    String? systemMode,
    double? minTemp,
    double? maxTemp,
    bool? heating,
    int? fault,
    bool? childLock,
    int? volume,
    bool? muted,
    String? mediaInput,
    String? mediaState,
    String? mediaApp,
    String? mediaChannel,
    String? vacuumState,
    String? cleanMode,
    List<String>? cleanModes,
    int? battery,
    List<VacuumRoom>? rooms,
    String? fanSpeed,
    List<String>? fanSpeeds,
    VacuumRoomQueue? roomQueue,
    String? vacuumActivity,
    String? vacuumRoomName,
    Map<String, int>? consumables,
    Map<String, num>? cleanSummary,
    VacuumPosition? vacuumPosition,
    String? callState,
    String? callDirection,
    String? peerNumber,
    String? peerName,
    int? callStartedAt,
    String? lastCallResult,
    String? lastCallDirection,
    int? lastCallAt,
    String? lineActive,
    int? signalBars,
    String? networkTech,
    String? networkOperator,
  }) {
    return DeviceState(
      on: on ?? this.on,
      bri: bri ?? this.bri,
      hue: hue ?? this.hue,
      sat: sat ?? this.sat,
      ct: ct ?? this.ct,
      reachable: reachable ?? this.reachable,
      mode: mode ?? this.mode,
      lightModes: lightModes ?? this.lightModes,
      lightScenes: lightScenes ?? this.lightScenes,
      sceneId: sceneId ?? this.sceneId,
      colormode: colormode ?? this.colormode,
      xy: xy ?? this.xy,
      currentTemp: currentTemp ?? this.currentTemp,
      targetTemp: targetTemp ?? this.targetTemp,
      tempMode: tempMode ?? this.tempMode,
      systemMode: systemMode ?? this.systemMode,
      minTemp: minTemp ?? this.minTemp,
      maxTemp: maxTemp ?? this.maxTemp,
      heating: heating ?? this.heating,
      fault: fault ?? this.fault,
      childLock: childLock ?? this.childLock,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      mediaInput: mediaInput ?? this.mediaInput,
      mediaState: mediaState ?? this.mediaState,
      mediaApp: mediaApp ?? this.mediaApp,
      mediaChannel: mediaChannel ?? this.mediaChannel,
      vacuumState: vacuumState ?? this.vacuumState,
      cleanMode: cleanMode ?? this.cleanMode,
      cleanModes: cleanModes ?? this.cleanModes,
      battery: battery ?? this.battery,
      rooms: rooms ?? this.rooms,
      fanSpeed: fanSpeed ?? this.fanSpeed,
      fanSpeeds: fanSpeeds ?? this.fanSpeeds,
      roomQueue: roomQueue ?? this.roomQueue,
      vacuumActivity: vacuumActivity ?? this.vacuumActivity,
      vacuumRoomName: vacuumRoomName ?? this.vacuumRoomName,
      consumables: consumables ?? this.consumables,
      cleanSummary: cleanSummary ?? this.cleanSummary,
      vacuumPosition: vacuumPosition ?? this.vacuumPosition,
      callState: callState ?? this.callState,
      callDirection: callDirection ?? this.callDirection,
      peerNumber: peerNumber ?? this.peerNumber,
      peerName: peerName ?? this.peerName,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      lastCallResult: lastCallResult ?? this.lastCallResult,
      lastCallDirection: lastCallDirection ?? this.lastCallDirection,
      lastCallAt: lastCallAt ?? this.lastCallAt,
      lineActive: lineActive ?? this.lineActive,
      signalBars: signalBars ?? this.signalBars,
      networkTech: networkTech ?? this.networkTech,
      networkOperator: networkOperator ?? this.networkOperator,
    );
  }
}

/// Umbral con el que el backend deriva `brightness` de `lux`
/// (BRIGHTNESS_LUX_THRESHOLD en el API, CCE#112): menos de 50 lx es oscuro.
const int kBrightnessLuxThreshold = 50;

class DeviceSensor {
  final double? temperature;
  final double? humidity;
  final String? battery;
  final bool? motion;
  final bool? contact;
  /// 'darker' | 'brighter'. Derivado de [lux] (umbral 50) cuando el sensor mide.
  final String? brightness;
  /// Iluminancia en lux, entera (CCE#112). Sólo en los sensores que la miden
  /// (SNZB-03PR2); el SNZB-03P viejo trae [brightness] y nada más.
  final int? lux;

  /// ¿Hay luz? El binario si vino; si no, el número contra el mismo umbral que
  /// usa el backend. null sin ninguna de las dos lecturas.
  bool? get isBright {
    if (brightness != null) return brightness == 'brighter';
    if (lux != null) return lux! >= kBrightnessLuxThreshold;
    return null;
  }
  // Switches multi-botón (Hue Tap Dial / remotes): cantidad de botones y la
  // última tecla pulsada (0=click, 1=doble, 2=long).
  final int? outlets;
  final int? lastKey;
  /// Botón físico del último evento en un device multi-tecla (0-based).
  final int? outlet;
  /// Epoch ms del último disparo reportado por el sensor (eWeLink trigTime).
  final int? trigTime;

  DeviceSensor({
    this.temperature,
    this.humidity,
    this.battery,
    this.motion,
    this.contact,
    this.brightness,
    this.lux,
    this.outlets,
    this.lastKey,
    this.outlet,
    this.trigTime,
  });

  /// Parseo del sensor que llega por REST (`GET /devices`).
  factory DeviceSensor.fromJson(Map<String, dynamic> json) =>
      DeviceSensor.merge(null, json);

  /// Aplica [json] sobre [current] y devuelve el sensor resultante: cada campo
  /// que el mapa no traiga —o traiga con un valor que no se puede convertir—
  /// conserva el valor de [current]. Con `current == null` es el parseo puro,
  /// por eso [DeviceSensor.fromJson] delega acá.
  ///
  /// UNA sola lista de campos para los dos caminos, el REST y el evento del
  /// WebSocket (`DevicesService._applyDeviceEvent`). Hasta CCE#56 eran dos
  /// listas calcadas y la defensa de `trigTime` estaba sólo en la del REST:
  /// el evento casteaba crudo y reventaba con el String que manda eWeLink,
  /// perdiendo el bloque de sensor entero (motion, contact, temperatura).
  factory DeviceSensor.merge(DeviceSensor? current, Map<String, dynamic> json) {
    return DeviceSensor(
      temperature: _sensorDouble(json['temperature']) ?? current?.temperature,
      humidity: _sensorDouble(json['humidity']) ?? current?.humidity,
      battery: _sensorString(json['battery']) ?? current?.battery,
      motion: _sensorBool(json['motion']) ?? current?.motion,
      contact: _sensorBool(json['contact']) ?? current?.contact,
      brightness: _sensorString(json['brightness']) ?? current?.brightness,
      // CCE#112 — acá y NO en otra lista: esta es la única whitelist del sensor
      // (REST y WS), así que agregarlo acá es lo que evita que el primer evento
      // WebSocket lo borre (la trampa de CCE#100 con lightModes).
      lux: _sensorInt(json['lux']) ?? current?.lux,
      outlets: _sensorInt(json['outlets']) ?? current?.outlets,
      lastKey: _sensorInt(json['lastKey']) ?? current?.lastKey,
      outlet: _sensorInt(json['outlet']) ?? current?.outlet,
      // OJO: el backend manda trigTime como num o como String según el
      // provider (el fixture dorado tiene ambos) — parseo defensivo.
      trigTime: _sensorInt(json['trigTime']) ?? current?.trigTime,
    );
  }
}

// ── Coerciones del sensor ─────────────────────────────────────────────
// El mismo campo llega con distinto tipo según el provider. Un cast crudo
// (`as num?`) no falla en el campo: tira y se lleva puesto el objeto entero.
// Devolver null ante un valor inconvertible lo degrada a "este campo no vino",
// que es lo que el merge ya sabe manejar.

double? _sensorDouble(dynamic v) => switch (v) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

int? _sensorInt(dynamic v) => switch (v) {
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? double.tryParse(s)?.toInt(),
      _ => null,
    };

bool? _sensorBool(dynamic v) => switch (v) {
      final bool b => b,
      final num n => n != 0,
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };

String? _sensorString(dynamic v) => switch (v) {
      final String s => s,
      final num n => n.toString(),
      final bool b => b.toString(),
      _ => null,
    };

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

  /// ¿El device declara esta capability en su descriptor? Fuente canónica para
  /// la vista unificada por capabilities.
  bool hasCapability(String cap) => capabilities.contains(cap);

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

  /// Robot aspiradora: capability 'vacuum' (Matter RVC / Roborock). Tiene tile
  /// y pantalla dedicados; se excluye de luces/sensores como los media devices.
  bool get isVacuum => capabilities.contains('vacuum');

  /// Teléfono 4G (`dev_phone`, HAT SIM7600G-H): capability 'phone'. Tiene card
  /// y pantalla dedicadas; se excluye de luces/sensores como el robot — sin
  /// esto caería en `isLight` (no tiene sensor ni es switch) y aparecería como
  /// una luz fantasma que se puede "prender".
  bool get isPhone => capabilities.contains('phone');

  /// Hay una llamada viva (marcando, sonando o en curso).
  bool get phoneInCall =>
      state.callState != null && state.callState != 'idle' && state.callState != 'ended';

  /// Relé-pulsador: declara `switch` Y `button` a la vez. Es un actuador
  /// comandable que ADEMÁS es una tecla de pared.
  ///
  /// El caso real es el SONOFF ZBMINIR2 en modo detach: la tecla dispara
  /// automatizaciones y la salida del relé no controla ninguna luz, así que su
  /// `state.on` es cierto (la salida existe) pero NO significa "hay una luz
  /// encendida". Por eso el plano lo pinta NEUTRO en vez de encendido — sin
  /// dejar de ser comandable. Espejo de isButtonRelay del dashboard.
  ///
  /// Se decide por CAPABILITIES y no por `type` ('eWeLink Switch Button'): ese
  /// string es una etiqueta libre del provider eWeLink y ataría la UI de dos
  /// clientes a un texto que mañana cambia. Los botones a pilas (SNZB-01P/01M,
  /// Hue tap dial) declaran `button` + `sensor` pero NO `switch`, y las luces
  /// declaran `switch` sin `button`: ninguno matchea.
  bool get isButtonRelay =>
      capabilities.contains('switch') && capabilities.contains('button');

  /// Área MotionAware de Hue (EugeValeiras/CCE#96): un sensor de movimiento
  /// que el bridge arma con las señales de radio de los bombillos y que se
  /// prende y apaga. Es el ÚNICO sensor cuyo `state.on` significa algo y se
  /// escribe: `on` = el área detecta (el `enabled` del bridge). Por eso el
  /// toggle se rotula «MotionAware» y no «Encendido»: no hay ninguna luz que
  /// encender. Espejo de isHueMotionArea del dashboard: capabilities y
  /// proveedor, nunca el `type` (llega como 'Hue Motion Sensor', igual que un
  /// sensor PIR).
  bool get isHueMotionArea =>
      capabilities.contains('motion') &&
      capabilities.contains('switch') &&
      (source == 'hue' || bindingIds.any((b) => b.startsWith('hue_')));

  /// ¿`state.on` es un encendido de verdad que se puede mandar? Es el guard
  /// del `on` polisémico del catálogo (lock = trabada, alarm = armada)
  /// aplicado a la pregunta «¿se puede prender y apagar?».
  bool get hasRealOnOff =>
      capabilities.contains('switch') &&
      !capabilities.contains('lock') &&
      !capabilities.contains('alarm');

  /// Relé cuya tecla física se puede desacoplar de la carga (CCE#39). Sólo lo
  /// declaran los devices cuyo firmware expone el modo, así que alcanza para
  /// decidir si mostrar el interruptor.
  bool get supportsDetach => capabilities.contains('detach_relay');

  bool get isLight {
    // Heuristic: has bri field or type name suggests light
    if (isThermostat || isLock || isMediaDevice || isVacuum || isPhone) return false;
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
