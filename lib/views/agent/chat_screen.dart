import 'package:flutter/material.dart';

import '../../models/server_config.dart';
import '../../services/chat_service.dart';
import 'input_bar.dart';
import 'message_bubble.dart';
import 'thread_history_drawer.dart';

/// WhatsApp-style "Agente" chat tab. Talks to the CCE-API agent over SSE,
/// renders streaming Markdown replies, tool-call chips, images and voice input.
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
      backgroundColor: const Color(0xFF0B1D38),
      endDrawer: ThreadHistoryDrawer(service: _service),
      appBar: AppBar(
        backgroundColor: const Color(0xFF152D54),
        title: const Row(
          children: [
            Icon(Icons.smart_toy_outlined, color: Color(0xFF00A884), size: 22),
            SizedBox(width: 8),
            Text('Asistente', style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Nueva conversación',
            icon: const Icon(Icons.edit_square, color: Colors.white70),
            onPressed: () => _service.newConversation(),
          ),
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history, color: Colors.white70),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          _ModelMenu(service: _service),
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
                          child:
                              CircularProgressIndicator(color: Colors.white54),
                        )
                      : _service.messages.isEmpty
                          ? _EmptyChat(onPick: _onSuggestion)
                          : ListView.builder(
                              controller: _scrollController,
                              // Swipe the messages down to close the keyboard.
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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

class _ModelMenu extends StatelessWidget {
  final ChatService service;
  const _ModelMenu({required this.service});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Modelo',
      color: const Color(0xFF152D54),
      icon: const Icon(Icons.more_vert, color: Colors.white70),
      onSelected: (m) => service.model = m,
      itemBuilder: (_) => [
        for (final m in const ['sonnet', 'opus', 'haiku'])
          CheckedPopupMenuItem(
            value: m,
            checked: service.model == m,
            child: Text(
              m[0].toUpperCase() + m.substring(1),
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _EmptyChat({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_outlined,
                size: 56, color: Color(0xFF00A884)),
            const SizedBox(height: 16),
            const Text(
              'Tu asistente de la casa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Controlá luces, alarma y sensores\nen lenguaje natural. También por voz o foto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _ChatScreenState._suggestions)
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    backgroundColor: const Color(0xFF16213E),
                    labelStyle: const TextStyle(color: Colors.white),
                    side: const BorderSide(color: Colors.white12),
                    onPressed: () => onPick(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
