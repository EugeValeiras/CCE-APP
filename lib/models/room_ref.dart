import 'package:flutter/painting.dart';

/// Habitación canónica única de la app: derivada on-demand por
/// DevicesService.rooms con triple fallback (planos → groups → '_orphans').
class RoomRef {
  final String id;
  final String name;
  final List<String> deviceIds;
  final String? iconName;

  /// NO-NULL SOLO para rooms derivados de un floor plan (fallback 1).
  /// Los fallbacks 2 (groups) y 3 ('_orphans') SIEMPRE tienen planId == null.
  final String? planId;

  /// Room Hue linkeado al plano; ídem: solo fallback 1.
  final String? hueRoomId;

  const RoomRef({
    required this.id,
    required this.name,
    required this.deviceIds,
    this.iconName,
    this.planId,
    this.hueRoomId,
  });
}

/// Stats derivadas de una sala — ÚNICA fuente de verdad (las vistas tienen
/// prohibido recalcular tint/conteos/brillo; todo sale de
/// DevicesService.statsFor).
class RoomStats {
  final int lightsOn;
  final int lightsTotal;
  final bool anyOn;

  /// Promedio HSV de las luces ON con color; null si lightsOn == 0
  /// (o si ninguna luz encendida reporta color).
  final Color? tint;

  /// Colores (crudos, sin pastelizar) de TODAS las luces ON con color, para
  /// armar el gradiente multicolor de la room card estilo Hue. Vacío si no
  /// hay luces ON coloreadas (la card cae al [tint] dominante o al ámbar).
  final List<Color> tintColors;

  /// Brillo promedio 0..1 de las luces ON (bri/254); null si lightsOn == 0
  /// — NUNCA NaN.
  final double? avgBrightness;

  final bool anyContactOpen;
  final bool anyMotion;

  /// Máximo lastEventAt entre los devices de la sala (para PulseOnUpdate).
  final DateTime? latestEventAt;

  const RoomStats({
    required this.lightsOn,
    required this.lightsTotal,
    required this.anyOn,
    this.tint,
    this.tintColors = const [],
    this.avgBrightness,
    this.anyContactOpen = false,
    this.anyMotion = false,
    this.latestEventAt,
  });
}
