class AlarmEvent {
  final String automationId;
  final String automationName;
  final String message;
  final String sound;
  final bool critical;
  final int timestamp;

  AlarmEvent({
    required this.automationId,
    required this.automationName,
    required this.message,
    this.sound = 'alarm',
    this.critical = true,
    required this.timestamp,
  });

  factory AlarmEvent.fromJson(Map<String, dynamic> json) {
    return AlarmEvent(
      automationId: json['automationId'] ?? '',
      automationName: json['automationName'] ?? 'Alarma',
      message: json['message'] ?? '',
      sound: json['sound'] ?? 'alarm',
      critical: json['critical'] ?? json['type'] == 'critical',
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
