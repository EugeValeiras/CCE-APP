/// A tool call performed by the agent during a turn, with its result once it
/// arrives. Mirrors `ChatToolRecord` in the CCE-API.
class ToolUseRecord {
  final String id;
  final String name;
  dynamic input;
  String? result;
  bool isError;

  ToolUseRecord({
    required this.id,
    required this.name,
    this.input,
    this.result,
    this.isError = false,
  });

  factory ToolUseRecord.fromJson(Map<String, dynamic> json) => ToolUseRecord(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        input: json['input'],
        result: json['result'] as String?,
        isError: json['isError'] as bool? ?? false,
      );
}

/// A single message in a chat thread. Used both for persisted messages loaded
/// from the API and for the in-flight assistant turn being streamed.
///
/// Mirrors `ChatMessageEntry` in the CCE-API. `imageUrls` holds either absolute
/// URLs to `GET /api/agent/uploads/:file` (for persisted user messages) or local
/// file paths (for just-sent images shown instantly).
class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  String text;
  final List<ToolUseRecord> tools;
  final List<String> imageUrls;
  String? error;
  bool streaming;

  ChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    List<ToolUseRecord>? tools,
    List<String>? imageUrls,
    this.error,
    this.streaming = false,
  })  : tools = tools ?? [],
        imageUrls = imageUrls ?? [];

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// Parses a persisted `ChatMessageEntry`. `images[]` are upload filenames; we
  /// build absolute URLs against [baseUrl] (e.g. 'http://host:port/api').
  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    required String baseUrl,
  }) {
    final rawImages = json['images'] as List<dynamic>? ?? const [];
    final urls = rawImages
        .map((e) => e.toString())
        .where((f) => f.isNotEmpty)
        .map((f) => f.startsWith('http')
            ? f
            : '$baseUrl/agent/uploads/${Uri.encodeComponent(f)}')
        .toList();
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      tools: (json['tools'] as List<dynamic>? ?? [])
          .map((t) => ToolUseRecord.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      imageUrls: urls,
      error: json['error'] as String?,
    );
  }
}
