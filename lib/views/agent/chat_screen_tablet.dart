import 'package:flutter/material.dart';

import '../../models/server_config.dart';
import '../../services/chat_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_button.dart';
import 'input_bar.dart';
import 'message_bubble.dart';
import 'thread_history_drawer.dart'; // ThreadTile (reusado)

/// Variante TABLET del Asistente, con el layout de DOS COLUMNAS del dashboard
/// web (que al usuario le gusta): sidebar fijo de conversaciones a la izquierda
/// + chat centrado a la derecha (topbar con selector de modelo en chips, lista
/// de mensajes con ancho máximo y composer centrado).
///
/// Reusa toda la maquinaria existente: [ChatService] (estado + SSE),
/// [MessageBubble], [InputBar] y [ThreadTile]. El teléfono sigue usando
/// [ChatScreen] (full-screen, historial en end-drawer) sin cambios.
class ChatScreenTablet extends StatefulWidget {
  final ServerConfig config;
  const ChatScreenTablet({super.key, required this.config});

  @override
  State<ChatScreenTablet> createState() => _ChatScreenTabletState();
}

class _ChatScreenTabletState extends State<ChatScreenTablet> {
  late final ChatService _service;
  final _scrollController = ScrollController();

  /// Ancho de la columna de chat (mensajes + composer), centrada como en el
  /// dashboard para que las líneas no se estiren a lo ancho del iPad.
  static const double _colMaxWidth = 820;

  /// Sugerencias del estado vacío: (ícono SVG vendoreado, texto). Espeja las
  /// del dashboard web — mismas 6, con ícono accent a la izquierda.
  static const _suggestions = <(String, String)>[
    (CceIcons.lights, 'Prendé la luz del living'),
    (CceIcons.thermometer, '¿Qué temperatura hace?'),
    (CceIcons.alarmShield, 'Armá la alarma'),
    (CceIcons.sensors, 'Mostrame los sensores'),
    (CceIcons.sun, 'Poné el cuarto al 30%'),
    (CceIcons.users, '¿Hay alguien en la oficina?'),
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

  void _onSuggestion(String text) {
    _scrollToBottom();
    _service.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Sidebar de conversaciones (como el dashboard) ──────────────
            SizedBox(width: 280, child: _Sidebar(service: _service)),
            const VerticalDivider(
                width: 1, thickness: 1, color: CceColors.cardBevel),
            // ── Chat ───────────────────────────────────────────────────────
            Expanded(
              child: AnimatedBuilder(
                animation: _service,
                builder: (context, _) {
                  if (_service.streaming) _scrollToBottom();
                  return Column(
                    children: [
                      _Topbar(service: _service),
                      const Divider(
                          height: 1, thickness: 1, color: CceColors.cardBevel),
                      Expanded(
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
                                  : Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: _colMaxWidth),
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          keyboardDismissBehavior:
                                              ScrollViewKeyboardDismissBehavior
                                                  .onDrag,
                                          padding: const EdgeInsets.fromLTRB(
                                              20, 12, 20, 12),
                                          itemCount: _service.messages.length,
                                          itemBuilder: (context, i) =>
                                              MessageBubble(
                                                  message:
                                                      _service.messages[i]),
                                        ),
                                      ),
                                    ),
                        ),
                      ),
                      // Composer centrado, alineado con la columna de mensajes.
                      Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: _colMaxWidth),
                          child: InputBar(service: _service, embedded: true),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sidebar de conversaciones: header con "Nueva" + lista de [ThreadTile].
class _Sidebar extends StatelessWidget {
  final ChatService service;
  const _Sidebar({required this.service});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
          child: Row(
            children: [
              Text('Conversaciones', style: CceText.title.copyWith(fontSize: 16)),
              const Spacer(),
              CceNeoIconButton(
                icon: Icons.edit_square,
                tooltip: 'Nueva conversación',
                size: 38,
                onPressed: service.newConversation,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: CceColors.stroke),
        Expanded(
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              if (service.loadingThreads && service.threadList.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: CceColors.accent),
                );
              }
              if (service.threadList.isEmpty) {
                return const _SidebarEmpty();
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                itemCount: service.threadList.length,
                itemBuilder: (context, i) {
                  final t = service.threadList[i];
                  return ThreadTile(
                    service: service,
                    thread: t,
                    selected: t.id == service.currentThreadId,
                    // En el sidebar (no es un drawer) NO hay que cerrar nada al
                    // abrir un hilo: solo carga en el panel de la derecha.
                    popOnOpen: false,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SidebarEmpty extends StatelessWidget {
  const _SidebarEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Todavía no tenés conversaciones.\nEmpezá una nueva.',
          textAlign: TextAlign.center,
          style: TextStyle(color: CceColors.textTertiary, height: 1.5),
        ),
      ),
    );
  }
}

/// Topbar del panel de chat: título del hilo + selector de modelo (como el
/// dashboard web). El título sale del hilo activo (o "Nueva conversación").
class _Topbar extends StatelessWidget {
  final ChatService service;
  const _Topbar({required this.service});

  String get _title {
    final id = service.currentThreadId;
    if (id == null) return 'Nueva conversación';
    for (final t in service.threadList) {
      if (t.id == id) return t.title;
    }
    return 'Conversación';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: CceText.titleInk,
                shadows: CceText.embossShadows,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text('MODELO', style: CceText.section.copyWith(fontSize: 10.5)),
          const SizedBox(width: 8),
          _ModelChips(service: service),
        ],
      ),
    );
  }
}

