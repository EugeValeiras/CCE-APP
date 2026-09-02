import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../models/server_config.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/section_header.dart';
import 'automation_card.dart';
import 'automation_wizard_page.dart';
import 'automations_order_page.dart';

/// Vista de Automatizaciones (destino del rail, índice 1).
///
/// Contrato para B (§0.7): `AutomationsView(devices: ..., config: ...)`.
class AutomationsView extends StatefulWidget {
  const AutomationsView({
    super.key,
    required this.devices,
    required this.config,
  });

  /// Read-only: byId, displayName, automationName, socket, grupos/escenas.
  final DevicesService devices;

  /// Para construir [AutomationsService] (baseUrl).
  final ServerConfig config;

  @override
  State<AutomationsView> createState() => _AutomationsViewState();
}

class _AutomationsViewState extends State<AutomationsView> {
  late final AutomationsService _service;
  Timer? _ticker;

  /// Id de la automation con confirmación de borrado inline visible.
  String? _confirmingDeleteId;

  @override
  void initState() {
    super.initState();
    _service =
        AutomationsService(config: widget.config, devices: widget.devices);
    // Ticker de 30 s: "Última vez: hace 5 min" no puede mentir.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _service.dispose();
    super.dispose();
  }

  /// Abre el wizard (CCE#66) sobre una copia descartable. Un flujo que no
  /// entra en el molde se muestra en solo lectura desde la misma página.
  Future<void> _openEditor(Automation? existing) async {
    final draft = existing?.copyForEdit() ?? Automation.blank();
    final result = await Navigator.of(context).push(
      MaterialPageRoute<Object?>(
        builder: (_) => AutomationWizardPage(
          service: _service,
          devices: widget.devices,
          draft: draft,
          isNew: existing == null,
        ),
      ),
    );
    if (!mounted) return;
    // El editor devuelve 'deleted' tras borrar: la lista ofrece el DESHACER
    // que el dialogo del editor promete (el editor no tiene ScaffoldMessenger
    // propio una vez que hace pop).
    if (result == 'deleted') _showUndoDeleteSnackBar();
  }

