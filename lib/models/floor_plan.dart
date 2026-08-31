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

  /// Factor de tamaño de los markers de devices sobre ESTE plano (rango
  /// 0.4–3.0). Atributo del plano, persistido en el backend y compartido con
  /// el dashboard; null = plano sin ajuste, los clientes asumen 1.0.
  final double? markerScale;

  FloorPlan(
      {required this.id,
      required this.name,
      required this.svg,
      this.hueRoomId,
      this.icon,
      this.vacuumRoom,
      this.vacuumAnchor,
      this.markerScale});

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    // Defensivo como VacuumAnchor: un markerScale no numérico o no finito es
    // un valor roto, no un ajuste — se descarta y el plano queda en 1.0.
    final rawScale = json['markerScale'];
    return FloorPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      svg: (json['svg'] ?? '').toString(),
      hueRoomId: json['hueRoomId'] as String?,
      icon: json['icon'] as String?,
      vacuumRoom: VacuumRoomLink.fromJson(json['vacuumRoom']),
      vacuumAnchor: VacuumAnchor.fromJson(json['vacuumAnchor']),
      markerScale: (rawScale is num && rawScale.toDouble().isFinite)
          ? rawScale.toDouble()
          : null,
    );
  }

  /// Copia con otro markerScale — el update optimista de los botones –/+
  /// reemplaza el plano dentro de [FloorPlansData] sin esperar al backend.
  FloorPlan withMarkerScale(double scale) => FloorPlan(
        id: id,
        name: name,
        svg: svg,
        hueRoomId: hueRoomId,
        icon: icon,
        vacuumRoom: vacuumRoom,
        vacuumAnchor: vacuumAnchor,
        markerScale: scale,
      );
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

/// Dónde va un ícono en el plano y CÓMO se dibuja (EugeValeiras/CCE#60).
///
/// Hasta el #60 esto era `{x, y}` y nada más: el tamaño era un atributo DEL
/// PLANO (`markerScale`, el mismo para todos los markers) y el televisor y el
/// soundbar salían girados 90° porque estaba escrito a mano en el dibujo. Ahora
/// cada ícono lleva su propio giro y su propio tamaño, se acomodan desde el
/// dashboard y la app los REFLEJA — acá no se editan (ver el issue).
///
/// Los dos campos son OPCIONALES para siempre. Cuando esto se escribió había 59
/// posiciones guardadas en la casa y ninguna los tenía: sin `rotation` vale 0 y
/// sin `scale` vale 1. Ese default es el contrato que comparten la API, el
/// dashboard y la app, y por eso los getters de abajo lo resuelven UNA vez, acá,
/// en vez de repetir `?? 0` en cada widget que dibuja.
class LightPosition {
  final double x;
  final double y;

  /// Giro del ícono en grados, 0–359. `null` = sin girar.
  final double? rotation;

  /// Multiplicador del `markerScale` del plano, 0.1–3.0. `null` = sin ajuste.
  final double? scale;

  LightPosition(this.x, this.y, {this.rotation, this.scale});

  /// El giro con su default, en RADIANES (que es lo que pide `Transform`).
  double get rotationRadians => (rotation ?? 0) * math.pi / 180;

  /// El multiplicador con su default. Nunca `null`.
  double get scaleFactor => scale ?? 1;

  /// Lee un `num` finito, o `null`. Un `NaN` en un `Transform` no lanza: pinta
  /// un marcador invisible, que es peor que ignorarlo.
  static double? _finite(dynamic v) {
    if (v is! num) return null;
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }

  factory LightPosition.fromJson(Map<String, dynamic> json) {
    return LightPosition(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
      rotation: _finite(json['rotation']),
      scale: _finite(json['scale']),
    );
  }
}

/// Familia de dispositivo DEDICADO: los que no viven en `positions` con las
/// luces sino en un mapa de posiciones propio del backend
/// (`/config/jbl-positions`, `/config/samsung-tv-positions`).
enum DedicatedFamily {
  /// Samsung TV / monitor: devices `dev_tv…`, `type: 'tv'` en /devices/merged.
  tv('tv'),

  /// Barra de sonido JBL: device `dev_jbl`, `type: 'speaker'`.
  jbl('speaker');

  const DedicatedFamily(this.deviceType);

  /// `type` con el que /devices/merged marca a estos aparatos.
  final String deviceType;
}

