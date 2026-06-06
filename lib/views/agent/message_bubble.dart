import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';
import 'tool_call_tile.dart';

/// WhatsApp-style chat bubble using the CCE dark palette.
/// User (outgoing) bubbles are right-aligned in a dark-green; assistant
/// (incoming) bubbles are left-aligned in the app card color and render Markdown.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  static const _outgoing = Color(0xFF075E54); // WhatsApp-ish dark green
  static const _incoming = Color(0xFF1E2A44); // app card color

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUser(context) : _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: _outgoing,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.imageUrls.isNotEmpty) ...[
              _ImageGrid(urls: message.imageUrls),
              if (message.text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final hasText = message.text.trim().isNotEmpty;
    final showThinking =
        message.streaming && !hasText && message.tools.isEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        margin: const EdgeInsets.only(right: 40, top: 4, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: _incoming,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in message.tools) ToolCallTile(tool: tool),
            if (message.tools.isNotEmpty && (hasText || showThinking))
              const SizedBox(height: 6),
            if (showThinking) const _ThinkingIndicator(),
            if (hasText)
              MarkdownBody(
                data: message.text,
                selectable: true,
                styleSheet: _markdownStyle(context),
              ),
            if (message.streaming && hasText) const _Caret(),
            if (message.error != null) ...[
              const SizedBox(height: 6),
              _errorBox(message.error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6465D).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFF6465D).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: Color(0xFFF6465D)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFFF6465D), fontSize: 13),
              ),
            ),
          ],
        ),
      );

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: Color(0xFF9FD3FF),
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(color: Colors.white, height: 1.45, fontSize: 14),
      listBullet:
          const TextStyle(color: Colors.white, height: 1.45, fontSize: 14),
      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      em: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
      a: const TextStyle(color: Color(0xFF4DD0E1)),
      code: mono,
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0B1D38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0xFF152D54),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: Color(0xFF4DD0E1), width: 3),
        ),
      ),
      tableBorder: TableBorder.all(color: Colors.white12),
      tableHead:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      tableBody: const TextStyle(color: Colors.white70, fontSize: 13),
      h1: const TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
      h2: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      h3: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
    );
  }
}

/// Renders one or more image thumbnails. Local paths use Image.file, remote
/// URLs use Image.network.
class _ImageGrid extends StatelessWidget {
  final List<String> urls;
  const _ImageGrid({required this.urls});

  bool _isLocal(String u) => !u.startsWith('http');

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final u in urls)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 160,
              height: 160,
              child: _isLocal(u)
                  ? Image.file(File(u), fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => _broken())
                  : Image.network(u, fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => _broken(),
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : _loading()),
            ),
          ),
      ],
    );
  }

  Widget _broken() => Container(
        color: Colors.black26,
        child: const Icon(Icons.broken_image_outlined,
            color: Colors.white38, size: 32),
      );

  Widget _loading() => Container(
        color: Colors.black26,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text(
          'escribiendo…',
          style: TextStyle(fontSize: 13, color: Colors.white60),
        ),
      ],
    );
  }
}

class _Caret extends StatelessWidget {
  const _Caret();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      width: 7,
      height: 14,
      color: const Color(0xFF4DD0E1),
    );
  }
}
