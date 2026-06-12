class FloorPlan {
  final String id;
  final String name;
  final String svg;

  /// Room Hue linkeado al plano (para la sección de escenas); opcional.
  final String? hueRoomId;

  FloorPlan({required this.id, required this.name, required this.svg, this.hueRoomId});

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    return FloorPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      svg: (json['svg'] ?? '').toString(),
      hueRoomId: json['hueRoomId'] as String?,
    );
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

  FloorPlansData({required this.plans, required this.activePlanId, required this.positions});
}
