/// Estado del soundbar JBL (← GET /jbl/status) y radios guardadas
/// (← items de GET /jbl/radios).
///
/// NOTA sobre `copyWith`: el patrón `?? this.x` NO puede setear un campo a
/// `null` (pasar null conserva el valor previo). Se usa solo para updates
/// optimistas (siempre valor non-null al optimismo). Para "borrar" un campo a
/// null (p.ej. `volume` que pasa a no-disponible) → re-`fromJson` vía
/// `refresh()`, nunca `copyWith`.
class JblStatus {
  final bool online;
  final String? ip;
  final String name;
  final int? volume; // 0..31 (escala de display de la barra) | null (UPnP falló)
  final bool? muted; // true | false | null
  final String power; // 'on' | 'off' | 'unknown'
  final String? source;
  final String? transport;

  const JblStatus({
    this.online = false,
    this.ip,
    this.name = 'JBL BAR 1000MK2',
    this.volume,
    this.muted,
    this.power = 'unknown',
    this.source,
    this.transport,
  });

  bool get isOn => power == 'on';
  bool get isStandby => power == 'off';
  bool get hasVolume => volume != null;

  factory JblStatus.fromJson(Map<String, dynamic> json) {
    return JblStatus(
      online: json['online'] == true,
      ip: json['ip'] as String?,
      name: (json['name'] ?? 'JBL BAR 1000MK2').toString(),
      volume: (json['volume'] as num?)?.toInt(),
      muted: json['muted'] is bool ? json['muted'] as bool : null,
      power: (json['power'] ?? 'unknown').toString(),
      source: json['source'] as String?,
      transport: json['transport'] as String?,
    );
  }

  JblStatus copyWith({
    bool? online,
    String? ip,
    String? name,
    int? volume,
    bool? muted,
    String? power,
    String? source,
    String? transport,
  }) {
    return JblStatus(
      online: online ?? this.online,
      ip: ip ?? this.ip,
      name: name ?? this.name,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      power: power ?? this.power,
      source: source ?? this.source,
      transport: transport ?? this.transport,
    );
  }
}

class JblRadio {
  final String name;
  final int? index;

  const JblRadio({required this.name, this.index});

  factory JblRadio.fromJson(Map<String, dynamic> json) {
    return JblRadio(
      name: (json['name'] ?? '').toString(),
      index: (json['index'] as num?)?.toInt(),
    );
  }
}
