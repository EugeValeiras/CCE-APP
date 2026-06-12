import 'package:flutter/material.dart';

import '../../models/chat_thread.dart';
import '../../services/chat_service.dart';
import '../../theme/cce_tokens.dart';

/// End-drawer listing previous conversations with open / new / rename / delete.
/// Rebuilds with the [service] (a ChangeNotifier) — no Provider.
class ThreadHistoryDrawer extends StatelessWidget {
  final ChatService service;
  const ThreadHistoryDrawer({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: CceColors.surface,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Conversaciones',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Nueva conversación',
                        icon: const Icon(Icons.add, color: CceColors.accent),
                        onPressed: () {
                          service.newConversation();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: service.loadingThreads && service.threadList.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white54),
                        )
                      : service.threadList.isEmpty
                          ? const _EmptyHistory()
                          : ListView.builder(
                              itemCount: service.threadList.length,
                              itemBuilder: (context, i) {
                                final thread = service.threadList[i];
                                return _ThreadTile(
                                  service: service,
                                  thread: thread,
                                  selected: thread.id == service.currentThreadId,
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final ChatService service;
  final ThreadSummary thread;
  final bool selected;
  const _ThreadTile({
    required this.service,
    required this.thread,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: CceColors.surfaceHigh,
      title: Text(
        thread.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: thread.lastMessagePreview.isEmpty
          ? null
          : Text(
              thread.lastMessagePreview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white38),
        color: CceColors.surfaceHigh,
        onSelected: (value) async {
          if (value == 'rename') {
            await _rename(context);
          } else if (value == 'delete') {
            await _confirmDelete(context);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'rename',
            child: Text('Renombrar', style: TextStyle(color: Colors.white)),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Eliminar', style: TextStyle(color: CceColors.danger)),
          ),
        ],
      ),
      onTap: () {
        service.openThread(thread.id);
        Navigator.of(context).pop();
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final input = TextEditingController(text: thread.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.surfaceHigh,
        title: const Text('Renombrar conversación',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: input,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Título'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await service.renameThread(thread.id, title);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.surfaceHigh,
        title: const Text('Eliminar conversación',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar "${thread.title}"? No se puede deshacer.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: CceColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.deleteThread(thread.id);
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Todavía no tenés conversaciones.\nEmpezá una nueva.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38),
        ),
      ),
    );
  }
}
