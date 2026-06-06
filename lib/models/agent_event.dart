/// Events emitted by the CCE-API agent over SSE (`POST /api/agent/chat`) or
/// buffered by the sync fallback (`POST /api/agent/chat/sync`).
///
/// Mirrors the `AgentEvent` JSON union in the API.
sealed class AgentEvent {
  const AgentEvent();

  /// Parses a single decoded SSE `data:` payload into a typed event.
  /// Returns `null` for unknown / malformed payloads so callers can skip them.
  static AgentEvent? fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'thread':
        return ThreadEvent(json['threadId'] as String? ?? '');
      case 'session':
        return SessionEvent(json['sessionId'] as String? ?? '');
      case 'text':
        return TextEvent(json['text'] as String? ?? '');
      case 'tool_use':
        return ToolUseEvent(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          input: json['input'],
        );
      case 'tool_result':
        return ToolResultEvent(
          toolUseId: json['toolUseId'] as String? ?? '',
          content: json['content'] as String? ?? '',
          isError: json['isError'] as bool? ?? false,
        );
      case 'usage':
        return UsageEvent(
          inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
          outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
          cachedTokens: (json['cachedTokens'] as num?)?.toInt() ?? 0,
          costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
        );
      case 'done':
        return DoneEvent(
          result: json['result'] as String?,
          sessionId: json['sessionId'] as String?,
        );
      case 'error':
        return ErrorEvent(json['message'] as String? ?? 'Error desconocido');
      default:
        return null;
    }
  }
}

class ThreadEvent extends AgentEvent {
  final String threadId;
  const ThreadEvent(this.threadId);
}

class SessionEvent extends AgentEvent {
  final String sessionId;
  const SessionEvent(this.sessionId);
}

class TextEvent extends AgentEvent {
  final String text;
  const TextEvent(this.text);
}

class ToolUseEvent extends AgentEvent {
  final String id;
  final String name;
  final dynamic input;
  const ToolUseEvent({required this.id, required this.name, this.input});
}

class ToolResultEvent extends AgentEvent {
  final String toolUseId;
  final String content;
  final bool isError;
  const ToolResultEvent({
    required this.toolUseId,
    required this.content,
    this.isError = false,
  });
}

class UsageEvent extends AgentEvent {
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final double costUsd;
  const UsageEvent({
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    required this.costUsd,
  });
}

class DoneEvent extends AgentEvent {
  final String? result;
  final String? sessionId;
  const DoneEvent({this.result, this.sessionId});
}

class ErrorEvent extends AgentEvent {
  final String message;
  const ErrorEvent(this.message);
}
