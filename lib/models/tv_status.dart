/// Estado del TV (← GET /tv/status). Espejo fiel del shape del backend, que
/// nunca tira por TV inalcanzable: TV apagado/offline ⇒ `online:false` (igual
/// que /jbl/status). Los campos de lectura (volume/muted/channel/input/app/
/// playback/modos) pueden venir null cuando el TV está apagado o el dato no
/// está disponible por el transporte actual (cloud SmartThings vs Tizen local).
///
/// NOTA sobre `copyWith`: el patrón `?? this.x` NO puede setear un campo a
/// `null` (pasar null conserva el valor previo). Se usa solo para updates
/// optimistas (siempre valor non-null al optimismo). Para "borrar" un campo a
/// null (p.ej. `volume`/`muted` que pasan a no-disponible) → re-`fromJson` vía
/// `refresh()`, nunca `copyWith`.
class TvStatus {
  final bool online;
  final String power; // 'on' | 'off' | 'unknown'
  final int? volume; // 0..100 | null (transporte no expone volumen)
  final bool? muted; // true | false | null
  final String? channel;
  final String? channelName;
  final String? input; // id de la fuente activa
  final List<TvInput> inputs;
  final String? app; // app activa (appId) | null
  final String? playback; // play|pause|stop|fastForward|rewind | null
  final List<String> supportedPlaybackCommands;
  final String? pictureMode;
  final List<String> supportedPictureModes;
  final String? soundMode;
  final List<String> supportedSoundModes;
  final List<String> disabled; // ids de controles deshabilitados server-side

  const TvStatus({
    this.online = false,
    this.power = 'unknown',
    this.volume,
    this.muted,
    this.channel,
    this.channelName,
    this.input,
    this.inputs = const [],
    this.app,
    this.playback,
    this.supportedPlaybackCommands = const [],
    this.pictureMode,
    this.supportedPictureModes = const [],
    this.soundMode,
    this.supportedSoundModes = const [],
    this.disabled = const [],
  });

  bool get isOn => power == 'on';
  bool get isStandby => power == 'off';
  bool get hasVolume => volume != null;
  bool get hasChannel => channel != null;

  /// Helper de gating de un control puntual (lo declara el backend en
  /// `disabled`): p.ej. `isDisabled('channel')` si el transporte no soporta
  /// cambio de canal.
  bool isDisabled(String id) => disabled.contains(id);

  factory TvStatus.fromJson(Map<String, dynamic> json) {
    return TvStatus(
      online: json['online'] == true,
      power: (json['power'] ?? 'unknown').toString(),
      volume: (json['volume'] as num?)?.toInt(),
      muted: json['muted'] is bool ? json['muted'] as bool : null,
      channel: json['channel'] as String?,
      channelName: json['channelName'] as String?,
      input: json['input'] as String?,
      inputs: _inputs(json['inputs']),
      app: json['app'] as String?,
      playback: json['playback'] as String?,
      supportedPlaybackCommands: _strList(json['supportedPlaybackCommands']),
      pictureMode: json['pictureMode'] as String?,
      supportedPictureModes: _strList(json['supportedPictureModes']),
      soundMode: json['soundMode'] as String?,
      supportedSoundModes: _strList(json['supportedSoundModes']),
      disabled: _strList(json['disabled']),
    );
  }

  static List<TvInput> _inputs(dynamic raw) {
    if (raw is! List) return const [];
    final out = <TvInput>[];
    for (final it in raw) {
      if (it is Map) out.add(TvInput.fromJson(Map<String, dynamic>.from(it)));
    }
    return out;
  }

  static List<String> _strList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  TvStatus copyWith({
    bool? online,
    String? power,
    int? volume,
    bool? muted,
    String? channel,
    String? channelName,
    String? input,
    List<TvInput>? inputs,
    String? app,
    String? playback,
    List<String>? supportedPlaybackCommands,
    String? pictureMode,
    List<String>? supportedPictureModes,
    String? soundMode,
    List<String>? supportedSoundModes,
    List<String>? disabled,
  }) {
    return TvStatus(
      online: online ?? this.online,
      power: power ?? this.power,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      channel: channel ?? this.channel,
      channelName: channelName ?? this.channelName,
      input: input ?? this.input,
      inputs: inputs ?? this.inputs,
      app: app ?? this.app,
      playback: playback ?? this.playback,
      supportedPlaybackCommands:
          supportedPlaybackCommands ?? this.supportedPlaybackCommands,
      pictureMode: pictureMode ?? this.pictureMode,
      supportedPictureModes:
          supportedPictureModes ?? this.supportedPictureModes,
      soundMode: soundMode ?? this.soundMode,
      supportedSoundModes: supportedSoundModes ?? this.supportedSoundModes,
      disabled: disabled ?? this.disabled,
    );
  }
}

/// Una fuente/entrada del TV (← items de GET /tv/inputs y de `inputs` en
/// /tv/status). `id` = source que se manda en PUT /tv/input; `label` = nombre
/// para mostrar.
class TvInput {
  final String id;
  final String label;

  const TvInput({required this.id, required this.label});

  factory TvInput.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    return TvInput(
      id: id,
      label: (json['label'] ?? id).toString(),
    );
  }
}

/// Una tecla del remote (← items de GET /tv/remote/keys). La app solo manda el
/// `id` en POST /tv/remote {key}; `cloudKey`/`tizenKey` son metadata server-side
/// (qué transporte resuelve la tecla) que la UI puede mostrar pero no usa.
class TvRemoteKey {
  final String id;
  final String label;
  final String? cloudKey;
  final String? tizenKey;

  const TvRemoteKey({
    required this.id,
    required this.label,
    this.cloudKey,
    this.tizenKey,
  });

