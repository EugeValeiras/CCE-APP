class EventRecord {
  final String time;
  final String id;
  final String channel;
  final String eventName;
  final String? source;
  final String? globalId;
  final String? provider;
  final Map<String, dynamic>? payload;

  EventRecord({
    required this.time,
    required this.id,
    required this.channel,
    required this.eventName,
    this.source,
    this.globalId,
    this.provider,
    this.payload,
  });

  factory EventRecord.fromJson(Map<String, dynamic> json) {
    return EventRecord(
      time: (json['time'] ?? '').toString(),
      id: (json['id'] ?? '').toString(),
      channel: (json['channel'] ?? '').toString(),
      eventName: (json['eventName'] ?? '').toString(),
      source: json['source'] as String?,
      globalId: json['globalId'] as String?,
      provider: json['provider'] as String?,
      payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : null,
    );
  }

  DateTime get timestamp => DateTime.tryParse(time) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class EventsPage {
  final List<EventRecord> items;
  final String? nextCursor;
  final bool enabled;
  EventsPage({required this.items, this.nextCursor, this.enabled = true});

  factory EventsPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return EventsPage(
      items: raw is List
          ? raw.whereType<Map>().map((e) => EventRecord.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      nextCursor: json['nextCursor'] as String?,
      enabled: json['enabled'] != false,
    );
  }
}
