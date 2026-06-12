import 'package:flutter/painting.dart';

/// Escena nativa del bridge Hue (GET /hue/scenes y variantes por room).
class HueScene {
  final String id;
  final String name;
  final String? imageRid;
  final bool isSmart;
  bool isActive; // mutable: update optimista al hacer recall
  final String? roomId;
  final String? roomName;
  final List<String> colors; // hex "#rrggbb", máx 5

  HueScene({
    required this.id,
    required this.name,
    this.imageRid,
    this.isSmart = false,
    this.isActive = false,
    this.roomId,
    this.roomName,
    this.colors = const [],
  });

  factory HueScene.fromJson(Map<String, dynamic> json) {
    final rawColors = json['colors'];
    return HueScene(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      imageRid: json['imageRid'] as String?,
      isSmart: json['isSmart'] == true,
      isActive: json['isActive'] == true,
      roomId: json['roomId'] as String?,
      roomName: json['roomName'] as String?,
      colors: rawColors is List
          ? rawColors.map((c) => c.toString()).toList()
          : const [],
    );
  }

  /// Swatch de la escena: parsea los hex "#rrggbb" a [Color].
  List<Color> get swatch {
    final result = <Color>[];
    for (final hex in colors) {
      final clean = hex.replaceFirst('#', '');
      if (clean.length != 6) continue;
      final value = int.tryParse(clean, radix: 16);
      if (value == null) continue;
      result.add(Color(0xFF000000 | value));
    }
    return result;
  }
}

/// Estado objetivo de una luz dentro de una escena CCE.
class CceSceneLight {
  final String lightId;
  final bool on;
  final int? bri;
  final int? hue;
  final int? sat;
  final int? ct;

  const CceSceneLight({
    required this.lightId,
    required this.on,
    this.bri,
    this.hue,
    this.sat,
    this.ct,
  });

  factory CceSceneLight.fromJson(Map<String, dynamic> json) {
    return CceSceneLight(
      lightId: (json['lightId'] ?? '').toString(),
      on: json['on'] == true,
      bri: (json['bri'] as num?)?.toInt(),
      hue: (json['hue'] as num?)?.toInt(),
      sat: (json['sat'] as num?)?.toInt(),
      ct: (json['ct'] as num?)?.toInt(),
    );
  }

  /// Body para PUT /devices/{id}/state: si la luz va apagada solo {'on': false};
  /// si va encendida, 'on' + solo las claves presentes.
  Map<String, dynamic> toStateBody() {
    if (!on) return {'on': false};
    final body = <String, dynamic>{'on': true};
    if (bri != null) body['bri'] = bri;
    if (hue != null) body['hue'] = hue;
    if (sat != null) body['sat'] = sat;
    if (ct != null) body['ct'] = ct;
    return body;
  }
}

/// Escena de config CCE (key 'scenes' del GET /config). Se ejecuta
/// client-side luz por luz con setDeviceState.
class CceScene {
  final String id;
  final String name;
  final String? icon;
  final String? planId;
  final List<CceSceneLight> lights;

  const CceScene({
    required this.id,
    required this.name,
    this.icon,
    this.planId,
    this.lights = const [],
  });

  factory CceScene.fromJson(Map<String, dynamic> json) {
    final rawLights = json['lights'];
    return CceScene(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      icon: json['icon'] as String?,
      planId: json['planId'] as String?,
      lights: rawLights is List
          ? rawLights
              .whereType<Map>()
              .map((l) => CceSceneLight.fromJson(Map<String, dynamic>.from(l)))
              .toList()
          : const [],
    );
  }
}
