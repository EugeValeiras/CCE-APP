import 'chat_message.dart';

/// Summary of a chat thread as returned by `GET /api/agent/threads`.
class ThreadSummary {
  final String id;
  final String title;
  final String model; // 'sonnet' | 'opus' | 'haiku'
  final int messageCount;
  final String lastMessagePreview;
  final double costUsd;
  final DateTime updatedAt;

  ThreadSummary({
    required this.id,
    required this.title,
    required this.model,
    required this.messageCount,
    required this.lastMessagePreview,
    required this.costUsd,
    required this.updatedAt,
  });

  factory ThreadSummary.fromJson(Map<String, dynamic> json) => ThreadSummary(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Conversación',
        model: json['model'] as String? ?? 'sonnet',
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        lastMessagePreview: json['lastMessagePreview'] as String? ?? '',
        costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
        updatedAt: _parseDate(json['updatedAt']),
      );
}

/// Full thread with messages as returned by `GET /api/agent/threads/:id`.
class ThreadDetail {
  final String id;
  final String title;
  final String model;
  final String? claudeSessionId;
  final double costUsd;
  final List<ChatMessage> messages;

  ThreadDetail({
    required this.id,
    required this.title,
    required this.model,
    this.claudeSessionId,
    required this.costUsd,
    required this.messages,
  });

  /// [baseUrl] is e.g. 'http://host:port/api', used to build image URLs.
  factory ThreadDetail.fromJson(
    Map<String, dynamic> json, {
    required String baseUrl,
  }) =>
      ThreadDetail(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Conversación',
        model: json['model'] as String? ?? 'sonnet',
        claudeSessionId: json['claudeSessionId'] as String?,
        costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(m as Map),
                  baseUrl: baseUrl,
                ))
            .toList(),
      );
}

DateTime _parseDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
  }
  return DateTime.now();
}
