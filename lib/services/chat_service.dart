import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/agent_event.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/server_config.dart';

/// Owns the Agente chat UI state: thread list, the open conversation, and the
/// in-flight streaming turn. Talks to the CCE-API agent over SSE (package:http)
/// with a buffered sync fallback.
class ChatService extends ChangeNotifier {
  final ServerConfig config;

  ChatService(this.config);

  String get _base => config.baseUrl; // e.g. http://host:port/api

  // ── Open conversation ──────────────────────────────────────────────────────
  final List<ChatMessage> messages = [];
  bool streaming = false;
  bool loadingThread = false;
  String? currentThreadId;
  String? claudeSessionId;
  String model = 'sonnet'; // 'sonnet' | 'opus' | 'haiku'

  // ── Thread list ────────────────────────────────────────────────────────────
  List<ThreadSummary> threadList = [];
  bool loadingThreads = false;

  // ── Streaming internals ─────────────────────────────────────────────────────
  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  bool _aborted = false;

  // ── Thread list operations ─────────────────────────────────────────────────
  Future<void> loadThreads() async {
    loadingThreads = true;
    notifyListeners();
    try {
      final resp = await http
          .get(Uri.parse('$_base/agent/threads'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data is List ? data : (data['threads'] as List? ?? []);
        threadList = list
            .map((t) => ThreadSummary.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('[ChatService] loadThreads error: $e');
    } finally {
      loadingThreads = false;
      notifyListeners();
    }
  }

  /// Starts a fresh, unsaved conversation. The thread is created server-side on
  /// the first message (its id arrives via the `thread` event).
  void newConversation() {
    if (streaming) abort();
    currentThreadId = null;
    claudeSessionId = null;
    messages.clear();
    notifyListeners();
  }

  Future<void> openThread(String id) async {
    if (streaming) abort();
    loadingThread = true;
    currentThreadId = id;
    messages.clear();
    notifyListeners();
    try {
      final resp = await http
          .get(Uri.parse('$_base/agent/threads/${Uri.encodeComponent(id)}'))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final detail = ThreadDetail.fromJson(
          Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
          baseUrl: _base,
        );
        claudeSessionId = detail.claudeSessionId;
        model = detail.model;
        messages
          ..clear()
          ..addAll(detail.messages);
      }
    } catch (e) {
      debugPrint('[ChatService] openThread error: $e');
    } finally {
      loadingThread = false;
      notifyListeners();
    }
  }

  Future<void> renameThread(String id, String title) async {
    try {
      await http
          .patch(
            Uri.parse('$_base/agent/threads/${Uri.encodeComponent(id)}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'title': title}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[ChatService] renameThread error: $e');
    }
    await loadThreads();
  }

  Future<void> deleteThread(String id) async {
    try {
      await http
          .delete(Uri.parse('$_base/agent/threads/${Uri.encodeComponent(id)}'))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[ChatService] deleteThread error: $e');
    }
    if (currentThreadId == id) newConversation();
    await loadThreads();
  }

  // ── Sending a message ───────────────────────────────────────────────────────
  Future<void> sendMessage(String text, {List<XFile> images = const []}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && images.isEmpty) || streaming) return;

    // User bubble — local paths for instant image display.
    messages.add(ChatMessage(
      id: _randomId(),
      role: 'user',
      text: trimmed,
      imageUrls: images.map((x) => x.path).toList(),
    ));

    final assistant = ChatMessage(
      id: _randomId(),
      role: 'assistant',
      streaming: true,
    );
    messages.add(assistant);

    streaming = true;
    _aborted = false;
    notifyListeners();

    // Base64-encode any images for the request body.
    final encodedImages = <Map<String, String>>[];
    for (final img in images) {
      try {
        final bytes = await img.readAsBytes();
        encodedImages.add({
          'data': base64Encode(bytes),
          'mediaType': _mediaType(img.path),
        });
      } catch (e) {
        debugPrint('[ChatService] image encode error: $e');
      }
    }

    final payload = <String, dynamic>{
      'message': trimmed,
      if (currentThreadId != null) 'threadId': currentThreadId,
      'model': model,
      if (encodedImages.isNotEmpty) 'images': encodedImages,
    };

    try {
      await _stream(payload, assistant);
    } catch (e) {
      debugPrint('[ChatService] stream failed, trying sync fallback: $e');
      try {
        await _syncFallback(payload, assistant);
      } catch (e2) {
        if (!_aborted) assistant.error = 'No se pudo contactar al agente.';
      }
    } finally {
      assistant.streaming = false;
      streaming = false;
      _client?.close();
      _client = null;
      _sub = null;
      notifyListeners();
      await loadThreads();
    }
  }

  /// Opens the SSE stream and applies events to [assistant] as they arrive.
  Future<void> _stream(
    Map<String, dynamic> payload,
    ChatMessage assistant,
  ) async {
    final client = http.Client();
    _client = client;

    final req = http.Request('POST', Uri.parse('$_base/agent/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(payload);

    // No .timeout on the stream — an agent turn can take minutes.
    final resp = await client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode >= 400) {
      throw http.ClientException('HTTP ${resp.statusCode}');
    }

    final completer = Completer<void>();
    final buffer = <int>[];

    void flushBlocks() {
      var sep = _indexOfDoubleNewline(buffer);
      while (sep != -1) {
        final block = utf8.decode(buffer.sublist(0, sep), allowMalformed: true);
        buffer.removeRange(0, sep + 2);
        for (final event in _parseBlock(block)) {
          _handleEvent(event, assistant);
        }
        sep = _indexOfDoubleNewline(buffer);
      }
    }

    _sub = resp.stream.listen(
      (chunk) {
        buffer.addAll(chunk);
        flushBlocks();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        // Flush any trailing block without a final separator.
        if (buffer.isNotEmpty) {
          final block = utf8.decode(buffer, allowMalformed: true);
          for (final event in _parseBlock(block)) {
            _handleEvent(event, assistant);
          }
        }
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  /// Buffered fallback: gets the whole turn at once and replays its events.
  Future<void> _syncFallback(
    Map<String, dynamic> payload,
    ChatMessage assistant,
  ) async {
    final resp = await http
        .post(
          Uri.parse('$_base/agent/chat/sync'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode >= 400) {
      throw http.ClientException('HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final events = data['events'] as List<dynamic>? ?? [];
    for (final raw in events) {
      final event = AgentEvent.fromJson(Map<String, dynamic>.from(raw as Map));
      if (event != null) _handleEvent(event, assistant);
    }
  }

  void _handleEvent(AgentEvent event, ChatMessage assistant) {
    switch (event) {
      case ThreadEvent(:final threadId):
        currentThreadId ??= threadId.isEmpty ? null : threadId;
      case SessionEvent(:final sessionId):
        if (sessionId.isNotEmpty) claudeSessionId = sessionId;
      case TextEvent(:final text):
        assistant.text += text;
      case ToolUseEvent(:final id, :final name, :final input):
        assistant.tools.add(ToolUseRecord(id: id, name: name, input: input));
      case ToolResultEvent(:final toolUseId, :final content, :final isError):
        for (final tool in assistant.tools) {
          if (tool.id == toolUseId) {
            tool.result = content;
            tool.isError = isError;
            break;
          }
        }
      case UsageEvent():
        break;
      case DoneEvent(:final sessionId):
        if (sessionId != null && sessionId.isNotEmpty) {
          claudeSessionId = sessionId;
        }
      case ErrorEvent(:final message):
        assistant.error = message;
    }
    notifyListeners();
  }

  /// Aborts the in-flight turn, keeping whatever was streamed so far.
  void abort() {
    if (!streaming) return;
    _aborted = true;
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    for (final m in messages) {
      if (m.streaming) m.streaming = false;
    }
    streaming = false;
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Iterable<AgentEvent> _parseBlock(String block) sync* {
    for (final line in block.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final event = AgentEvent.fromJson(json);
        if (event != null) yield event;
      } catch (_) {
        // skip malformed payloads
      }
    }
  }

  int _indexOfDoubleNewline(List<int> bytes) {
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x0A && bytes[i + 1] == 0x0A) return i;
    }
    return -1;
  }

  String _mediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  String _randomId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${identityHashCode(Object()).toRadixString(36)}';

  @override
  void dispose() {
    _sub?.cancel();
    _client?.close();
    super.dispose();
  }
}
