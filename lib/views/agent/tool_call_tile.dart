import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';

/// Collapsible chip showing a single agent tool call and its result.
///
/// Neumorfismo: mini-card RAISED (almohada flotante) cuya sombra/gradiente/bevel
/// vive en un contenedor EXTERNO sin clip (via [CceCard.raisedDecoration]); el
/// InkWell de expand/collapse clipea aparte (Material transparency) para no
/// recortar la sombra. Los bloques de codigo (input/resultado/error) son WELLS
/// HUNDIDOS (neoSunken opaco + neoInset). Sin BackdropFilter; cards baratas.
class ToolCallTile extends StatefulWidget {
  final ToolUseRecord tool;
  const ToolCallTile({super.key, required this.tool});

  @override
  State<ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<ToolCallTile> {
  bool _expanded = false;

  static const _mono = TextStyle(fontFamily: 'monospace');
  // Color de pending: amarillo "warn" coherente con la app.
  static const _pendingColor = Color(0xFFFFB46B);
  static const _radius = CceRadii.tile; // 22

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final pending = tool.result == null;
    final color = tool.isError
        ? CceColors.danger
        : pending
            ? _pendingColor
            : CceColors.ok;

    final borderRadius = BorderRadius.circular(_radius);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      // Contenedor EXTERNO sin clip: pinta gradiente + cardFloat + bevel.
      child: DecoratedBox(
        decoration: CceCard.raisedDecoration(
          base: CceColors.neoBase,
          radius: _radius,
        ),
        // Contenedor INTERNO clipeado: el InkWell del expand/collapse y el
        // contenido recortan aca, NO la sombra externa.
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        if (pending)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
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
                              color: CceColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: CceColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  const Divider(height: 1, color: CceColors.stroke),
                  Padding(
                    padding: const EdgeInsets.all(12),
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
          ),
        ),
      ),
    );
  }

  /// Etiqueta de seccion (uppercase, tertiary, tracking) reusando CceText.section.
  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: CceText.section.copyWith(fontSize: 10, letterSpacing: 0.8),
        ),
      );

  /// WELL HUNDIDO: color OPACO neoSunken (requisito de BlurStyle.inner) +
  /// inner-shadow neoInset. El contentPadding despega el texto del inner-shadow.
  Widget _code(String text) {
    final clipped =
        text.length > 3000 ? '${text.substring(0, 3000)}…' : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(CceRadii.control),
        boxShadow: CceShadows.neoInset(),
      ),
      child: SelectableText(
        clipped,
        style: _mono.copyWith(
          fontSize: 11,
          color: CceColors.textSecondary,
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