  factory TvRemoteKey.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    return TvRemoteKey(
      id: id,
      label: (json['label'] ?? id).toString(),
      cloudKey: json['cloudKey'] as String?,
      tizenKey: json['tizenKey'] as String?,
    );
  }
}

/// Una app lanzable del TV (← items de GET /tv/apps). `id` = clave canónica
/// (netflix/max/prime/youtube), `appId` = id real de la plataforma que se manda
/// en POST /tv/app/launch {appId}, `label` = nombre para mostrar.
class TvApp {
  final String id;
  final String appId;
  final String label;

  const TvApp({required this.id, required this.appId, required this.label});

  factory TvApp.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    return TvApp(
      id: id,
      appId: (json['appId'] ?? id).toString(),
      label: (json['label'] ?? id).toString(),
    );
  }
}

/// Una app INSTALADA del TV (← items de GET /tv/apps/installed). A diferencia de
/// [TvApp] (catálogo de accesos fijos), estas son las apps realmente sondeadas
/// en el TV. `appId` = id real de la plataforma que se manda en POST
/// /tv/app/launch {appId}, `label` = nombre para mostrar, `brand` = color de
/// marca en hex (ej "#E50914"); se guarda como String crudo y la vista lo
/// convierte a Color (este modelo no depende de Flutter). El endpoint NUNCA
/// tira: devuelve solo las instaladas o la última lista cacheada.
class TvInstalledApp {
  final String appId;
  final String label;

  /// Color de marca en hex tal como lo manda el backend (ej "#E50914"). Puede
  /// venir vacío si el backend no lo conoce; la vista cae a un color neutro.
  final String brand;

  const TvInstalledApp({
    required this.appId,
    required this.label,
    required this.brand,
  });

  factory TvInstalledApp.fromJson(Map<String, dynamic> json) {
    final appId = (json['appId'] ?? '').toString();
    return TvInstalledApp(
      appId: appId,
      // Si no viene label, usamos el appId como fallback legible.
      label: (json['label'] ?? appId).toString(),
      brand: (json['brand'] ?? '').toString(),
    );
  }
}

/// Qué sabe hacer un Samsung, según lo que declara en SmartThings
/// (← `features` de GET /tv/tvs, EugeValeiras/CCE#45).
///
/// Existe porque los dos aparatos de la casa NO son iguales: uno es el televisor
/// `65" OLED` y el otro un MONITOR `49" Odyssey OLED G9`, que puede no tener
/// sintonizador ni las mismas apps. Ofrecerle botones que no hacen nada es
/// peor que no ofrecerlos.
///
/// Un backend viejo (o una ruta que todavía no existe) NO manda esto: en ese
/// caso todo queda en `true`, que es como se comportaba la app antes.
class TvFeatures {
  final bool power;
  final bool volume;
  final bool mute;
  final bool channel;
  final bool input;
  final bool playback;
  final bool tracks;
  final bool apps;
  final bool remote;
  final bool pictureMode;
  final bool soundMode;
  final bool ambient;

  const TvFeatures({
    this.power = true,
    this.volume = true,
    this.mute = true,
    this.channel = true,
    this.input = true,
    this.playback = true,
    this.tracks = true,
    this.apps = true,
    this.remote = true,
    this.pictureMode = true,
    this.soundMode = true,
    this.ambient = true,
  });

  /// Todo soportado: lo que se asume mientras no sepamos qué declara el aparato.
  static const TvFeatures all = TvFeatures();

  factory TvFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null) return all;
    bool f(String k) => json[k] is bool ? json[k] as bool : true;
    return TvFeatures(
      power: f('power'),
      volume: f('volume'),
      mute: f('mute'),
      channel: f('channel'),
      input: f('input'),
      playback: f('playback'),
      tracks: f('tracks'),
      apps: f('apps'),
      remote: f('remote'),
      pictureMode: f('pictureMode'),
      soundMode: f('soundMode'),
      ambient: f('ambient'),
    );
  }
}

/// Un Samsung de la casa (← items de GET /tv/tvs).
///
/// `id` es el id ESTABLE del aparato: el mismo que va en `?tv=<id>` y el que
/// forma su device canónico `dev_<id>` en el socket. El televisor que ya estaba
/// configurado conserva `id: 'tv'` ⇒ `dev_tv`, así que nada de lo que ya
/// apuntaba a él se mueve.
class TvSummary {
  final String id;
  final String name;

  /// 'tv' o 'monitor'.
  final String kind;
  final String deviceId;
  final String? ip;
  final String? model;

  /// ¿Tiene token de pairing Tizen? Sin él no hay control local (teclas rápidas)
  /// y recuperarlo obliga a ir hasta el aparato y aceptar un aviso en pantalla.
  final bool paired;
  final TvFeatures features;

  /// ¿Es el que atiende el backend cuando no se manda `?tv=`?
  final bool isDefault;

  const TvSummary({
    required this.id,
    required this.name,
    this.kind = 'tv',
    this.deviceId = '',
    this.ip,
    this.model,
    this.paired = false,
    this.features = TvFeatures.all,
    this.isDefault = false,
  });

  /// Device canónico en el socket (`dev_tv`, `dev_tv-ce588d39`, …).
  String get canonicalDeviceId => 'dev_$id';

  bool get isMonitor => kind == 'monitor';

  factory TvSummary.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? 'tv').toString();
    return TvSummary(
      id: id,
      name: (json['name'] ?? id).toString(),
      kind: (json['kind'] ?? 'tv').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      ip: json['ip'] as String?,
      model: json['model'] as String?,
      paired: json['paired'] == true,
      features: TvFeatures.fromJson(
        json['features'] is Map
            ? Map<String, dynamic>.from(json['features'] as Map)
            : null,
      ),
      isDefault: json['isDefault'] == true,
    );
  }
}
