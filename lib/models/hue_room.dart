/// Room de un bridge Hue (GET /hue/rooms). El backend agrega los rooms de
/// TODOS los bridges: el `id` del primer bridge viaja crudo (UUID) y el resto
/// namespaceado como `<bridgeId>::<rid>`, así el on/off rutea solo al bridge
/// dueño. `on` es mutable para el update optimista del toggle.
class HueRoom {
  final String id;
  final String name;
  final String? archetype;
  final String? groupedLightId;
  bool? on; // null = desconocido; mutable: update optimista
  final String? bridgeId;
  final String? bridgeName;

  HueRoom({
    required this.id,
    required this.name,
    this.archetype,
    this.groupedLightId,
    this.on,
    this.bridgeId,
    this.bridgeName,
  });

  factory HueRoom.fromJson(Map<String, dynamic> json) {
    return HueRoom(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Room').toString(),
      archetype: json['archetype'] as String?,
      groupedLightId: json['groupedLightId'] as String?,
      on: json['on'] is bool ? json['on'] as bool : null,
      bridgeId: json['bridgeId'] as String?,
      bridgeName: json['bridgeName'] as String?,
    );
  }
}
