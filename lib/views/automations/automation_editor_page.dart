import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import 'automation_card.dart' show automationIcon;
import 'automation_phrases.dart';
import 'run_automation.dart';
import 'sheets/actions_sheet.dart';
import 'sheets/conditions_sheet.dart';
import 'sheets/trigger_sheet.dart';

/// Editor full-screen por bloques (no wizard): CUÁNDO / SOLO SI / ENTONCES,
/// banner con la frase humana viva y footer fijo
/// [Eliminar] … [Probar] [Cancelar] [Guardar].
///
/// Trabaja sobre [draft] (copia descartable); el guardado pasa por
/// [AutomationsService.save] con su anti-clobber y manejo de conflicto.
class AutomationEditorPage extends StatefulWidget {
  const AutomationEditorPage({
    super.key,
    required this.service,
    required this.devices,
    required this.draft,
    required this.isNew,
  });

  final AutomationsService service;
  final DevicesService devices;
  final Automation draft;
  final bool isNew;

  @override
  State<AutomationEditorPage> createState() => _AutomationEditorPageState();
}

enum _SaveState { idle, saving, done }

class _AutomationEditorPageState extends State<AutomationEditorPage> {
  Automation get draft => widget.draft;

  late final TextEditingController _name =
      TextEditingController(text: draft.name);
  final FocusNode _nameFocus = FocusNode();
  _SaveState _saveState = _SaveState.idle;

