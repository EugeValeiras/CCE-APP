import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
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
    // Si el usuario cierra el sheet del disparador (swipe-down / Cancelar) NO
    // se encadena el de acciones: aterriza en el editor vacio y decide.
    final okTrigger =
        await showTriggerSheet(context, draft: draft, devices: widget.devices);
    if (!mounted) return;
    setState(() {});
    if (!okTrigger) return;
    await showActionsSheet(context,
        draft: draft, devices: widget.devices, config: widget.service.config);
    if (!mounted) return;
    setState(() {
      // Sugerir nombre SOLO si lo configurado es valido: antes, cancelando
      // ambos sheets, quedaba "Sensor sin configurar -> Sin acciones".
      if (_name.text.trim().isEmpty && draft.validationError() == null) {
        final t = triggerPhrase(draft, widget.devices);
        final acts = actionsPhrase(draft, widget.devices);
        _name.text = '$t → $acts';
        _name.selection =
            TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
    _nameFocus.requestFocus();
  }

  /// ¿El draft difiere de lo que se abrio? Para confirmar el descarte.
  bool get _dirty {
    const eq = DeepCollectionEquality();
    final current = Map<String, dynamic>.of(draft.toJson());
    current['name'] = _name.text.trim();
    final original = Map<String, dynamic>.of(draft.original);
    if (widget.isNew) {
      // Nueva: sucia si toco algo (nombre, trigger o acciones).
      return _name.text.trim().isNotEmpty ||
          draft.actions.isNotEmpty ||
          draft.trigger.type != 'manual';
    }
    original['name'] = (original['name'] as String?)?.trim() ?? '';
    return !eq.equals(current, original);
  }

  /// Confirma el descarte de cambios (swipe-back o Cancelar).
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: CceColors.surface,
        title: const Text('¿Descartar los cambios?', style: CceText.title),
        content: const Text('Lo que configuraste se va a perder.',
            style: CceText.caption),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CceColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  /// Íconos ofrecidos: los FAVORITOS que el usuario curó en el Dashboard
  /// (config.favoriteIcons). Se completan con los emoji clásicos al final para
  /// que nunca quede vacío, y el ícono actual del draft siempre está presente
  /// aunque ya no figure entre los favoritos.
  List<String> get _iconOptions {
    final favs = widget.devices.favoriteIcons;
    final current = draft.icon.trim();
    return <String>[
      if (current.isNotEmpty) current,
      ...favs.where((f) => f != current),
      ..._emojiOptions.where((e) => e != current && !favs.contains(e)),
    ];
  }

  Future<void> _pickIcon() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CceColors.neoBase,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (sheetContext) {
        // Celda neumórfica: elegido = HUNDIDO con acento; libre = elevado.
        Widget cell(String value) {
          final selected = draft.icon == value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(sheetContext).pop(value),
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CceColors.neoBase,
                borderRadius: BorderRadius.circular(CceRadii.control),
                boxShadow: selected
                    ? CceShadows.neoInset(blur: 6, offset: 2)
                    : CceShadows.neo(blur: 8, offset: 3),
              ),
              child: automationIcon(
                value,
                size: 26,
                color: selected ? CceColors.accent : CceColors.neoText,
                customIcons: widget.devices.customIcons,
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Center(child: Text('Ícono', style: CceText.title)),
              const SizedBox(height: 6),
              Center(
                child: Text('Tus favoritos del panel',
                    style: CceText.caption),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final v in _iconOptions) cell(v)],
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
        content: const Text('Vas a poder deshacerlo unos segundos.',
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
    // 'deleted' → la lista muestra el SnackBar con DESHACER (antes el dialogo
    // prometia un undo que nunca aparecia al borrar desde el editor).
    if (mounted) Navigator.of(context).pop('deleted');
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
        radius: CceRadii.hueCard,
        padding: const EdgeInsets.all(18),
        onTap: onTap,
        color: CceColors.neoBase,
        neo: true,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CceColors.neoBase,
                gradient: CceGradients.convex(CceColors.neoBase),
                boxShadow: [
                  ...CceShadows.neo(blur: 8, offset: 3),
                  BoxShadow(
                      color: color.withValues(alpha: 0.35), blurRadius: 10),
                ],
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
          child: CircularProgressIndicator(
              strokeWidth: 2, color: CceColors.accent),
        );
      case _SaveState.done:
        // Check blanco sobre FilledButton accent: el relieve sobra -> flat.
        child = const CceIcon(CceIcons.check,
            size: 20, color: CceColors.ok, emboss: false);
      case _SaveState.idle:
        child = const Text('Guardar');
    }
    final enabled =
        validationError == null && _saveState == _SaveState.idle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _save : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          // Habilitado = tecla elevada con halo del acento; deshabilitado =
          // plano sin relieve (canon: disabled no sobresale).
          boxShadow: enabled
              ? [
                  ...CceShadows.neo(blur: 8, offset: 3),
                  BoxShadow(
                      color: CceColors.accent.withValues(alpha: 0.35),
                      blurRadius: 12),
                ]
              : const [],
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: enabled ? CceColors.accent : CceColors.neoTextSub,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validationError = draft.validationError();
    final condPhrase = conditionsPhrase(draft, widget.devices);

    return PopScope(
      // Sin esto, el swipe-back de iOS descartaba trigger+condiciones+acciones
      // sin preguntar (el AppBar no tiene flecha, pero el gesto sigue activo).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (context.mounted) Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
                    // Botón de ícono: tecla neumórfica (antes: cuadrado plano
                    // con borde, ajeno al material de la app).
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _pickIcon,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CceColors.neoBase,
                          borderRadius:
                              BorderRadius.circular(CceRadii.control),
                          boxShadow: CceShadows.neo(blur: 8, offset: 3),
                        ),
                        child: automationIcon(
                          draft.icon,
                          size: 28,
                          color: CceColors.neoText,
                          customIcons: widget.devices.customIcons,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Nombre: WELL hundido (el campo plano no pertenecía al
                    // sistema; acá el texto "se escribe dentro" del material).
                    Expanded(
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CceColors.neoBase,
                          borderRadius:
                              BorderRadius.circular(CceRadii.control),
                          boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
                        ),
                        child: TextField(
                          controller: _name,
                          focusNode: _nameFocus,
                          // SIN embossShadows: el relieve de goma es para
                          // TÍTULOS grabados, no para texto que se escribe —
                          // sobre el input se veía como un blur sucio.
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: CceColors.textPrimary,
                          ),
                          cursorColor: CceColors.accent,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Nombre',
                            hintStyle:
                                CceText.caption.copyWith(fontSize: 15),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // CceSwitch de la casa (antes: Switch.adaptive verde de iOS).
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CceSwitch(
                          value: draft.enabled,
                          accent: CceColors.ok,
                          onChanged: (v) => setState(() => draft.enabled = v),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          draft.enabled ? 'Activa' : 'Pausada',
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
                    color: CceColors.neoBase,
                    borderRadius: BorderRadius.circular(CceRadii.control),
                    boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
                  ),
                  child: Text(
                    editorSummary(draft, widget.devices),
                    style: CceText.body
                        .copyWith(color: CceColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          // Footer fijo.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: CceColors.neoBase,
              boxShadow: [
                BoxShadow(
                    color: Color(0x59000000), blurRadius: 18, offset: Offset(0, -6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Motivo por el que Guardar esta deshabilitado, JUNTO al boton:
              // el mismo texto vive en el banner de arriba, fuera de pantalla
              // cuando el usuario mira el footer.
              if (validationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 15, color: CceColors.warm),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          validationError,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: CceColors.warm,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 64,
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
                // Compacto (▶ redondo): el botón ancho "Probar" se solapaba
                // con "Cancelar" en teléfonos angostos.
                RunAutomationButton(
                  automation: draft,
                  service: widget.service,
                  compact: true,
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () async {
                    if (await _confirmDiscard() && context.mounted) {
                      Navigator.of(context).pop(false);
                    }
                  },
                  child: const Text('Cancelar',
                      style: TextStyle(color: CceColors.textSecondary)),
                ),
                const SizedBox(width: 6),
                _saveButton(validationError),
              ],
                ),
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
