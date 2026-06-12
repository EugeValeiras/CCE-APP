import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../theme/cce_tokens.dart';

/// Collapsible chip showing a single agent tool call and its result.
class ToolCallTile extends StatefulWidget {
  final ToolUseRecord tool;
  const ToolCallTile({super.key, required this.tool});

  @override
  State<ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<ToolCallTile> {
  bool _expanded = false;

  static const _mono = TextStyle(fontFamily: 'monospace');

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final pending = tool.result == null;
    final color = tool.isError
        ? CceColors.danger
        : pending
            ? const Color(0xFFF0B90B)
            : CceColors.ok;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (pending)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      tool.isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 14,
                      color: color,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      tool.name,
                      style: _mono.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tool.input != null) ...[
                    _label('Input'),
                    _code(_pretty(tool.input)),
                  ],
                  if (tool.result != null) ...[
                    const SizedBox(height: 8),
                    _label(tool.isError ? 'Error' : 'Resultado'),
                    _code(tool.result!),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: Colors.white38,
          ),
        ),
      );

  Widget _code(String text) {
    final clipped =
        text.length > 3000 ? '${text.substring(0, 3000)}…' : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: CceColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        clipped,
        style: _mono.copyWith(
          fontSize: 11,
          color: Colors.white70,
          height: 1.4,
        ),
      ),
    );
  }

  String _pretty(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
