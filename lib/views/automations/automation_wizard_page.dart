import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../models/automation_flow.dart';
import '../../services/automations_service.dart';
import '../../services/devices_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
import 'automation_card.dart' show automationIcon, triggerColor, triggerIcon;
import 'automation_phrases.dart';
import 'run_automation.dart';
import 'sheets/actions_sheet.dart';
import 'sheets/conditions_sheet.dart';
import 'sheets/trigger_sheet.dart';

/// El wizard de automatizaciones del teléfono (EugeValeiras/CCE#66): cinco
/// pantallas lineales —¿Cuándo? → ¿Solo si…? → ¿Qué hace? → ¿Y después? →
/// Nombre y listo— que reusan los tres sheets del editor viejo y producen un
/// FLUJO (`when` + `flow`, ver `automation_flow.dart`), nunca `actions`.
///
/// Una automatización nueva recorre las cinco en orden; una existente abre en
/// la última (el resumen), desde donde se salta a cualquier paso y «Listo»
/// vuelve. Un flujo que no entra en el molde —ramas anidadas, «si no» con
/// contenido, `waitFor`, más de una espera— se abre en [_ReadOnlyView]:
/// narrado, con el aviso «Este flujo se edita desde el Dashboard» y SIN botón
/// Guardar. La app nunca pisa lo que se armó en el diagrama.
///
/// Trabaja sobre [draft] (copia descartable); el guardado pasa por
/// [AutomationsService.save] con su anti-clobber y manejo de conflicto.
class AutomationWizardPage extends StatefulWidget {
  const AutomationWizardPage({
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
  State<AutomationWizardPage> createState() => _AutomationWizardPageState();
}

/// Las cinco pantallas, en orden.
enum WizardStep { when, onlyIf, does, after, name }

extension on WizardStep {
  String get label => switch (this) {
        WizardStep.when => 'Cuándo',
        WizardStep.onlyIf => 'Solo si',
        WizardStep.does => 'Qué hace',
        WizardStep.after => 'Después',
        WizardStep.name => 'Nombre',
      };

  bool get optional => this == WizardStep.onlyIf || this == WizardStep.after;
}

enum _SaveState { idle, saving, done }

/// Ancho máximo del contenido: en la tablet el wizard se lee como una columna,
/// no como un formulario estirado a todo el panel.
const double _kMaxContentWidth = 600;

/// Esperas ofrecidas de un toque en «¿Y después?».
const _kWaitPresets = [60, 120, 300, 600, 900, 1800, 3600];

/// Íconos ofrecidos cuando no hay favoritos del Dashboard.
const _kEmojiOptions = [
  '⚡', '💡', '🌙', '🌅', '🚪', '🔔', '🎵', '🏠',
  '🕖', '👋', '🎬', '🛋️', '🛏️', '📺', '🔒', '🍿',
];

class _AutomationWizardPageState extends State<AutomationWizardPage> {
  Automation get draft => widget.draft;
  DevicesService get devices => widget.devices;

  late final WizardDraft _wizard = WizardDraft(draft);
  late WizardStep _step = widget.isNew ? WizardStep.when : WizardStep.name;

  /// Hasta dónde llegó una automatización nueva: los pasos ya vistos son
  /// tocables en la barra; los que siguen, todavía no.
  late WizardStep _reached = _step;

  /// true = se entró al paso desde el resumen: «Listo» vuelve al resumen en
  /// vez de seguir al paso siguiente.
  bool _fromSummary = false;

  /// Pasos cuyo sheet ya se abrió solo al llegar (una vez por paso).
  final Set<WizardStep> _autoOpened = {};

  late final TextEditingController _name =
      TextEditingController(text: draft.name);
  final FocusNode _nameFocus = FocusNode();
  _SaveState _saveState = _SaveState.idle;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      draft.name = _name.text;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnterStep());
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Navegación entre pasos ──────────────────────────────────────────────

  bool get _triggerSet =>
      draft.trigger.type != 'sensor' || draft.trigger.sensorTriggers.isNotEmpty;

  /// Por qué no se puede avanzar desde el paso actual (null = se puede).
  String? get _stepBlocker {
    switch (_step) {
      case WizardStep.when:
        if (!_triggerSet) return 'Elegí qué dispara la automatización';
        if (draft.trigger.type == 'schedule') {
          final err = draft.validationError();
          if (err != null && err.contains('CUÁNDO')) return err;
          if (err != null && err.contains('intervalo')) return err;
        }
        return null;
      case WizardStep.does:
        return draft.actions.isEmpty ? 'Agregá al menos una acción' : null;
      case WizardStep.after:
        return _wizard.waitSeconds != null && _wizard.afterActions.isEmpty
            ? 'Elegí qué hacer después de la espera'
            : null;
      case WizardStep.onlyIf:
        return null;
      case WizardStep.name:
        return _wizard.validationError();
    }
  }

  void _goTo(WizardStep step, {bool fromSummary = false}) {
    setState(() {
      _step = step;
      _fromSummary = fromSummary;
      if (step.index > _reached.index) _reached = step;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnterStep());
  }

  void _next() {
    if (_fromSummary || _step == WizardStep.name) {
      _goTo(WizardStep.name);
      return;
    }
    _goTo(WizardStep.values[_step.index + 1]);
  }

  void _back() {
    if (_fromSummary) {
      _goTo(WizardStep.name);
      return;
    }
    if (_step.index > 0) _goTo(WizardStep.values[_step.index - 1]);
  }

  /// Al llegar a un paso obligatorio todavía vacío (automatización nueva) el
  /// sheet se abre solo: es el flujo encadenado que ya tenía el editor viejo,
  /// un toque menos por pantalla.
  Future<void> _onEnterStep() async {
    if (!mounted || !widget.isNew) return;
    // La sugerencia de nombre no se gasta: mientras el nombre siga vacío se
    // vuelve a ofrecer cada vez que se llega al último paso.
    if (_step == WizardStep.name) {
      _suggestName();
      return;
    }
    if (_autoOpened.contains(_step)) return;
    _autoOpened.add(_step);
    switch (_step) {
      case WizardStep.when:
        if (!_triggerSet) await _editTrigger();
      case WizardStep.does:
        if (draft.actions.isEmpty) await _editActions();
      default:
        break;
    }
  }

  void _suggestName() {
    if (_name.text.trim().isNotEmpty ||
        _wizard.validationError(ignoreName: true) != null) {
      return;
    }
    // Nombre sugerido SOLO si lo configurado es válido: antes, cancelando los
    // sheets, quedaba "Sensor sin configurar → Sin acciones".
    _name.text = '${triggerPhrase(draft, devices)} → '
        '${_actionsLine(draft.actions)}';
    _name.selection =
        TextSelection(baseOffset: 0, extentOffset: _name.text.length);
    _nameFocus.requestFocus();
  }

  // ── Los sheets existentes ───────────────────────────────────────────────

  Future<void> _editTrigger() async {
    await showTriggerSheet(context, draft: draft, devices: devices);
    if (mounted) setState(() {});
  }

  Future<void> _editConditions() async {
    await showConditionsSheet(context, draft: draft, devices: devices);
    if (mounted) setState(() {});
  }

  Future<void> _editActions() async {
    await showActionsSheet(context,
        draft: draft, devices: devices, config: widget.service.config);
    if (mounted) setState(() {});
  }

  /// El mismo sheet ENTONCES sobre el cascarón de «¿y después?»: sólo toca
  /// `draft.actions`, así que la segunda lista se edita sin duplicar nada.
  Future<void> _editAfterActions() async {
    await showActionsSheet(context,
        draft: _wizard.afterShell,
        devices: devices,
        config: widget.service.config,
        title: 'Y después');
    if (mounted) setState(() {});
  }

  // ── Guardar / descartar / eliminar (portados del editor por bloques) ────

  Future<bool> _confirmDiscard() async {
    if (!_wizard.dirty) return true;
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

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_saveState != _SaveState.idle) return;
    setState(() => _saveState = _SaveState.saving);
    // Acá es donde las cuatro pantallas pasan a ser `when` + `flow`.
    _wizard.commit();
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
              const Text('Se modificó desde otro lugar', style: CceText.title),
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
    // 'deleted' → la lista muestra el SnackBar con DESHACER.
    if (mounted) Navigator.of(context).pop('deleted');
  }

  // ── Ícono ───────────────────────────────────────────────────────────────

  List<String> get _iconOptions {
    final favs = devices.favoriteIcons;
    final current = draft.icon.trim();
    return <String>[
      if (current.isNotEmpty) current,
      ...favs.where((f) => f != current),
      ..._kEmojiOptions.where((e) => e != current && !favs.contains(e)),
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
                customIcons: devices.customIcons,
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              const Center(child: Text('Ícono', style: CceText.title)),
              const SizedBox(height: 6),
              const Center(
                child:
                    Text('Tus favoritos del panel', style: CceText.caption),
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

  // ── Frases de las filas ─────────────────────────────────────────────────

  /// "Prender Living al 40% · Apagar la tele", >3 → "… +N más".
  String _actionsLine(List<AutomationAction> acts) {
    if (acts.isEmpty) return 'Sin acciones';
    final phrases = [for (final a in acts) actionPhrase(a, devices)];
    if (phrases.length > 3) {
      return '${phrases.take(3).join(' · ')} +${phrases.length - 3} más';
    }
    return phrases.join(' · ');
  }

  String get _conditionsLine {
    final parts = disambiguatedConditions(
        draft.trigger.conditions, devices, (c) => conditionPhrase(c, devices));
    switch (draft.trigger.alarmCondition) {
      case 'armed':
        parts.add('con alarma armada');
      case 'disarmed':
        parts.add('con alarma desarmada');
    }
    return parts.isEmpty ? 'Siempre' : parts.join(' · ');
  }

  String get _afterLine {
    final wait = _wizard.waitSeconds;
    if (wait == null) return 'Nada más';
    final acts = _wizard.afterActions;
    return '${_cap(waitPhrase(wait))} · '
        '${acts.isEmpty ? 'elegí qué hacer' : _actionsLine(acts)}';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String get _summary => wizardSummary(
        draft,
        devices,
        conditions: draft.trigger.conditions,
        actions: draft.actions,
        waitSeconds: _wizard.waitSeconds,
        afterActions: _wizard.afterActions,
      );

  // ── Cuerpos de cada paso ────────────────────────────────────────────────

  List<Widget> _whenBody() => [
        const _StepTitle('¿Cuándo?', 'Lo que dispara la automatización.'),
        _StepCard(
          label: 'Disparador',
          color: triggerColor(draft),
          icon: triggerIcon(draft),
          rows: [
            _triggerSet
                ? triggerPhrase(draft, devices)
                : 'Elegí un sensor, un horario o manual',
          ],
          onTap: _editTrigger,
          actionLabel: _triggerSet ? 'Cambiar' : 'Elegir',
        ),
      ];

  List<Widget> _onlyIfBody() {
    final conds = draft.trigger.conditions;
    final alarm = draft.trigger.alarmCondition;
    return [
      const _StepTitle('¿Solo si…?',
          'Opcional. La automatización corre sólo cuando se cumple.'),
      _StepCard(
        label: 'Condición',
        color: CceColors.triggerManual,
        icon: const CceIcon(CceIcons.moon),
        rows: [
          if (conds.isEmpty && alarm == 'any') 'Siempre',
          for (final p in disambiguatedConditions(
              conds, devices, (c) => conditionPhrase(c, devices)))
            _cap(p),
          if (alarm == 'armed') 'Con la alarma armada',
          if (alarm == 'disarmed') 'Con la alarma desarmada',
        ],
        onTap: _editConditions,
        actionLabel: conds.isEmpty && alarm == 'any' ? 'Agregar' : 'Cambiar',
      ),
    ];
  }

  List<Widget> _doesBody() => [
        const _StepTitle('¿Qué hace?', 'Las acciones corren juntas.'),
        _StepCard(
          label: 'Acciones',
          color: CceColors.triggerSchedule,
          icon: const CceIcon(CceIcons.lights),
          rows: [
            if (draft.actions.isEmpty) 'Elegí luces, escenas, avisos…',
            for (final a in draft.actions) actionPhrase(a, devices),
          ],
          rowIcons: [for (final a in draft.actions) _kindIcon(a.kind)],
          onTap: _editActions,
          actionLabel: draft.actions.isEmpty ? 'Elegir' : 'Editar',
        ),
      ];

  List<Widget> _afterBody() {
    final enabled = _wizard.waitSeconds != null;
    return [
      const _StepTitle('¿Y después?',
          'Opcional. Esperar un rato y hacer otra cosa: «prendé, esperá 5 '
          'minutos, apagá».'),
      // Un switch y no un segmentado: la etiqueta larga no entra en dos
      // segmentos de medio ancho en un teléfono angosto.
      CceCard(
        radius: CceRadii.hueCard,
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        color: CceColors.neoBase,
        neo: true,
        child: Row(
          children: [
            const Expanded(
              child: Text('Esperar un rato y hacer otra cosa',
                  style: CceText.body),
            ),
            const SizedBox(width: 12),
            CceSwitch(
              value: enabled,
              accent: CceColors.accent,
              onChanged: (v) => setState(() {
                _wizard.waitSeconds = v ? (_wizard.waitSeconds ?? 300) : null;
              }),
            ),
          ],
        ),
      ),
      if (enabled) ...[
        const SizedBox(height: 20),
        Text('ESPERAR', style: CceText.section),
        const SizedBox(height: 10),
        _WaitPicker(
          seconds: _wizard.waitSeconds!,
          onChanged: (s) => setState(() => _wizard.waitSeconds = s),
        ),
        const SizedBox(height: 20),
        _StepCard(
          label: 'Y después hacer',
          color: CceColors.triggerSchedule,
          icon: const CceIcon(CceIcons.lights),
          rows: [
            if (_wizard.afterActions.isEmpty) 'Elegí qué hacer después',
            for (final a in _wizard.afterActions) actionPhrase(a, devices),
          ],
          rowIcons: [
            for (final a in _wizard.afterActions) _kindIcon(a.kind),
          ],
          onTap: _editAfterActions,
          actionLabel: _wizard.afterActions.isEmpty ? 'Elegir' : 'Editar',
        ),
      ],
    ];
  }

  List<Widget> _nameBody() => [
        const _StepTitle('Nombre y listo', 'Así se va a ver en la lista.'),
        // Header: ícono 56 + nombre + habilitada (mismo que el editor viejo).
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickIcon,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CceColors.neoBase,
                  borderRadius: BorderRadius.circular(CceRadii.control),
                  boxShadow: CceShadows.neo(blur: 8, offset: 3),
                ),
                child: automationIcon(
                  draft.icon,
                  size: 28,
                  color: CceColors.neoText,
                  customIcons: devices.customIcons,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CceColors.neoBase,
                  borderRadius: BorderRadius.circular(CceRadii.control),
                  boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
                ),
                child: TextField(
                  controller: _name,
                  focusNode: _nameFocus,
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
                    hintStyle: CceText.caption.copyWith(fontSize: 15),
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CceSwitch(
                  value: draft.enabled,
                  accent: CceColors.accent,
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
        // La frase humana viva.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(CceRadii.control),
            boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
          ),
          child: Text(
            _summary,
            style: CceText.body
                .copyWith(color: CceColors.textSecondary, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        // Los cuatro pasos como filas: tocar una vuelve a esa pantalla.
        _SummaryRow(
          label: 'Cuándo',
          color: triggerColor(draft),
          icon: triggerIcon(draft),
          phrase: triggerPhrase(draft, devices),
          onTap: () => _goTo(WizardStep.when, fromSummary: true),
        ),
        _SummaryRow(
          label: 'Solo si',
          color: CceColors.triggerManual,
          icon: const CceIcon(CceIcons.moon),
          phrase: _conditionsLine,
          onTap: () => _goTo(WizardStep.onlyIf, fromSummary: true),
        ),
        _SummaryRow(
          label: 'Qué hace',
          color: CceColors.triggerSchedule,
          icon: const CceIcon(CceIcons.lights),
          phrase: _actionsLine(draft.actions),
          onTap: () => _goTo(WizardStep.does, fromSummary: true),
        ),
        _SummaryRow(
          label: 'Y después',
          color: CceColors.info,
          icon: const Icon(Icons.timer_outlined),
          phrase: _afterLine,
          onTap: () => _goTo(WizardStep.after, fromSummary: true),
        ),
      ];

  List<Widget> _stepBody() => switch (_step) {
        WizardStep.when => _whenBody(),
        WizardStep.onlyIf => _onlyIfBody(),
        WizardStep.does => _doesBody(),
        WizardStep.after => _afterBody(),
        WizardStep.name => _nameBody(),
      };

  // ── Footer ──────────────────────────────────────────────────────────────

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    Widget child;
    switch (_saveState) {
      case _SaveState.saving:
        child = const SizedBox(
          width: 18,
          height: 18,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: CceColors.accent),
        );
      case _SaveState.done:
        child = const CceIcon(CceIcons.check,
            size: 20, color: CceColors.ok, emboss: false);
      case _SaveState.idle:
        child = Text(label);
    }
    final active = enabled && _saveState == _SaveState.idle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? onTap : null,
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
          boxShadow: active
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
            color: active ? CceColors.accent : CceColors.neoTextSub,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _footer() {
    final blocker = _stepBlocker;
    final isLast = _step == WizardStep.name;
    final String primaryLabel;
    if (isLast) {
      primaryLabel = 'Guardar';
    } else if (_fromSummary) {
      primaryLabel = 'Listo';
    } else {
      primaryLabel = 'Siguiente';
    }
    final showSkip = !isLast &&
        !_fromSummary &&
        _step.optional &&
        (_step == WizardStep.onlyIf
            ? draft.trigger.conditions.isEmpty &&
                draft.trigger.alarmCondition == 'any'
            : _wizard.waitSeconds == null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: CceColors.neoBase,
        boxShadow: [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 18, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Motivo por el que no se puede avanzar, JUNTO al botón.
            if (blocker != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: CceColors.warm),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        blocker,
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
                  if (isLast && !widget.isNew)
                    TextButton.icon(
                      onPressed: _delete,
                      icon: const CceIcon(CceIcons.trash,
                          size: 16, color: CceColors.danger),
                      label: const Text('Eliminar',
                          style: TextStyle(color: CceColors.danger)),
                    )
                  else if (_step.index > 0 || _fromSummary)
                    TextButton.icon(
                      onPressed: _back,
                      icon: const Icon(Icons.chevron_left,
                          size: 18, color: CceColors.textSecondary),
                      label: Text(_fromSummary ? 'Resumen' : 'Atrás',
                          style:
                              const TextStyle(color: CceColors.textSecondary)),
                    ),
                  const Spacer(),
                  // Probar SOLO en una existente: en una nueva el id todavía
                  // no existe en el server y el 404 marcaría el endpoint de
                  // ejecución como ausente por el resto de la sesión.
                  if (isLast && !widget.isNew) ...[
                    RunAutomationButton(
                        automation: draft,
                        service: widget.service,
                        compact: true),
                    const SizedBox(width: 6),
                  ],
                  if (showSkip) ...[
                    TextButton(
                      onPressed: _next,
                      child: const Text('Saltear',
                          style: TextStyle(color: CceColors.textSecondary)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _primaryButton(
                    label: primaryLabel,
                    // Guardar sólo si hay algo que guardar: una existente
                    // abierta sin tocar no tiene por qué volver a la red.
                    enabled: blocker == null &&
                        (!isLast || widget.isNew || _wizard.dirty),
                    onTap: isLast ? _save : _next,
                  ),
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
    if (_wizard.readOnly) {
      return _ReadOnlyView(
        automation: draft,
        service: widget.service,
        devices: devices,
        reason: _wizard.unsupportedReason,
      );
    }
    return PopScope(
      // Sin esto, el swipe-back de iOS descartaba todo sin preguntar.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_step != WizardStep.when && (widget.isNew || _fromSummary)) {
          _back();
          return;
        }
        await _close();
      },
      child: Scaffold(
        backgroundColor: CceColors.bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Cerrar',
            icon: const CceIcon(CceIcons.close,
                size: 18, color: CceColors.textSecondary),
            onPressed: _close,
          ),
          title: Text(widget.isNew ? 'Nueva automatización' : 'Editar'),
        ),
        body: Column(
          children: [
            // La barra va al mismo ancho que el contenido: en la tablet, una
            // barra de borde a borde sobre una columna centrada se lee suelta.
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: _StepBar(
                  current: _step,
                  reachable: widget.isNew ? _reached : WizardStep.name,
                  onTap: (s) => _goTo(s, fromSummary: !widget.isNew),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _kMaxContentWidth),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: ListView(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: _stepBody(),
                    ),
                  ),
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }
}

// ── Piezas del wizard ─────────────────────────────────────────────────────────

Widget _kindIcon(AutomationActionKind kind) {
  switch (kind) {
    case AutomationActionKind.light:
      return const CceIcon(CceIcons.lights, size: 16);
    case AutomationActionKind.group:
    case AutomationActionKind.hueRoom:
      return const CceIcon(CceIcons.room, size: 16);
    case AutomationActionKind.scene:
    case AutomationActionKind.hueScene:
      return const CceIcon(CceIcons.scenes, size: 16);
    case AutomationActionKind.device:
      return const Icon(Icons.tune, size: 16);
    case AutomationActionKind.notification:
      return const Icon(Icons.notifications_outlined, size: 16);
    case AutomationActionKind.alarm:
      return const CceIcon(CceIcons.alarmShield, size: 16);
    case AutomationActionKind.jbl:
      return const CceIcon(CceIcons.jbl, size: 16);
    case AutomationActionKind.advanced:
      return const CceIcon(CceIcons.automations, size: 16);
  }
}

/// La barra de progreso de arriba: cinco tramos con su etiqueta; el actual en
/// acento, los ya vistos tocables.
class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.current,
    required this.reachable,
    required this.onTap,
  });

  final WizardStep current;
  final WizardStep reachable;
  final ValueChanged<WizardStep> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        children: [
          for (final s in WizardStep.values) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: s.index <= reachable.index && s != current
                    ? () => onTap(s)
                    : null,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 5,
                      decoration: BoxDecoration(
                        color: s == current
                            ? CceColors.accent
                            : s.index <= reachable.index
                                ? CceColors.accent.withValues(alpha: 0.4)
                                : CceColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.section.copyWith(
                        letterSpacing: 0.4,
                        color: s == current
                            ? CceColors.textPrimary
                            : s.index <= reachable.index
                                ? CceColors.textSecondary
                                : CceColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (s != WizardStep.name) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.hint);

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CceText.display.copyWith(fontSize: 28)),
          const SizedBox(height: 6),
          Text(hint, style: CceText.caption.copyWith(height: 1.35)),
        ],
      ),
    );
  }
}

/// La card grande de un paso: ícono en círculo con el color del bloque, la(s)
/// frase(s) de lo configurado y el botón que abre el sheet.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.label,
    required this.color,
    required this.icon,
    required this.rows,
    this.rowIcons = const [],
    required this.onTap,
    required this.actionLabel,
  });

  final String label;
  final Color color;
  final Widget icon;
  final List<String> rows;
  final List<Widget> rowIcons;
  final VoidCallback onTap;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      radius: CceRadii.hueCard,
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      color: CceColors.neoBase,
      neo: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CceColors.neoBase,
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
                  child: Text(label.toUpperCase(), style: CceText.section)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: CceColors.accent,
                  borderRadius: BorderRadius.circular(CceRadii.pill),
                ),
                child: Text(
                  actionLabel,
                  style: CceText.label.copyWith(
                    color: CceTint.inkOnPastel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (i < rowIcons.length) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: IconTheme.merge(
                        data: const IconThemeData(
                            color: CceColors.textTertiary, size: 16),
                        child: rowIcons[i],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(rows[i], style: CceText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila del resumen: un paso, su frase y el chevron para volver a él.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.color,
    required this.icon,
    required this.phrase,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Widget icon;
  final String phrase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CceCard(
        radius: CceRadii.hueCard,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        color: CceColors.neoBase,
        neo: true,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 18),
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
            const CceIcon(CceIcons.chevronRight,
                size: 16, color: CceColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// La espera de «¿y después?»: atajos de un toque y un paso a paso de a un
/// minuto. Se guarda en segundos (contrato del `wait`).
class _WaitPicker extends StatelessWidget {
  const _WaitPicker({required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  Widget _chip(int value) {
    final selected = value == seconds;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? CceColors.accent : CceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          border: Border.all(
              color: selected ? CceColors.accent : CceColors.stroke),
        ),
        child: Text(
          durationLabel(value),
          style: CceText.label.copyWith(
            color: selected ? CceTint.inkOnPastel : CceColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          shape: BoxShape.circle,
          boxShadow: onTap == null ? const [] : CceShadows.neo(blur: 8, offset: 3),
        ),
        child: Icon(icon,
            size: 20,
            color: onTap == null ? CceColors.textMuted : CceColors.textPrimary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Paso de a un minuto; una espera heredada que no sea múltiplo de 60 se
    // muestra tal cual ("1 min 30 s") y el primer toque la redondea.
    final minutes = seconds ~/ 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final v in _kWaitPresets) _chip(v)],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _stepButton(
              Icons.remove,
              minutes > 1 ? () => onChanged((minutes - 1) * 60) : null,
            ),
            Expanded(
              child: Text(
                durationLabel(seconds),
                textAlign: TextAlign.center,
                style: CceText.dataLarge.copyWith(fontSize: 26),
              ),
            ),
            _stepButton(
              Icons.add,
              minutes < 24 * 60 ? () => onChanged((minutes + 1) * 60) : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Solo lectura ─────────────────────────────────────────────────────────────

/// Un flujo que no entra en el molde: se narra entero y no se toca. Sin botón
/// Guardar, sin sheets; sólo Probar y Cerrar.
class _ReadOnlyView extends StatelessWidget {
  const _ReadOnlyView({
    required this.automation,
    required this.service,
    required this.devices,
    required this.reason,
  });

  final Automation automation;
  final AutomationsService service;
  final DevicesService devices;
  final String? reason;

  Widget _lineIcon(FlowLine line) {
    const color = CceColors.textTertiary;
    switch (line.kind) {
      case FlowLineKind.condition:
        return const Icon(Icons.call_split, size: 16, color: color);
      case FlowLineKind.branch:
        return const Icon(Icons.subdirectory_arrow_right,
            size: 16, color: color);
      case FlowLineKind.action:
        return const Icon(Icons.play_arrow_rounded, size: 16, color: color);
      case FlowLineKind.wait:
        return const Icon(Icons.timer_outlined, size: 16, color: color);
      case FlowLineKind.stop:
        return const Icon(Icons.stop_circle_outlined, size: 16, color: color);
      case FlowLineKind.unknown:
        return const Icon(Icons.help_outline, size: 16, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = automation;
    final color = triggerColor(a);
    final lines = flowNarration(a.flow, devices);
    final cond = conditionsPhrase(a, devices);
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const CceIcon(CceIcons.close,
              size: 18, color: CceColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Solo lectura'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withValues(alpha: 0.18),
                          ),
                          child: automationIcon(a.icon,
                              size: 26,
                              color: color,
                              customIcons: devices.customIcons),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name.isEmpty ? 'Sin nombre' : a.name,
                                  style: CceText.headline),
                              const SizedBox(height: 2),
                              Text(a.enabled ? 'Activa' : 'Pausada',
                                  style: CceText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // El aviso: la app no pisa lo que se armó en el diagrama.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: CceColors.accentWash,
                        borderRadius: BorderRadius.circular(CceRadii.control),
                        border: Border.all(
                            color: CceColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.info_outline,
                                size: 18, color: CceColors.accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Este flujo se edita desde el Dashboard',
                                  style: TextStyle(
                                      color: CceColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                if (reason != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Acá se muestra completo pero no se '
                                    'cambia: $reason.',
                                    style: CceText.caption
                                        .copyWith(height: 1.35),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('CUÁNDO', style: CceText.section),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(color: color, size: 18),
                          child: triggerIcon(a, size: 18, color: color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            cond.isEmpty
                                ? triggerPhrase(a, devices)
                                : '${triggerPhrase(a, devices)} · $cond',
                            style: CceText.body,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('FLUJO', style: CceText.section),
                    const SizedBox(height: 10),
                    if (lines.isEmpty)
                      const Text('Sin pasos.', style: CceText.caption),
                    for (final line in lines)
                      Padding(
                        padding: EdgeInsets.only(
                            left: 18.0 * line.depth, bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _lineIcon(line),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                line.text,
                                style: line.kind == FlowLineKind.condition ||
                                        line.kind == FlowLineKind.branch
                                    ? CceText.body
                                        .copyWith(fontWeight: FontWeight.w600)
                                    : CceText.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: CceColors.neoBase,
              boxShadow: [
                BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 18,
                    offset: Offset(0, -6)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    RunAutomationButton(automation: a, service: service),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cerrar',
                          style: TextStyle(color: CceColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