  void _showUndoDeleteSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Eliminada'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'DESHACER',
          onPressed: () => _service.undoDelete(),
        ),
      ),
    );
  }

  /// Duplica: copia el raw con id nuevo, nombre " (copia)" y DESHABILITADA
  /// (para que no dispare mientras se ajusta), y abre el editor con ese draft.
  Future<void> _duplicate(Automation a) async {
    final copy = Automation.fromJson({
      ...a.toJson(),
      'id': newAutomationId(),
      'name': '${a.name} (copia)',
      'enabled': false,
    });
    await Navigator.of(context).push(
      MaterialPageRoute<Object?>(
        builder: (_) => AutomationWizardPage(
          service: _service,
          devices: widget.devices,
          draft: copy,
          isNew: true,
        ),
      ),
    );
  }

  Future<void> _showCardMenu(Automation a) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const CceIcon(CceIcons.play,
                  size: 20, color: CceColors.textSecondary),
              title: const Text('Ejecutar ahora', style: CceText.body),
              onTap: () => Navigator.of(sheetContext).pop('run'),
            ),
            ListTile(
              leading: const CceIcon(CceIcons.pencil,
                  size: 20, color: CceColors.textSecondary),
              title: const Text('Editar', style: CceText.body),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: const CceIcon(CceIcons.plus,
                  size: 20, color: CceColors.textSecondary),
              title: const Text('Duplicar', style: CceText.body),
              onTap: () => Navigator.of(sheetContext).pop('duplicate'),
            ),
            ListTile(
              leading: const CceIcon(CceIcons.trash,
                  size: 20, color: CceColors.danger),
              title: const Text('Eliminar',
                  style: TextStyle(color: CceColors.danger, fontSize: 15)),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'run':
        final warning = _service.clientReplayWarning(a);
        if (warning != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(warning)));
        }
        final result = await _service.runNow(a);
        if (!mounted) return;
        if (!result.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.warning ?? 'No se pudo ejecutar')),
          );
        }
      case 'edit':
        await _openEditor(a);
      case 'duplicate':
        await _duplicate(a);
      case 'delete':
        setState(() => _confirmingDeleteId = a.id);
    }
  }

  Future<void> _confirmDelete(Automation a) async {
    setState(() => _confirmingDeleteId = null);
    await _service.delete(a.id);
    if (!mounted) return;
    _showUndoDeleteSnackBar();
  }

  Future<void> _toggleEnabled(Automation a, bool enabled) async {
    final result = await _service.setEnabled(a.id, enabled);
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'No se pudo cambiar')),
      );
    }
  }

  /// Reordenar (CCE#79): la lista plana en el orden del servidor, con un asa
  /// por fila. Secundario, al lado de «Nueva».
  Widget _orderPill() {
    return Tooltip(
      message: 'Reordenar',
      child: InkWell(
        onTap: _openOrderPage,
        borderRadius: BorderRadius.circular(CceRadii.pill),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(CceRadii.pill),
          ),
          child: const Icon(Icons.swap_vert_rounded,
              size: 22, color: CceColors.textPrimary),
        ),
      ),
    );
  }

  Future<void> _openOrderPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AutomationsOrderPage(service: _service),
      ),
    );
  }

  Widget _newPill() {
    return InkWell(
      onTap: () => _openEditor(null),
      borderRadius: BorderRadius.circular(CceRadii.pill),
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: CceSpace.lg),
        decoration: BoxDecoration(
          // Acción principal de la pantalla: fill de acento, sin borde.
          // El acento al 24% sobre el lienzo daba un marrón apagado con
          // contorno — no se leía ni como botón primario ni como secundario.
          color: CceColors.accent,
          borderRadius: BorderRadius.circular(CceRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CceIcon(CceIcons.plus, size: 16, color: CceTint.inkOnPastel),
            SizedBox(width: CceSpace.sm),
            Text(
              'Nueva',
              style: CceText.label.copyWith(
                color: CceTint.inkOnPastel,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallo de carga: espejo del empty state pero con Reintentar (antes un
  /// error de red se veia como "Sin automatizaciones" y sin pull-to-refresh).
  Widget _errorState(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.danger.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.cloud_off_rounded,
                size: 58, color: CceColors.danger),
          ),
          const SizedBox(height: 20),
          const Text('No pudimos cargar tus automatizaciones',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: CceColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: Text(error,
                textAlign: TextAlign.center, style: CceText.caption),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _service.refresh(),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.accent.withValues(alpha: 0.12),
            ),
            child: const CceIcon(CceIcons.automations,
                size: 64, color: CceColors.accent),
          ),
          const SizedBox(height: 20),
          const Text('Sin automatizaciones',
              style: TextStyle(
                  color: CceColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const SizedBox(
            width: 360,
            child: Text(
              'Creá la primera: un botón, un horario o un sensor pueden '
              'disparar acciones',
              textAlign: TextAlign.center,
              style: CceText.caption,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openEditor(null),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            icon: const CceIcon(CceIcons.plus, size: 16, color: Colors.white),
            label: const Text('Nueva automatización'),
          ),
        ],
      ),
    );
  }

  SliverGrid _grid(List<Automation> items) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: AutomationCard.kHeight,
        // = CceSpace.md (literal: el delegate es const).
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final a = items[i];
          return AutomationCard(
            automation: a,
            service: _service,
            devices: widget.devices,
            lastExecuted: _service.lastExecuted(a.id),
            confirmingDelete: _confirmingDeleteId == a.id,
            onTap: () => _openEditor(a),
            onLongPress: () => _showCardMenu(a),
            onToggleEnabled: (v) => _toggleEnabled(a, v),
            onConfirmDelete: () => _confirmDelete(a),
            onCancelDelete: () =>
                setState(() => _confirmingDeleteId = null),
          );
        },
        childCount: items.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        // Dentro de cada sección, el ORDEN DEL SERVIDOR (CCE#79): el que el
        // dueño armó arrastrando, el mismo que muestra el Dashboard. Antes se
        // ordenaba por nombre, y por eso los nombres llevaban número
        // («1 - Relax», «33. Volumen 10»): era la única forma de mandar en el
        // teléfono. Sigue sin ser lastExecuted, que reordenaba las cards en
        // vivo bajo el dedo.
        final all = _service.automations;
        final enabled = all.where((a) => a.enabled).toList();
        final disabled = all.where((a) => !a.enabled).toList();
        final bySensor =
            enabled.where((a) => a.trigger.type == 'sensor').toList();
        final bySchedule =
            enabled.where((a) => a.trigger.type == 'schedule').toList();
        final byManual = enabled
            .where((a) =>
                a.trigger.type != 'sensor' && a.trigger.type != 'schedule')
            .toList();

        Widget body;
        if (all.isEmpty && _service.loading) {
          body = const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: CceColors.textTertiary),
            ),
          );
        } else if (all.isEmpty && _service.error != null) {
          // Fallo de red: NO mostrar "Sin automatizaciones" (invitaba a crear
          // duplicados de las que no se pudieron cargar).
          body = _errorState(_service.error!);
        } else if (all.isEmpty) {
          body = _emptyState();
        } else {
          body = RefreshIndicator(
            onRefresh: _service.refresh,
            color: CceColors.textPrimary,
            backgroundColor: CceColors.surfaceHigh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (bySensor.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(title: 'Por sensor')),
                  _grid(bySensor),
                ],
                if (bySchedule.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(title: 'Programadas')),
                  _grid(bySchedule),
                ],
                if (byManual.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(title: 'Manuales')),
                  _grid(byManual),
                ],
                if (disabled.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                      child: SectionHeader(title: 'Desactivadas')),
                  _grid(disabled),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: CceColors.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        // `title` (20), no `display` (32): "Automatizaciones"
                        // es la palabra más larga de la navegación y a 32 no
                        // entra junto al botón — se partía en dos líneas,
                        // cortada como "Automatizacion / es".
                        child: Text(
                          'Automatizaciones',
                          style: CceText.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: CceSpace.md),
                      if (all.length > 1) ...[
                        _orderPill(),
                        SizedBox(width: CceSpace.sm),
                      ],
                      _newPill(),
                    ],
                  ),
                  if (_service.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _service.error!,
                        style: const TextStyle(
                            color: CceColors.danger, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