/// Selector de modelo en chips (segmented), espejando el del dashboard. Maneja
/// su propio [setState] porque [ChatService.model] es un campo simple (no
/// dispara notifyListeners al asignarse).
class _ModelChips extends StatefulWidget {
  final ChatService service;
  const _ModelChips({required this.service});

  @override
  State<_ModelChips> createState() => _ModelChipsState();
}

class _ModelChipsState extends State<_ModelChips> {
  static const _models = ['sonnet', 'opus', 'haiku'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(CceRadii.pill),
        boxShadow: CceShadows.neoInset(blur: 5, offset: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final m in _models) _chip(m)],
      ),
    );
  }

  Widget _chip(String m) {
    final active = widget.service.model == m;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!active) setState(() => widget.service.model = m);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? CceColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(CceRadii.pill),
        ),
        child: Text(
          m[0].toUpperCase() + m.substring(1),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : CceColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Estado vacío del chat (centrado): tótem + título + sugerencias.
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
            // Hero liviano: círculo con tinte accent + destello (sparkles),
            // espejando el del dashboard (en vez del robot pesado embossado).
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CceColors.accent.withOpacity(0.14),
              ),
              child: const CceIcon(
                CceIcons.scenes,
                size: 36,
                color: CceColors.accent,
                emboss: false,
              ),
            ),
            const SizedBox(height: 20),
            const Text('Tu asistente de la casa', style: CceText.title),
            const SizedBox(height: 10),
            const Text(
              'Controlá luces, alarma y sensores\nen lenguaje natural. También por voz o foto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CceColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in _ChatScreenTabletState._suggestions)
                    _SuggestionChip(
                      icon: s.$1,
                      label: s.$2,
                      onPick: () => onPick(s.$2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de sugerencia: pill neo raised → inset al presionar (mismo patrón que
/// el de [ChatScreen]).
class _SuggestionChip extends StatefulWidget {
  final String icon;
  final String label;
  final VoidCallback onPick;
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onPick,
  });

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
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
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          boxShadow: _pressed
              ? CceShadows.neoInset(blur: 6, offset: 2)
              : CceShadows.neo(blur: 8, offset: 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CceIcon(
              widget.icon,
              size: 15,
              color: CceColors.accent,
              emboss: false,
            ),
            const SizedBox(width: 7),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: CceColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