/// Dónde va, en cada plano, cada aparato de una familia dedicada.
///
/// El backend guarda un mapa PLANO cuya clave tiene hoy dos formatos que
/// conviven en la misma casa:
///
/// ```json
/// { "edafc1f9-…":              {"x": 26, "y": 110},   // ← sólo el plano
///   "733a3c72-…::tv-ce588d39": {"x": 95, "y":  43} }  // ← plano + aparato
/// ```
///
/// La primera es la forma legacy, de cuando había UN aparato por familia; la
/// segunda llegó con varios Samsung (CCE#45) y nombra al aparato —
/// `tv-ce588d39` es el device canónico `dev_tv-ce588d39`. Modelar esto como
/// `{planId: posición}` (lo que hacía la app) descarta la segunda en silencio:
/// el monitor del Office no se dibujaba y encima caía en "Sin ubicación"
/// (CCE#54). Las dos formas tienen que seguir funcionando: la pelada sigue
/// viva en la config de la casa.
class DedicatedPositions {
  /// planId → id del aparato (`null` = clave pelada) → posición.
  final Map<String, Map<String?, LightPosition>> byPlan;

  const DedicatedPositions(this.byPlan);

  static const DedicatedPositions empty = DedicatedPositions({});

  /// Lo que separa el plano del aparato en la clave compuesta.
  static const String keySeparator = '::';

  /// Parsea el `{clave: {x, y}}` crudo de la API. Mismo criterio defensivo que
  /// /config/positions: lo que no trae un objeto de posición se ignora.
  factory DedicatedPositions.fromJson(Map<dynamic, dynamic> raw) {
    final byPlan = <String, Map<String?, LightPosition>>{};
    raw.forEach((key, xy) {
      if (xy is! Map) return;
      final k = key.toString();
      final sep = k.indexOf(keySeparator);
      final planId = sep < 0 ? k : k.substring(0, sep);
      if (planId.isEmpty) return;
      final device = sep < 0 ? '' : k.substring(sep + keySeparator.length);
      byPlan.putIfAbsent(planId, () => <String?, LightPosition>{})[
              device.isEmpty ? null : device] =
          LightPosition.fromJson(Map<String, dynamic>.from(xy));
    });
    return DedicatedPositions(byPlan);
  }

  bool get isEmpty => byPlan.isEmpty;
  bool get isNotEmpty => byPlan.isNotEmpty;

  /// Los aparatos ubicados en [planId]: id del aparato (`null` = clave pelada)
  /// → dónde va. Vacío si el plano no tiene ninguno.
  Map<String?, LightPosition> inPlan(String? planId) => planId == null
      ? const <String?, LightPosition>{}
      : (byPlan[planId] ?? const <String?, LightPosition>{});

  /// ¿Hay algún aparato de esta familia ubicado en [planId]?
  bool hasPlan(String? planId) => inPlan(planId).isNotEmpty;
}

class FloorPlansData {
  final List<FloorPlan> plans;
  final String? activePlanId;
  /// positions[planId][deviceId] => LightPosition
  final Map<String, Map<String, LightPosition>> positions;

  /// Dónde va la barra JBL en cada plano (GET /config/jbl-positions).
  final DedicatedPositions jblPositions;

  /// Dónde va cada Samsung en cada plano (GET /config/samsung-tv-positions).
  final DedicatedPositions tvPositions;

  FloorPlansData({
    required this.plans,
    required this.activePlanId,
    required this.positions,
    this.jblPositions = DedicatedPositions.empty,
    this.tvPositions = DedicatedPositions.empty,
  });

  /// Plano a mostrar cuando ninguna vista lo fuerza: [candidateId] (la
  /// elección persistida del usuario) si todavía existe; si no, el plano con
  /// más dispositivos posicionados → el primero. La comparten FloorPlanPanel
  /// y la toolbar que opera sobre "el plano visible" (botones de tamaño de
  /// markers): ambos TIENEN que resolver el mismo plano o los botones
  /// ajustarían uno que no se ve.
  FloorPlan? visiblePlan(String? candidateId) {
    if (plans.isEmpty) return null;
    for (final p in plans) {
      if (p.id == candidateId) return p;
    }
    FloorPlan? best;
    var bestCount = -1;
    for (final p in plans) {
      final count = positions[p.id]?.length ?? 0;
      if (count > bestCount) {
        best = p;
        bestCount = count;
      }
    }
    return best ?? plans.first;
  }
}
