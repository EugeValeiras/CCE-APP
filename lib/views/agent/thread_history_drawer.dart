import 'package:flutter/material.dart';

import '../../models/chat_thread.dart';
import '../../services/chat_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_button.dart';

/// End-drawer listing previous conversations with open / new / rename / delete.
/// Rebuilds with the [service] (a ChangeNotifier) — no Provider.
class ThreadHistoryDrawer extends StatelessWidget {
  final ChatService service;
  const ThreadHistoryDrawer({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: CceColors.neoBase,
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
                      Text(
                        'Conversaciones',
                        style: CceText.title.copyWith(fontSize: 16),
                      ),
                      const Spacer(),
                      CceNeoIconButton(
                        icon: Icons.add,
                        tooltip: 'Nueva conversación',
                        size: 40,
                        onPressed: () {
                          service.newConversation();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: CceColors.stroke),
                Expanded(
                  child: service.loadingThreads && service.threadList.isEmpty
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: CceColors.accent),
                        )
                      : service.threadList.isEmpty
                          ? const _EmptyHistory()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                              itemCount: service.threadList.length,
                              itemBuilder: (context, i) {
                                final thread = service.threadList[i];
                                return ThreadTile(
                                  service: service,
                                  thread: thread,
                                  selected:
                                      thread.id == service.currentThreadId,
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

class ThreadTile extends StatelessWidget {
  final ChatService service;
  final ThreadSummary thread;
  final bool selected;

  /// Si true (drawer del teléfono), cierra el Navigator al abrir un hilo. En el
  /// sidebar fijo de la tablet es false (no hay drawer que cerrar).
  final bool popOnOpen;

  const ThreadTile({
    super.key,
    required this.service,
    required this.thread,
    required this.selected,
    this.popOnOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    // SELECCIONADO = well hundido (neoSunken + neoInset, color opaco
    // obligatorio para BlurStyle.inner); NO seleccionado = plano sutil sobre
    // neoBase para no saturar la lista. La sombra interna vive en la misma
    // decoración (no overlay), así no recorta nada.
    final decoration = selected
        ? BoxDecoration(
            color: CceColors.neoSunken,
            borderRadius: BorderRadius.circular(CceRadii.tile),
            boxShadow: CceShadows.neoInset(),
          )
        : BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.tile),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(CceRadii.tile),
          onTap: () {
            service.openThread(thread.id);
            if (popOnOpen) Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CceColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      if (thread.lastMessagePreview.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          thread.lastMessagePreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CceColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    size: 18,
                    color: CceColors.textTertiary,
                  ),
                  color: CceColors.neoSunken,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CceRadii.control),
                  ),
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
                      child: Text('Renombrar',
                          style: TextStyle(color: CceColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar',
                          style: TextStyle(color: CceColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final input = TextEditingController(text: thread.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CceColors.neoBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CceRadii.card),
        ),
        title: const Text('Renombrar conversación',
            style: TextStyle(color: CceColors.textPrimary)),
        // Well hundido coherente con los inputs del resto de la app: color
        // opaco neoSunken obligatorio para que la inner-shadow pinte, y
        // padding interno suficiente para despegar el cursor del inset.
        content: Container(
          decoration: BoxDecoration(
            color: CceColors.neoSunken,
            borderRadius: BorderRadius.circular(CceRadii.control),
            boxShadow: CceShadows.neoInset(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: input,
            autofocus: true,
            cursorColor: CceColors.accent,
            style: const TextStyle(color: CceColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Título',
              hintStyle: TextStyle(color: CceColors.textTertiary),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
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
        backgroundColor: CceColors.neoBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CceRadii.card),
        ),
        title: const Text('Eliminar conversación',
            style: TextStyle(color: CceColors.textPrimary)),
        content: Text(
          '¿Eliminar "${thread.title}"? No se puede deshacer.',
          style: const TextStyle(color: CceColors.textSecondary),
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
    // Glyph grande extruido de la goma (size >= CceEmboss.minSize) como tótem
    // de identidad del estado vacío; par highlight/shadow derivado de neoBase.
    final (hi, sh) = EmbossedGlyph.surfaceEmboss(CceColors.neoBase);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmbossedGlyph(
              size: 48,
              color: CceColors.accent,
              highlight: hi,
              shadow: sh,
              child: const Icon(Icons.forum_outlined),
            ),
            const SizedBox(height: 16),
            const Text(
              'Todavía no tenés conversaciones.\nEmpezá una nueva.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CceColors.textTertiary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
