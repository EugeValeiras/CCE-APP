import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../theme/cce_tokens.dart';
import 'automation_card.dart' show automationIcon, triggerColor;

/// Reordenar las automatizaciones desde el teléfono (CCE#79).
///
/// La lista principal las agrupa por sección (sensor / programadas /
/// manuales / desactivadas) en una grilla, y una grilla con secciones no se
/// arrastra. Acá van TODAS, planas, en el orden del servidor — el mismo que
/// muestra el Dashboard — con un asa por fila. Soltar guarda: GET fresco →
/// orden nuevo → PUT, por la cola de escritura del servicio.
class AutomationsOrderPage extends StatefulWidget {
  const AutomationsOrderPage({super.key, required this.service});

  final AutomationsService service;

  @override
  State<AutomationsOrderPage> createState() => _AutomationsOrderPageState();
}

class _AutomationsOrderPageState extends State<AutomationsOrderPage> {
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // onReorder entrega newIndex SIN ajustar por el item removido.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final ids = [for (final a in widget.service.automations) a.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    final result = await widget.service.reorder(ids);
    if (!mounted || result.ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'No se pudo guardar el orden')),
    );
  }

  String _caption(Automation a) {
    final kind = switch (a.trigger.type) {
      'sensor' => 'Por sensor',
      'schedule' => 'Programada',
      _ => 'Manual',
    };
    return a.enabled ? kind : '$kind · desactivada';
  }

  Widget _row(Automation a, int index) {
    final color = triggerColor(a);
    final enabled = a.enabled;
    return Padding(
      key: ValueKey(a.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 64,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: CceColors.surface,
          borderRadius: BorderRadius.circular(CceRadii.control),
        ),
        child: Row(
          children: [
            // SOLO el asa arranca el drag (56 px para el pulgar): la fila
            // entera como handle se pelea con el scroll de la lista.
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 56,
                height: 64,
                child: Icon(Icons.drag_handle_rounded,
                    color: CceColors.textTertiary),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? color.withValues(alpha: 0.18)
                    : CceColors.surfaceHigh,
              ),
              child: automationIcon(a.icon,
                  size: 20, color: enabled ? color : CceColors.textTertiary),
            ),
            SizedBox(width: CceSpace.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: CceText.body.copyWith(
                      color: enabled
                          ? CceColors.textPrimary
                          : CceColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(_caption(a), style: CceText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: CceColors.textPrimary),
                  ),
                  SizedBox(width: CceSpace.xs),
                  const Expanded(
                    child: Text(
                      'Ordenar',
                      style: CceText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 0, 14),
                child: Text(
                  'Arrastrá desde el asa. Es el mismo orden que en el '
                  'Dashboard.',
                  style: CceText.caption,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.service,
                  builder: (context, _) {
                    final items = widget.service.automations;
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(left: 8, bottom: 24),
                      itemCount: items.length,
                      onReorder: _onReorder,
                      // Sin el Material blanco que el decorador por defecto
                      // pone debajo de la fila que viaja.
                      proxyDecorator: (child, _, _) =>
                          Material(color: Colors.transparent, child: child),
                      itemBuilder: (context, i) => _row(items[i], i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