  static const _emojiOptions = [
    '⚡', '💡', '🌙', '🌅', '🚪', '🔔', '🎵', '🏠',
    '🕖', '👋', '🎬', '🛋️', '🛏️', '📺', '🔒', '🍿',
  ];
  static const _mdiOptions = [
    'mdi:lightning-bolt',
    'mdi:lightbulb',
    'mdi:weather-night',
    'mdi:door',
    'mdi:bell',
    'mdi:music',
    'mdi:home',
    'mdi:clock-outline',
    'mdi:gesture-tap',
    'mdi:motion-sensor',
    'mdi:sofa',
    'mdi:television',
  ];

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      draft.name = _name.text;
      setState(() {});
    });
    if (widget.isNew) {
      // Flujo de creación encadenado: CUÁNDO → ENTONCES → foco en nombre.
      WidgetsBinding.instance.addPostFrameCallback((_) => _createFlow());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _createFlow() async {
    if (!mounted) return;
    await showTriggerSheet(context, draft: draft, devices: widget.devices);
    if (!mounted) return;
    setState(() {});
    await showActionsSheet(context,
        draft: draft, devices: widget.devices, config: widget.service.config);
    if (!mounted) return;
    setState(() {
      if (_name.text.trim().isEmpty) {
        // Sugerencia de nombre a partir de lo configurado.
        final t = triggerPhrase(draft, widget.devices);
        final acts = actionsPhrase(draft, widget.devices);
        _name.text = '$t → $acts';
        _name.selection =
            TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
    _nameFocus.requestFocus();
  }

  Future<void> _pickIcon() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (sheetContext) {
        Widget cell(String value) {
          final selected = draft.icon == value;
          return InkWell(
            onTap: () => Navigator.of(sheetContext).pop(value),
            borderRadius: BorderRadius.circular(CceRadii.control),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? CceColors.accent.withValues(alpha: 0.24)
                    : CceColors.surfaceHigh,
                borderRadius: BorderRadius.circular(CceRadii.control),
                border: Border.all(
                  color: selected ? CceColors.accent : CceColors.stroke,
                ),
              ),
              child:
                  automationIcon(value, size: 24, color: CceColors.textPrimary),
            ),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Ícono', style: CceText.title),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in _emojiOptions) cell(e),
                  for (final m in _mdiOptions) cell(m),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (chosen != null) setState(() => draft.icon = chosen);
  }

  Future<void> _save() async {
    if (_saveState != _SaveState.idle) return;
    setState(() => _saveState = _SaveState.saving);
    final result = await widget.service.save(draft);
    if (!mounted) return;
    if (result.ok) {
      setState(() => _saveState = _SaveState.done);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saveState = _SaveState.idle);
    if (result.status == SaveStatus.conflict) {
      await _handleConflict(result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'No se pudo guardar')),
      );
    }
  }

  Future<void> _handleConflict(SaveResult result) async {
    final serverName =
        (result.serverCopy?['name'] ?? 'esta automatización').toString();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Se modificó desde otro lugar',
                  style: CceText.title),
              const SizedBox(height: 8),
              Text(
                '"$serverName" cambió en el servidor mientras la editabas. '
                '¿Querés pisar esos cambios con tu versión?',
                style: CceText.caption,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop('discard'),
                      child: const Text('Descartar lo mío'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop('overwrite'),
                      child: const Text('Sobrescribir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'overwrite') {
      setState(() => _saveState = _SaveState.saving);
      final forced = await widget.service.save(draft, force: true);
      if (!mounted) return;
      if (forced.ok) {
        setState(() => _saveState = _SaveState.done);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() => _saveState = _SaveState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(forced.message ?? 'No se pudo guardar')),
        );
      }
    } else if (choice == 'discard') {
      await widget.service.refresh();
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: CceColors.surface,
        title: Text('¿Eliminar "${draft.name}"?', style: CceText.title),
        content: const Text('Esta acción se puede deshacer desde la lista.',
            style: CceText.caption),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CceColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.service.delete(draft.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _blockCard({
    required String label,
    required Color color,
    required Widget icon,
    required String phrase,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CceCard(
        radius: CceRadii.card,
        padding: const EdgeInsets.all(18),
        onTap: onTap,
        border: true,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 20),
                child: icon,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: CceText.section),
                  const SizedBox(height: 4),
                  Text(
                    phrase,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CceText.body,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const CceIcon(CceIcons.chevronDown,
                size: 18, color: CceColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _saveButton(String? validationError) {
    Widget child;
    switch (_saveState) {
      case _SaveState.saving:
        child = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      case _SaveState.done:
        child = const CceIcon(CceIcons.check, size: 20, color: Colors.white);
      case _SaveState.idle:
        child = const Text('Guardar');
    }
    return FilledButton(
      onPressed:
          validationError == null && _saveState == _SaveState.idle ? _save : null,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final validationError = draft.validationError();
    final condPhrase = conditionsPhrase(draft, widget.devices);

    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nueva automatización' : 'Editar'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                // Header: ícono 56 + nombre + habilitada.
                Row(
                  children: [
                    InkWell(
                      onTap: _pickIcon,
                      borderRadius: BorderRadius.circular(CceRadii.control),
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CceColors.surfaceHigh,
                          borderRadius:
                              BorderRadius.circular(CceRadii.control),
                          border: Border.all(color: CceColors.stroke),
                        ),
                        child: automationIcon(draft.icon,
                            size: 28, color: CceColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        focusNode: _nameFocus,
                        style: CceText.title,
                        decoration: const InputDecoration(
                          hintText: 'Nombre de la automatización',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch.adaptive(
                          value: draft.enabled,
                          onChanged: (v) =>
                              setState(() => draft.enabled = v),
                        ),
                        Text(
                          draft.enabled ? 'Habilitada' : 'Deshabilitada',
                          style: const TextStyle(
                              color: CceColors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _blockCard(
                  label: 'Cuándo',
                  color: CceColors.triggerSensor,
                  icon: CceIcon(
                    draft.trigger.type == 'schedule'
                        ? CceIcons.clock
                        : draft.trigger.type == 'manual'
                            ? CceIcons.handTap
                            : CceIcons.sensors,
                  ),
                  phrase: triggerPhrase(draft, widget.devices),
                  onTap: () async {
                    await showTriggerSheet(context,
                        draft: draft, devices: widget.devices);
                    if (mounted) setState(() {});
                  },
                ),
                _blockCard(
                  label: 'Solo si',
                  color: CceColors.triggerManual,
                  icon: const CceIcon(CceIcons.moon),
                  phrase: condPhrase.isEmpty
                      ? 'Siempre (sin condiciones)'
                      : condPhrase,
                  onTap: () async {
                    await showConditionsSheet(context,
                        draft: draft, devices: widget.devices);
                    if (mounted) setState(() {});
                  },
                ),
                _blockCard(
                  label: 'Entonces',
                  color: CceColors.triggerSchedule,
                  icon: const CceIcon(CceIcons.lights),
                  phrase: actionsPhrase(draft, widget.devices),
                  onTap: () async {
                    await showActionsSheet(context,
                        draft: draft,
                        devices: widget.devices,
                        config: widget.service.config);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 6),
                // Banner con la frase humana viva.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CceColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(CceRadii.control),
                    border: Border.all(
                        color: CceColors.accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    editorSummary(draft, widget.devices),
                    style: CceText.body
                        .copyWith(color: CceColors.textSecondary, height: 1.4),
                  ),
                ),
                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      validationError,
                      style: const TextStyle(
                        color: CceColors.warm,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Footer fijo.
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: CceColors.surface,
              border: Border(top: BorderSide(color: CceColors.stroke)),
            ),
            child: Row(
              children: [
                if (!widget.isNew)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const CceIcon(CceIcons.trash,
                        size: 16, color: CceColors.danger),
                    label: const Text('Eliminar',
                        style: TextStyle(color: CceColors.danger)),
                  ),
                const Spacer(),
                Flexible(
                  child: RunAutomationButton(
                    automation: draft,
                    service: widget.service,
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar',
                      style: TextStyle(color: CceColors.textSecondary)),
                ),
                const SizedBox(width: 10),
                _saveButton(validationError),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
