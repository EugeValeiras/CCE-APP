/// Fallo por device del PUT atómico de grupo (entrada de `failed[]` en la
/// respuesta de PUT /groups/{id}/state). Existe como modelo para que el
/// service pueda revertir el optimista SOLO de las luces que fallaron.
class GroupStateFailure {
  final String deviceId;
  final String error;

  const GroupStateFailure({required this.deviceId, required this.error});

  factory GroupStateFailure.fromJson(Map<String, dynamic> json) {
    return GroupStateFailure(
      deviceId: (json['deviceId'] ?? '').toString(),
      error: (json['error'] ?? '').toString(),
    );
  }
}

class LightGroup {
  final String id;
  final String name;
  final String? icon;
  final List<String> lightIds;
  final String? planId;

  LightGroup({
    required this.id,
    required this.name,
    this.icon,
    required this.lightIds,
    this.planId,
  });

  factory LightGroup.fromJson(Map<String, dynamic> json) {
    final rawLights = json['lights'];
    final lightIds = <String>[];
    if (rawLights is List) {
      for (final l in rawLights) {
        if (l is Map && l['id'] != null) {
          lightIds.add(l['id'].toString());
        } else if (l is String) {
          lightIds.add(l);
        }
      }
    }
    return LightGroup(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      icon: json['icon'] as String?,
      lightIds: lightIds,
      planId: json['planId'] as String?,
    );
  }
}
