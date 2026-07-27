class FloorPlan {
  final String id;
  final String name;
  final String svg;

  /// Room Hue linkeado al plano (para la sección de escenas); opcional.
  final String? hueRoomId;

  /// Ícono de la room (emoji, `icons0:<prefix>:<name>` o nombre MDI); opcional.
  /// Lo asigna el dashboard sobre el plano y lo muestran todas las plataformas.
  final String? icon;

  /// Habitación del mapa del robot que le corresponde a esta room, para poder
  /// limpiarla desde acá. Se vincula desde el dashboard (igual que [icon] y
  /// [hueRoomId]) y las demás plataformas la consumen.
  final VacuumRoomLink? vacuumRoom;

  FloorPlan(
      {required this.id,
      required this.name,
      required this.svg,
      this.hueRoomId,
      this.icon,
      this.vacuumRoom});

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    return FloorPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      svg: (json['svg'] ?? '').toString(),
      hueRoomId: json['hueRoomId'] as String?,
      icon: json['icon'] as String?,
      vacuumRoom: VacuumRoomLink.fromJson(json['vacuumRoom']),
    );
  }
}

/// Vínculo room del plano ↔ habitación del mapa del robot.
class VacuumRoomLink {
  final String deviceId;
  final int segmentId;

  const VacuumRoomLink({required this.deviceId, required this.segmentId});

  /// Devuelve null si el vínculo no existe o está incompleto — el backend lo
  /// guarda como `null` al desvincular.
  static VacuumRoomLink? fromJson(dynamic json) {
    if (json is! Map) return null;
    final deviceId = json['deviceId'];
    final segmentId = json['segmentId'];
    if (deviceId is! String || deviceId.isEmpty) return null;
    if (segmentId is! num) return null;
    return VacuumRoomLink(deviceId: deviceId, segmentId: segmentId.toInt());
  }
}

class LightPosition {
  final double x;
  final double y;
  LightPosition(this.x, this.y);

  factory LightPosition.fromJson(Map<String, dynamic> json) {
    return LightPosition(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FloorPlansData {
  final List<FloorPlan> plans;
  final String? activePlanId;
  /// positions[planId][deviceId] => LightPosition
  final Map<String, Map<String, LightPosition>> positions;

  /// Posición ÚNICA por plano del JBL soundbar: jblPositions[planId] => pos.
  /// (GET /config/jbl-positions devuelve {planId: {x, y}}.)
  final Map<String, LightPosition> jblPositions;

  /// Posición ÚNICA por plano del Samsung TV: tvPositions[planId] => pos.
  /// (GET /config/samsung-tv-positions devuelve {planId: {x, y}}.)
  final Map<String, LightPosition> tvPositions;

  FloorPlansData({
    required this.plans,
    required this.activePlanId,
    required this.positions,
    this.jblPositions = const {},
    this.tvPositions = const {},
  });
}
