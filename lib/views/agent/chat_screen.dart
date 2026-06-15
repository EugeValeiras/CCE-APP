import 'package:flutter/material.dart';

import '../../models/server_config.dart';
import '../../services/chat_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_button.dart';
import 'input_bar.dart';
import 'message_bubble.dart';
import 'thread_history_drawer.dart';

/// Tab "Asistente": chat neumórfico contra el agente CCE-API sobre SSE.
/// Renderiza Markdown en streaming, tool-calls, imágenes y voz. La página
/// vive sobre [CceColors.neoBase] para que el relieve de toda la columna lea.
class ChatScreen extends StatefulWidget {
  final ServerConfig config;
  const ChatScreen({super.key, required this.config});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _service;
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _suggestions = [
    '¿Prendé la luz del living?',
    '¿Qué temperatura hace?',
    'Armá la alarma',
    'Mostrame los sensores',
  ];

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.config);
    _service.loadThreads();
  }

  @override
  void dispose() {
    _service.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: CceColors.neoBase,
      endDrawer: ThreadHistoryDrawer(service: _service),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: CceColors.neoBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Hairline de luz en lugar del borde duro: la transición a la lista
        // queda continua (fuente de luz arriba-izquierda).
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: CceColors.cardBevel),
        ),
        title: Row(
          children: [
            EmbossedGlyph(
              size: 22,
              color: CceColors.accent,
              highlight: CceEmboss.highlight.color,
              shadow: CceEmboss.shadow.color,
              child: const Icon(Icons.smart_toy_outlined),
            ),
            const SizedBox(width: 10),
            const Text('Asistente',
                style: TextStyle(
                    color: CceText.titleInk, shadows: CceText.embossShadows)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: CceNeoIconButton(
              icon: Icons.edit_square,
              tooltip: 'Nueva conversación',
              size: 40,
              onPressed: () => _service.newConversation(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: CceNeoIconButton(
              icon: Icons.history,
              tooltip: 'Historial',
              size: 40,
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ModelMenu(service: _service),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          if (_service.streaming) _scrollToBottom();
          return Column(
            children: [
              Expanded(
                // Tap anywhere on the chat area to dismiss the keyboard
                // (otherwise the multiline field traps it and covers the tabs).
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: _service.loadingThread
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: CceColors.accent),
                        )
                      : _service.messages.isEmpty
                          ? _EmptyChat(onPick: _onSuggestion)
                          : ListView.builder(
                              controller: _scrollController,
                              // Swipe the messages down to close the keyboard.
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              itemCount: _service.messages.length,
                              itemBuilder: (context, i) =>
                                  MessageBubble(message: _service.messages[i]),
                            ),
                ),
              ),
              InputBar(service: _service),
            ],
          );
        },
      ),
    );
  }

  void _onSuggestion(String text) {
    _scrollToBottom();
    _service.sendMessage(text);
  }
}

/// Selector de modelo: botón neo redondo que dispara un menú sobre superficie
/// hundida (neoSunken). Conserva la lista y el setter [ChatService.model].
class _ModelMenu extends StatelessWidget {
  final ChatService service;
  const _ModelMenu({required this.service});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Modelo',
      color: CceColors.neoSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CceRadii.control),
      ),
      position: PopupMenuPosition.under,
      onSelected: (m) => service.model = m,
      // El child es el botón neo press-to-inset (no usa onPressed propio: el
      // PopupMenuButton abre el menú al tocar el child).
      child: const _NeoMenuTarget(),
      itemBuilder: (_) => [
        for (final m in const ['sonnet', 'opus', 'haiku'])
          CheckedPopupMenuItem(
            value: m,
            checked: service.model == m,
            checkmarkColor: CceColors.accent,
            child: Text(
              m[0].toUpperCase() + m.substring(1),
              style: const TextStyle(color: CceColors.textPrimary),
            ),
          ),
      ],
    );
  }
}

/// Círculo neo raised estático que sirve de target del PopupMenuButton del
/// modelo (replica el look de [CceNeoIconButton] sin gesto propio, ya que el
/// tap lo consume el PopupMenuButton padre).
class _NeoMenuTarget extends StatelessWidget {
  const _NeoMenuTarget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.neoBase,
        boxShadow: CceShadows.neo(blur: 8, offset: 3),
      ),
      child: const Icon(Icons.more_vert, size: 20, color: CceColors.neoText),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _EmptyChat({required this.onPick});

  @override
  Widget build(BuildContext context) {
    // Tótem extruido: glifo grande embossado dentro de un círculo neo raised.
    final (hi, sh) = EmbossedGlyph.surfaceEmboss(CceColors.neoBase);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CceColors.neoBase,
                boxShadow: CceShadows.neo(blur: 16, offset: 7),
              ),
              child: EmbossedGlyph(
                size: 56,
                color: CceColors.accent,
                highlight: hi,
                shadow: sh,
                child: const Icon(Icons.smart_toy_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tu asistente de la casa',
              style: CceText.title,
            ),
            const SizedBox(height: 10),
            const Text(
              'Controlá luces, alarma y sensores\nen lenguaje natural. También por voz o foto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CceColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _ChatScreenState._suggestions)
                  _NeoSuggestionChip(label: s, onPick: () => onPick(s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de sugerencia: pill neo raised que se hunde a inset al presionar
/// (replica el patrón de [CceNeoActionButton] con tamaño/tipografía de chip).
class _NeoSuggestionChip extends StatefulWidget {
  final String label;
  final VoidCallback onPick;
  const _NeoSuggestionChip({required this.label, required this.onPick});

  @override
  State<_NeoSuggestionChip> createState() => _NeoSuggestionChipState();
}

class _NeoSuggestionChipState extends State<_NeoSuggestionChip> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          // Color opaco obligatorio para que el inset (BlurStyle.inner) pinte.
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          boxShadow: _pressed
              ? CceShadows.neoInset(blur: 6, offset: 2)
              : CceShadows.neo(blur: 8, offset: 3),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: CceColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
