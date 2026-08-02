import 'dart:math' as math;

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

  /// Transformada mapa del robot → coordenadas de este plano. Sólo la tienen
  /// los planos que el dashboard generó DESDE el mapa del robot; los dibujados
  /// a mano no comparten sistema de coordenadas y quedan en null.
  final VacuumAnchor? vacuumAnchor;

  FloorPlan(
      {required this.id,
      required this.name,
      required this.svg,
      this.hueRoomId,
      this.icon,
      this.vacuumRoom,
      this.vacuumAnchor});

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    return FloorPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      svg: (json['svg'] ?? '').toString(),
      hueRoomId: json['hueRoomId'] as String?,
      icon: json['icon'] as String?,
      vacuumRoom: VacuumRoomLink.fromJson(json['vacuumRoom']),
      vacuumAnchor: VacuumAnchor.fromJson(json['vacuumAnchor']),
    );
  }
}

/// Ancla del mapa del robot al plano: convierte un píxel ABSOLUTO del lienzo
/// RRMap en unidades del plano (las del viewBox del SVG). La escribe el
/// dashboard al generar el plano desde un segmento; la API sólo la persiste.
///
/// Que el píxel sea absoluto (y no del recorte del mapa) es lo que hace que el
/// ancla siga sirviendo cuando el robot amplía el mapa y el recorte se corre.
class VacuumAnchor {
  final String deviceId;

  /// Unidades del plano por píxel absoluto del RRMap. En los planos generados
  /// vale 1: el RRMap es 50 mm/px y el editor usa 0.05 m por unidad.
  final double scale;
  final double offsetX;
  final double offsetY;

  /// Horario, en grados; 0 en los planos generados.
  final double rotationDeg;

  const VacuumAnchor({
    required this.deviceId,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    this.rotationDeg = 0,
  });

  /// `planX = offsetX + scale · (x·cos θ − y·sin θ)`, ídem Y. Es la MISMA
  /// fórmula que el dashboard: si se separan, cada pantalla dibuja el robot en
  /// un lugar distinto.
  ({double x, double y}) toPlan(double x, double y) {
    if (rotationDeg == 0) {
      return (x: offsetX + scale * x, y: offsetY + scale * y);
    }
    final rad = rotationDeg * math.pi / 180;
    final cos = math.cos(rad);
    final sin = math.sin(rad);
    return (
      x: offsetX + scale * (x * cos - y * sin),
      y: offsetY + scale * (x * sin + y * cos),
    );
  }

  /// Devuelve null ante cualquier forma inesperada — mismo criterio que
  /// [VacuumRoomLink]: sin ancla el plano se dibuja igual que siempre, sólo se
  /// queda sin la capa del robot.
  static VacuumAnchor? fromJson(dynamic json) {
    if (json is! Map) return null;
    final deviceId = json['deviceId'];
    final scale = json['scale'];
    final offsetX = json['offsetX'];
    final offsetY = json['offsetY'];
    if (deviceId is! String || deviceId.isEmpty) return null;
    if (scale is! num || offsetX is! num || offsetY is! num) return null;
    // Una escala 0 (o NaN/infinita) colapsaría el robot en un punto y a un
    // tamaño imposible: es un ancla rota, no un ancla sin rotación.
    final s = scale.toDouble();
    final ox = offsetX.toDouble();
    final oy = offsetY.toDouble();
    if (!s.isFinite || s <= 0 || !ox.isFinite || !oy.isFinite) return null;
    final rot = json['rotationDeg'];
    return VacuumAnchor(
      deviceId: deviceId,
      scale: s,
      offsetX: ox,
      offsetY: oy,
      rotationDeg:
          (rot is num && rot.toDouble().isFinite) ? rot.toDouble() : 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VacuumAnchor &&
      other.deviceId == deviceId &&
      other.scale == scale &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.rotationDeg == rotationDeg;

  @override
  int get hashCode =>
      Object.hash(deviceId, scale, offsetX, offsetY, rotationDeg);
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
