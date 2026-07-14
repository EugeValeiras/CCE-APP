import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';
import '../../models/server_config.dart';
import '../../theme/cce_tokens.dart';
import 'tool_call_tile.dart';

/// Burbuja de chat en clave neumórfica CCE.
/// Usuario (saliente) = card RAISED tintada-accent anclada a la derecha con
/// esquina mordida abajo-derecha; asistente (entrante) = card RAISED neutra
/// anclada a la izquierda con esquina mordida abajo-izquierda y Markdown.
/// El eje de diferenciación es TINTE + ANCLAJE + ESQUINA MORDIDA (no el color
/// plano verde/gris del look WhatsApp anterior). Ambas son cards "almohada" del
/// mismo idioma que las room/light cards.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  /// Base de la burbuja del usuario: goma teñida violeta (NO un fill saturado
  /// plano). alpha bajo (0.20) para conservar legibilidad del texto blanco y el
  /// look "encendido" sin lavar la superficie.
  static final Color _userBase = Color.alphaBlend(
    CceColors.accent.withValues(alpha: 0.20),
    CceColors.neoBase,
  );

  /// Radios de cola (esquina mordida) en clave neumórfica.
  static const Radius _r = Radius.circular(22);
  static const Radius _bite = Radius.circular(6);

  /// Decoración RAISED-almohada con radio ASIMÉTRICO (replica
  /// CceCard.raisedDecoration a mano porque ese helper usa
  /// BorderRadius.circular y aquí necesitamos BorderRadius.only). La decoración
  /// va SIEMPRE en el contenedor EXTERNO sin clip (cardFloat se recorta si el
  /// contenedor clipea); el contenido clipa aparte.
  static BoxDecoration _bubbleDecoration({
    required Color base,
    required BorderRadius radius,
    bool glow = false,
  }) {
    return BoxDecoration(
      gradient: CceGradients.cardSurface(base),
      borderRadius: radius,
      border: Border.all(color: CceColors.cardBevel),
      boxShadow: [
        ...CceShadows.cardFloat(),
        if (glow) ...CceShadows.glowOn(CceColors.accent.withValues(alpha: 0.35)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUser(context) : _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    const radius = BorderRadius.only(
      topLeft: _r,
      topRight: _r,
      bottomLeft: _r,
      bottomRight: _bite,
    );
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerRight,
        // Contenedor EXTERNO sin clip: lleva la decoración (gradiente + sombra
        // + bevel + glow). El contenido (imágenes) clipa aparte.
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: _bubbleDecoration(
            base: _userBase,
            radius: radius,
            glow: true,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.imageUrls.isNotEmpty) ...[
                _ImageGrid(urls: message.imageUrls),
                if (message.text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: const TextStyle(
                    color: CceColors.textPrimary,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final hasText = message.text.trim().isNotEmpty;
    final showThinking =
        message.streaming && !hasText && message.tools.isEmpty;

    const radius = BorderRadius.only(
      topLeft: _r,
      topRight: _r,
      bottomLeft: _bite,
      bottomRight: _r,
    );

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.86,
          ),
          margin: const EdgeInsets.only(right: 40, top: 4, bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: _bubbleDecoration(
            base: CceColors.neoBase,
            radius: radius,
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
      ),
    );
  }

  Widget _errorBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: CceColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: Border.all(
            color: CceColors.danger.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: CceColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: CceColors.danger, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    // inline-code: azul info (#5AC8FA) legible sobre el well neoSunken.
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: CceColors.info,
    );
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(
          color: CceColors.textPrimary, height: 1.45, fontSize: 14),
      listBullet: const TextStyle(
          color: CceColors.textPrimary, height: 1.45, fontSize: 14),
      strong: const TextStyle(
          color: CceColors.textPrimary, fontWeight: FontWeight.w700),
      em: const TextStyle(
          color: CceColors.textPrimary, fontStyle: FontStyle.italic),
      a: const TextStyle(color: CceColors.accent),
      code: mono,
      // WELL HUNDIDO: color OPACO (neoSunken) obligatorio para que la
      // inner-shadow de neoInset pinte. Más oscuro que la burbuja -> contrasta.
      codeblockDecoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(CceRadii.control),
        boxShadow: CceShadows.neoInset(),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquoteDecoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: CceColors.accent, width: 3),
        ),
      ),
      tableBorder: TableBorder.all(color: CceColors.stroke),
      tableHead: const TextStyle(
          color: CceColors.textPrimary, fontWeight: FontWeight.w700),
      tableBody: const TextStyle(color: CceColors.textSecondary, fontSize: 13),
      h1: const TextStyle(
          color: CceText.titleInk, fontSize: 20, fontWeight: FontWeight.w700),
      h2: const TextStyle(
          color: CceText.titleInk, fontSize: 18, fontWeight: FontWeight.w700),
      h3: const TextStyle(
          color: CceText.titleInk, fontSize: 16, fontWeight: FontWeight.w600),
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
            borderRadius: BorderRadius.circular(CceRadii.control),
            child: SizedBox(
              width: 160,
              height: 160,
              child: _isLocal(u)
                  ? Image.file(File(u), fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => _broken())
                  : Image.network(u, fit: BoxFit.cover,
                      headers: ServerConfig.tokenHeaders,
                      errorBuilder: (ctx, err, stack) => _broken(),
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : _loading()),
            ),
          ),
      ],
    );
  }

  Widget _broken() => Container(
        color: CceColors.neoSunken,
        child: const Icon(Icons.broken_image_outlined,
            color: CceColors.textTertiary, size: 32),
      );

  Widget _loading() => Container(
        color: CceColors.neoSunken,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: CceColors.accent),
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
          child: CircularProgressIndicator(
              strokeWidth: 2, color: CceColors.accent),
        ),
        SizedBox(width: 8),
        Text(
          'escribiendo…',
          style: TextStyle(fontSize: 13, color: CceColors.textSecondary),
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
      color: CceColors.accent,
    );
  }
}
