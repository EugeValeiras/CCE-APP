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
