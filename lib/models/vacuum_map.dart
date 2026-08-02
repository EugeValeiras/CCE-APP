import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Mapa del robot (capability vacuum_map, GET /roborock/devices/:id/map).
///
/// El backend ya entrega TODO en "espacio pantalla" del recorte (fila 0 arriba,
/// y crece hacia abajo, robot/base/path en píxeles del grid): acá no se flipa
/// nada, sólo se decodifica. Contrato: src/roborock/protocol/roborock-map.ts.
class VacuumMapPoint {
  final double x;
  final double y;

  const VacuumMapPoint(this.x, this.y);

  static VacuumMapPoint? fromJson(dynamic json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'];
    if (x is! num || y is! num) return null;
    return VacuumMapPoint(x.toDouble(), y.toDouble());
  }
}

/// Posición en vivo del robot: campo de estado `vacuumPosition`, que el
/// sidecar publica mientras trabaja y apaga cuando termina. Llega sola por el
/// stream (son 4 números, a diferencia del mapa entero, que va por HTTP).
///
/// OJO: acá las coordenadas son píxeles ABSOLUTOS del lienzo RRMap (el DTO del
/// mapa, en cambio, va en píxeles del recorte). Es lo que permite anclarlas a
/// un plano sin que se corran cuando el robot descubre área nueva.
class VacuumPosition {
  final double x;
  final double y;

  /// Grados en espacio pantalla (0 = mirando a +x, horario); null si el robot
  /// no reportó orientación — mismo criterio que [VacuumMapData.robotAngle].
  final double? angle;

  /// Segmento en el que está parado, o null si el robot no lo dice.
  final int? segmentId;

  /// ms epoch de la lectura: sirve para saber cuánto duró el tramo entre dos
  /// posiciones y así interpolar a la velocidad real.
  final int? at;

  const VacuumPosition({
    required this.x,
    required this.y,
    this.angle,
    this.segmentId,
    this.at,
  });

  /// null ante cualquier forma inesperada (el backend manda `null` cuando el
  /// robot deja de trabajar): la capa del robot simplemente no se dibuja.
  static VacuumPosition? fromJson(dynamic json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'];
    if (x is! num || y is! num) return null;
    if (!x.toDouble().isFinite || !y.toDouble().isFinite) return null;
    final angle = json['angle'];
    final segmentId = json['segmentId'];
    final at = json['at'];
    return VacuumPosition(
      x: x.toDouble(),
      y: y.toDouble(),
      angle:
          (angle is num && angle.toDouble().isFinite) ? angle.toDouble() : null,
      segmentId: segmentId is num ? segmentId.toInt() : null,
      at: at is num ? at.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VacuumPosition &&
      other.x == x &&
      other.y == y &&
      other.angle == angle &&
      other.segmentId == segmentId &&
      other.at == at;

  @override
  int get hashCode => Object.hash(x, y, angle, segmentId, at);
}

class VacuumMapData {
  final int width;
  final int height;

  /// Grid width*height bytes CRUDOS del formato RRMap, row-major, fila 0
  /// ARRIBA. Semántica por byte: ver [kindAt] / [segmentAt].
  final Uint8List grid;

  /// segmentIds presentes (cruzan con DeviceState.rooms.segmentId).
  final List<int> segments;
  final VacuumMapPoint? robot;

  /// Grados en espacio pantalla (0 = mirando a +x, horario); null si el robot
  /// no reportó orientación.
  final double? robotAngle;
  final VacuumMapPoint? charger;
  final List<VacuumMapPoint> path;

  /// Identidad del mapa: si cambia mapSequence, el robot regeneró el mapa.
  final int mapIndex;
  final int mapSequence;

  const VacuumMapData({
    required this.width,
    required this.height,
    required this.grid,
    required this.segments,
    required this.robot,
    required this.robotAngle,
    required this.charger,
    required this.path,
    required this.mapIndex,
    required this.mapSequence,
  });

  /// Devuelve null ante cualquier forma inesperada (mismo criterio defensivo
  /// que getInstalledTvApps: mejor sin mapa que una pantalla rota).
  static VacuumMapData? fromJson(Map<String, dynamic> json) {
    final width = (json['width'] as num?)?.toInt() ?? 0;
    final height = (json['height'] as num?)?.toInt() ?? 0;
    final encoded = json['grid'];
    if (width <= 0 || height <= 0 || encoded is! String) return null;
    if (json['gridEncoding'] != 'deflate+base64') return null;
    final Uint8List grid;
    try {
      grid = Uint8List.fromList(zlib.decode(base64Decode(encoded)));
    } catch (_) {
      return null;
    }
    if (grid.length != width * height) return null;

    final rawRobot = json['robot'];
    final path = <VacuumMapPoint>[];
    if (json['path'] is List) {
      for (final p in json['path'] as List) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          path.add(VacuumMapPoint((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
    }
    return VacuumMapData(
      width: width,
      height: height,
      grid: grid,
      segments: (json['segments'] is List)
          ? (json['segments'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      robot: VacuumMapPoint.fromJson(rawRobot),
      robotAngle: (rawRobot is Map ? rawRobot['angle'] as num? : null)?.toDouble(),
      charger: VacuumMapPoint.fromJson(json['charger']),
      path: path,
      mapIndex: (json['mapIndex'] as num?)?.toInt() ?? 0,
      mapSequence: (json['mapSequence'] as num?)?.toInt() ?? 0,
    );
  }

  /// Tipo de píxel: 0 = fuera del mapa, 1 = pared, 2+ = piso.
  int kindAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return grid[y * width + x] & 0x07;
  }

  /// segmentId del piso en (x, y), o null si no es piso / piso sin segmento.
  int? segmentAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final px = grid[y * width + x];
    if ((px & 0x07) <= 1) return null;
    final seg = (px & 0xf8) >> 3;
    return seg == 0 ? null : seg;
  }
}
