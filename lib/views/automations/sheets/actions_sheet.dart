import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:http/http.dart' as http;

import '../../../models/automation.dart';
import '../../../models/scene.dart';
import '../../../models/capability.dart';
import '../../../models/device.dart';
import '../../../models/hue_room.dart';
import '../../../models/light_group.dart';
import '../../../utils/verb_labels.dart';
import '../../../models/server_config.dart';
import '../../../services/devices_service.dart';
import '../../../theme/cce_icons.dart';
import '../../../theme/cce_tokens.dart';
import '../../../theme/components/brightness_slider.dart';
import '../../../theme/components/cce_segmented.dart';
import '../../../theme/components/status_pill.dart';
import '../automation_phrases.dart';

/// Sheet ENTONCES: EL editor de acciones combinables (lista reordenable).
/// El modo Simple (una escena/grupo como source) se retiró el 2026-07-30:
/// la config está migrada a source:'custom' y las legacy se convierten al
/// abrir el editor. Muta el draft directo.
Future<bool> showActionsSheet(
  BuildContext context, {
  required Automation draft,
  required DevicesService devices,
  required ServerConfig config,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ActionsSheet(draft: draft, devices: devices, config: config),
  );
  return result == true;
}

/// Naranja de marca Hue (rooms y escenas del bridge).
const _hueOrange = Color(0xFFFF6A00);

/// Grosor del borde de marca Hue de los chips (mismo que HueRoomCard).
const double _hueBorderWidth = 1.4;

/// Chip de picker — COMPARTIDO entre los editores de acción Escena y Grupo
/// para que la marca visual sea una sola: swatch de colores, pill 'auto'
/// para smart scenes y borde con el gradiente de marca en lo que viene del
/// bridge Hue (escenas y rooms).
Widget _pickerChip({
  required String name,
  required bool selected,
  List<Color> swatch = const [],
  bool isSmart = false,
  bool hueBorder = false,
  required VoidCallback onTap,
}) {
  final tile = InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(CceRadii.control),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? CceColors.accent.withValues(alpha: 0.24)
            : CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.control),
        // Escena Hue: el borde lo pone el contenedor externo con el
        // gradiente de marca; acá no va Border para no sumar un anillo.
        border: hueBorder
            ? null
            : Border.all(
                color: selected
                    ? CceColors.accent.withValues(alpha: 0.6)
                    : CceColors.stroke,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch.isNotEmpty) ...[
            SizedBox(
              width: 16 + (swatch.length.clamp(1, 4) - 1) * 9.0,
              height: 16,
              child: Stack(
                children: [
                  for (var i = 0; i < swatch.length && i < 4; i++)
                    Positioned(
                      left: i * 9.0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: swatch[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: CceColors.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            name,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isSmart) ...[
            const SizedBox(width: 6),
            const StatusPill(label: 'auto', color: Color(0x52000000)),
          ],
          if (selected) ...[
            const SizedBox(width: 6),
            const CceIcon(CceIcons.check, size: 14, color: CceColors.accent),
          ],
        ],
      ),
    ),
  );
  if (!hueBorder) return tile;
  // Borde con el GRADIENTE de marca de Hue: mismo truco que HueRoomCard
  // (Flutter no pinta Border con gradiente) — Container con el gradiente +
  // padding fino, y el chip real encima tapando el centro.
  return Container(
    padding: const EdgeInsets.all(_hueBorderWidth),
    decoration: BoxDecoration(
      gradient: CceGradients.hueBrand,
      borderRadius: BorderRadius.circular(CceRadii.control),
    ),
    child: tile,
  );
}

/// Escenas agrupadas POR PLANO/room (fuente: DevicesService, sin fetch
/// propio): header con el nombre del plano y adentro las escenas CCE de ese
/// planId + las Hue cuyo roomId corresponde al hueRoomId del plano, mezcladas
/// en el mismo wrap (primero CCE, después Hue alfabético). Lo que no matchea
/// ningún plano cae al final: CCE en 'Sin plano', Hue por room 'sin vincular'.
List<Widget> _sceneSectionList({
  required DevicesService devices,
  required Widget Function(String) label,
  required Widget Function(CceScene) cceTile,
  required Widget Function(HueScene) hueTile,
}) {
  final cceScenes = devices.scenes;
  final hueScenes = devices.hueScenes;
  if (cceScenes.isEmpty && hueScenes.isEmpty) return const [];

  final usedCce = <String>{};
  final usedHue = <String>{};
  final out = <Widget>[];

  Widget sectionWrap(List<CceScene> cce, List<HueScene> hue) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in cce) cceTile(s),
          for (final s in hue) hueTile(s),
        ],
      );

  // Orden de secciones: el orden de los planos como los da devices_service.
  for (final room in devices.rooms) {
    final planId = room.planId;
    final hueRoomId = room.hueRoomId;
    final cce = planId == null
        ? const <CceScene>[]
        : cceScenes.where((s) => s.planId == planId).toList();
    final hue = hueRoomId == null
        ? const <HueScene>[]
        : (hueScenes.where((s) => s.roomId == hueRoomId).toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
    if (cce.isEmpty && hue.isEmpty) continue;
    usedCce.addAll(cce.map((s) => s.id));
    usedHue.addAll(hue.map((s) => s.id));
    out.add(label(room.name));
    out.add(sectionWrap(cce, hue));
  }

  // Escenas CCE sin plano.
  final looseCce = cceScenes.where((s) => !usedCce.contains(s.id)).toList();
  if (looseCce.isNotEmpty) {
    out.add(label('Sin plano'));
    out.add(sectionWrap(looseCce, const []));
  }

  // Rooms de Hue que ningún plano vinculó: sección propia con el NOMBRE del
  // room y la leyenda "sin vincular" (decisión 30/07, espejo del Dashboard) —
  // el bucket genérico 'Otras' escondía de qué room era cada escena.
  final looseHue = hueScenes.where((s) => !usedHue.contains(s.id)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final byRoom = <String, List<HueScene>>{};
  for (final s in looseHue) {
    byRoom.putIfAbsent(s.roomName ?? 'Room desconocido', () => []).add(s);
  }
  for (final e in byRoom.entries) {
    out.add(label('${e.key} · sin vincular'));
    out.add(sectionWrap(const [], e.value));
  }
  return out;
}

/// Grupos agrupados POR PLANO/room — MISMO patrón que [_sceneSectionList],
/// unificando lo que antes eran dos listas planas ("Grupos" y "Rooms de
/// Hue"): header con el nombre del plano y adentro los grupos CCE de ese
/// planId + el room de Hue que el plano vinculó (hueRoomId), con el borde de
/// marca. Grupos sin plano caen en 'Sin plano'; los rooms de Hue que ningún
/// plano vinculó, al final con la leyenda 'sin vincular' (espejo del
/// Dashboard). Nada se descarta.
List<Widget> _groupSectionList({
  required DevicesService devices,
  required Widget Function(String) label,
  required Widget Function(LightGroup) cceTile,
  required Widget Function(HueRoom) hueTile,
}) {
  final groups = devices.groups;
  final hueRooms = devices.hueRooms;
  if (groups.isEmpty && hueRooms.isEmpty) return const [];

  final usedCce = <String>{};
  final usedHue = <String>{};
  final out = <Widget>[];

  Widget sectionWrap(List<LightGroup> cce, List<HueRoom> hue) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final g in cce) cceTile(g),
          for (final r in hue) hueTile(r),
        ],
      );

  // Orden de secciones: el orden de los planos como los da devices_service.
  for (final room in devices.rooms) {
    final planId = room.planId;
    final cce = planId == null
        ? const <LightGroup>[]
        : groups.where((g) => g.planId == planId).toList();
    final hue = [
      for (final r in hueRooms)
        if (room.hueRoomId != null && r.id == room.hueRoomId) r,
    ];
    if (cce.isEmpty && hue.isEmpty) continue;
    usedCce.addAll(cce.map((g) => g.id));
    usedHue.addAll(hue.map((r) => r.id));
    out.add(label(room.name));
    out.add(sectionWrap(cce, hue));
  }

  // Grupos CCE sin plano.
  final looseCce = groups.where((g) => !usedCce.contains(g.id)).toList();
  if (looseCce.isNotEmpty) {
    out.add(label('Sin plano'));
    out.add(sectionWrap(looseCce, const []));
  }

  // Rooms de Hue sin vincular: sección propia por room con la leyenda, igual
  // que las escenas Hue sueltas de [_sceneSectionList].
  final looseHue = hueRooms.where((r) => !usedHue.contains(r.id)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final r in looseHue) {
    out.add(label('${r.name} · sin vincular'));
    out.add(sectionWrap(const [], [r]));
  }
  return out;
}

Color _kindColor(AutomationActionKind kind) {
  switch (kind) {
    case AutomationActionKind.light:
      return CceColors.warm;
    case AutomationActionKind.group:
      return CceColors.accent;
    case AutomationActionKind.hueRoom:
      return _hueOrange;
    case AutomationActionKind.scene:
      return CceColors.accent;
    // Escena Hue en naranja de marca: misma distinción que hueRoom.
    case AutomationActionKind.hueScene:
      return _hueOrange;
    case AutomationActionKind.device:
      return CceColors.info;
    case AutomationActionKind.notification:
      return CceColors.info;
    case AutomationActionKind.alarm:
      return CceColors.danger;
    case AutomationActionKind.jbl:
      return CceColors.ok;
    case AutomationActionKind.advanced:
      return CceColors.textTertiary;
  }
}

Widget _kindIcon(AutomationActionKind kind, Color color) {
  switch (kind) {
    case AutomationActionKind.light:
      return CceIcon(CceIcons.lights, size: 18, color: color);
    case AutomationActionKind.group:
      return CceIcon(CceIcons.room, size: 18, color: color);
    case AutomationActionKind.hueRoom:
      return CceIcon(CceIcons.room, size: 18, color: color);
    case AutomationActionKind.scene:
    case AutomationActionKind.hueScene:
      return CceIcon(CceIcons.scenes, size: 18, color: color);
    case AutomationActionKind.device:
      return Icon(Icons.tune, size: 18, color: color);
    case AutomationActionKind.notification:
      return Icon(Icons.notifications_outlined, size: 18, color: color);
    case AutomationActionKind.alarm:
      return CceIcon(CceIcons.alarmShield, size: 18, color: color);
    case AutomationActionKind.jbl:
      // Wordmark JBL vendoreado (mismo asset del panel de Sonido): la acción
      // es del soundbar, no "música" genérica.
      return CceIcon(CceIcons.jbl, size: 18, color: color);
    case AutomationActionKind.advanced:
      return CceIcon(CceIcons.automations, size: 18, color: color);
  }
}

class _ActionsSheet extends StatefulWidget {
  const _ActionsSheet({
    required this.draft,
    required this.devices,
    required this.config,
  });

  final Automation draft;
  final DevicesService devices;
  final ServerConfig config;

  @override
  State<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends State<_ActionsSheet> {
  Automation get draft => widget.draft;

  Future<void> _editAction(AutomationAction action, {required bool isNew}) async {
    bool? applied;
    switch (action.kind) {
      case AutomationActionKind.light:
        applied = await _showActionEditor(
            (ctx, scroll) => _LightActionEditor(
                action: action, devices: widget.devices, scroll: scroll));
      // Un solo editor para grupos CCE y rooms de Hue: el picker unificado
      // por plano mezcla ambos y al aplicar escribe el contrato que toque.
      case AutomationActionKind.group:
      case AutomationActionKind.hueRoom:
        applied = await _showActionEditor(
            (ctx, scroll) => _GroupActionEditor(
                action: action, devices: widget.devices, scroll: scroll));
      // Un solo editor para escenas CCE y Hue: el picker mezcla ambas y al
      // aplicar escribe el contrato que corresponda.
      case AutomationActionKind.scene:
      case AutomationActionKind.hueScene:
        applied = await _showActionEditor(
            (ctx, scroll) => _SceneActionEditor(
                action: action, devices: widget.devices, scroll: scroll));
      case AutomationActionKind.device:
        applied = await _showActionEditor(
            (ctx, scroll) => _DeviceActionEditor(
                action: action, devices: widget.devices, scroll: scroll));
      case AutomationActionKind.notification:
        applied = await _showActionEditor(
            (ctx, scroll) =>
                _NotificationActionEditor(action: action, scroll: scroll));
      case AutomationActionKind.alarm:
        applied = await _showActionEditor(
            (ctx, scroll) => _AlarmActionEditor(action: action, scroll: scroll));
      case AutomationActionKind.jbl:
        applied = await _showActionEditor(
            (ctx, scroll) => _JblActionEditor(
                action: action, config: widget.config, scroll: scroll));
      case AutomationActionKind.advanced:
        return; // sin lápiz: solo reordenable/borrable
    }
    if (!mounted) return;
    setState(() {
      if (applied == true && isNew) draft.actions.add(action);
    });
  }

  Future<bool?> _showActionEditor(
      Widget Function(BuildContext, ScrollController) builder) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: CceColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
          ),
          child: builder(ctx, scroll),
        ),
      ),
    );
  }

  Future<void> _convertScene() async {
    final scenes = widget.devices.scenes;
    final chosen = await showModalBottomSheet<CceScene>(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Convertir escena en acciones', style: CceText.title),
            const SizedBox(height: 6),
            const Text(
              'Copia las luces de la escena como acciones individuales para '
              'retocarlas una por una. Para activarla tal cual, usá la '
              'acción Escena.',
              style: CceText.caption,
            ),
            const SizedBox(height: 8),
            if (scenes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No hay escenas CCE configuradas',
                    style: CceText.caption),
              ),
            for (final s in scenes)
              ListTile(
                leading: const CceIcon(CceIcons.scenes,
                    color: CceColors.textSecondary),
                title: Text(s.name, style: CceText.body),
                subtitle: Text('${s.lights.length} luces',
                    style: const TextStyle(
                        color: CceColors.textTertiary, fontSize: 12)),
                onTap: () => Navigator.of(sheetContext).pop(s),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      for (final l in chosen.lights) {
        draft.actions.add(AutomationAction.blank({
          'lightId': l.lightId,
          'on': l.on,
          if (l.on && l.bri != null) 'bri': l.bri,
          if (l.on && l.hue != null) 'hue': l.hue,
          if (l.on && l.sat != null) 'sat': l.sat,
          if (l.on && l.ct != null) 'ct': l.ct,
        }));
      }
    });
  }

  Widget _actionRow(AutomationAction act, int index) {
    final color = _kindColor(act.kind);
    final advanced = act.kind == AutomationActionKind.advanced &&
        act.on != 'bri_up' &&
        act.on != 'bri_down';
    return Container(
      key: ObjectKey(act),
      height: 56,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: CceColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CceRadii.control),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
            child: _kindIcon(act.kind, color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionPhrase(act, widget.devices),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: CceColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
                if (advanced)
                  const Text(
                    'Acción avanzada (no editable acá)',
                    style:
                        TextStyle(color: CceColors.textTertiary, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (act.kind != AutomationActionKind.advanced)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Editar',
                icon: const CceIcon(CceIcons.pencil,
                    size: 17, color: CceColors.textSecondary),
                onPressed: () => _editAction(act, isNew: false),
              ),
            ),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              tooltip: 'Eliminar',
              icon: const CceIcon(CceIcons.trash,
                  size: 17, color: CceColors.textTertiary),
              onPressed: () => setState(() => draft.actions.removeAt(index)),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: CceIcon(CceIcons.dragHandle,
                  size: 18, color: CceColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile(String label, Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CceRadii.control),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: CceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: Border.all(color: CceColors.stroke),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: CceColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Acciones (en orden)'),
        if (draft.actions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Sin acciones todavía — agregá con los botones de '
                'abajo.', style: CceText.caption),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: draft.actions.length,
          // onReorder entrega newIndex SIN ajustar por el item removido.
          onReorder: (oldIndex, newIndex) => setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = draft.actions.removeAt(oldIndex);
            draft.actions.insert(newIndex, item);
          }),
          itemBuilder: (context, i) => _actionRow(draft.actions[i], i),
        ),
        _label('Agregar acción'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _addTile(
              'Luz',
              const CceIcon(CceIcons.lights, size: 24, color: CceColors.warm),
              () => _editAction(AutomationAction.light(''), isNew: true),
            ),
            // Un solo tile: el editor unificado ofrece grupos CCE y rooms de
            // Hue juntos, agrupados por plano (antes eran dos tiles).
            _addTile(
              'Grupo',
              const CceIcon(CceIcons.room, size: 24, color: CceColors.accent),
              () => _editAction(AutomationAction.group(''), isNew: true),
            ),
            _addTile(
              'Dispositivo',
              const Icon(Icons.tune, size: 24, color: CceColors.info),
              () => _editAction(AutomationAction.device('', ''), isNew: true),
            ),
            _addTile(
              'Aviso',
              const Icon(Icons.notifications_outlined,
                  size: 24, color: CceColors.info),
              () => _editAction(AutomationAction.notification(), isNew: true),
            ),
            _addTile(
              'Alarma',
              const CceIcon(CceIcons.alarmShield,
                  size: 24, color: CceColors.danger),
              () => _editAction(AutomationAction.alarm(), isNew: true),
            ),
            _addTile(
              'Música',
              // Wordmark JBL vendoreado (ver _kindIcon): identifica al device.
              const CceIcon(CceIcons.jbl, size: 24, color: CceColors.ok),
              () => _editAction(AutomationAction.jbl(), isNew: true),
            ),
            _addTile(
              'Escena',
              const CceIcon(CceIcons.scenes,
                  size: 24, color: CceColors.accent),
              () => _editAction(AutomationAction.scene(''), isNew: true),
            ),
            // Flujo legacy: copia las luces de una escena CCE como acciones
            // sueltas (editable luz por luz), distinto de la acción Escena
            // que activa la escena tal cual.
            _addTile(
              'Copiar escena',
              const CceIcon(CceIcons.scenes,
                  size: 24, color: CceColors.textTertiary),
              _convertScene,
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(text.toUpperCase(), style: CceText.section),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: CceColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CceColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                      child: Text('Entonces', style: CceText.title)),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Listo'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _customBody(),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Editores por tipo de acción
// =============================================================================

class _EditorScaffold extends StatelessWidget {
  const _EditorScaffold({
    required this.title,
    required this.scroll,
    required this.children,
    required this.onApply,
  });

  final String title;
  final ScrollController scroll;
  final List<Widget> children;

  /// Escribe los valores del editor en la acción. null = invalido (Listo
  /// deshabilitado). UN SOLO camino de confirmacion: antes convivian un
  /// "Listo" que popeaba SIN aplicar (descartaba todo en silencio) y un
  /// "Aplicar" al pie que si escribia.
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: CceColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(child: Text(title, style: CceText.title)),
            FilledButton(
              onPressed: onApply == null
                  ? null
                  : () {
                      onApply!();
                      Navigator.of(context).pop(true);
                    },
              child: const Text('Listo'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }
}

Widget _editorLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(text.toUpperCase(), style: CceText.section),
    );

/// Luz: picker + Prender/Apagar/Alternar + brillo % + color/CT.
class _LightActionEditor extends StatefulWidget {
  const _LightActionEditor({
    required this.action,
    required this.devices,
    required this.scroll,
  });

  final AutomationAction action;
  final DevicesService devices;
  final ScrollController scroll;

  @override
  State<_LightActionEditor> createState() => _LightActionEditorState();
}

class _LightActionEditorState extends State<_LightActionEditor> {
  late String _lightId = widget.action.lightId;
  late String _mode = widget.action.on == false
      ? 'off'
      : widget.action.on == 'toggle'
          ? 'toggle'
          : 'on';
  late double _briPct = widget.action.bri != null
      ? ((widget.action.bri! - 1) / 253).clamp(0.0, 1.0).toDouble()
      : 1.0;
  late String _colorMode = (widget.action.sat ?? 0) > 0
      ? 'color'
      : widget.action.ct != null
          ? 'ct'
          : 'none';
  late Color _color = _initialColor();
  late double _ct = (widget.action.ct ?? 350).toDouble();

  Color _initialColor() {
    final hue = widget.action.hue;
    final sat = widget.action.sat;
    if (hue != null && sat != null && sat > 0) {
      return HSVColor.fromAHSV(
        1.0,
        (hue / 65535 * 360).clamp(0.0, 360.0).toDouble(),
        (sat / 254).clamp(0.0, 1.0).toDouble(),
        1.0,
      ).toColor();
    }
    return Colors.amber;
  }

  void _apply() {
    dynamic on;
    int? bri;
    int? hue;
    int? sat;
    int? ct;
    if (_mode == 'on') {
      on = true;
      // % de la UI → bri 1..254.
      bri = (_briPct * 253).round() + 1;
      if (_colorMode == 'color') {
        final hsv = HSVColor.fromColor(_color);
        hue = ((hsv.hue / 360) * 65535).round().clamp(0, 65535);
        sat = (hsv.saturation * 254).round().clamp(1, 254);
      } else if (_colorMode == 'ct') {
        ct = _ct.round().clamp(153, 500);
      }
    } else if (_mode == 'off') {
      on = false;
    } else {
      on = 'toggle';
    }
    widget.action
        .updateLight(lightId: _lightId, on: on, bri: bri, hue: hue, sat: sat, ct: ct);
  }

  @override
  Widget build(BuildContext context) {
    final lights = widget.devices.lights;
    final valid = _lightId.isNotEmpty;
    return _EditorScaffold(
      title: 'Acción de luz',
      scroll: widget.scroll,
      onApply: valid ? _apply : null,
      children: [
        _editorLabel('Luz'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in lights)
              ChoiceChip(
                label: Text(widget.devices.displayName(d)),
                selected: _lightId == d.id,
                showCheckmark: false,
                onSelected: (_) => setState(() => _lightId = d.id),
              ),
          ],
        ),
        _editorLabel('Acción'),
        CceSegmented<String>(
          value: _mode,
          segments: const [
            CceSegment(value: 'on', label: 'Prender'),
            CceSegment(value: 'off', label: 'Apagar'),
            CceSegment(value: 'toggle', label: 'Alternar'),
          ],
          onChanged: (v) => setState(() => _mode = v),
        ),
        if (_mode == 'on') ...[
          _editorLabel('Brillo'),
          CceBrightnessSlider(
            value: _briPct,
            activeColor: _colorMode == 'color' ? _color : null,
            onChanged: (v) => setState(() => _briPct = v),
          ),
          _editorLabel('Color'),
          CceSegmented<String>(
            value: _colorMode,
            segments: const [
              CceSegment(value: 'none', label: 'No cambiar'),
              CceSegment(value: 'color', label: 'Color'),
              CceSegment(value: 'ct', label: 'Blanco'),
            ],
            onChanged: (v) => setState(() => _colorMode = v),
          ),
          if (_colorMode == 'color') ...[
            const SizedBox(height: 14),
            Center(
              child: HueRingPicker(
                pickerColor: _color,
                enableAlpha: false,
                displayThumbColor: true,
                portraitOnly: true,
                colorPickerHeight: 200,
                onColorChanged: (c) => setState(() => _color = c),
              ),
            ),
          ],
          if (_colorMode == 'ct') ...[
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFFBBDEFB), Colors.white, Color(0xFFFFCC80)],
                ),
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 14,
                  thumbColor: Colors.white,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: Slider(
                  min: 153,
                  max: 500,
                  value: _ct.clamp(153, 500).toDouble(),
                  onChanged: (v) => setState(() => _ct = v),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Grupo como acción: UN grupo CCE o room de Hue (borde con el gradiente de
/// marca), agrupados por plano igual que las escenas ([_groupSectionList]),
/// + Prender/Apagar/Alternar. Al aplicar escribe el contrato del backend que
/// corresponda: on:'group'+groupId+groupAction o
/// on:'hueRoom'+hueRoomId+hueRoomAction.
class _GroupActionEditor extends StatefulWidget {
  const _GroupActionEditor({
    required this.action,
    required this.devices,
    required this.scroll,
  });

  final AutomationAction action;
  final DevicesService devices;
  final ScrollController scroll;

  @override
  State<_GroupActionEditor> createState() => _GroupActionEditorState();
}

class _GroupActionEditorState extends State<_GroupActionEditor> {
  // Selección única entre dos namespaces de id: _hue dice de cuál viene.
  late bool _hue = widget.action.kind == AutomationActionKind.hueRoom;
  late String _targetId =
      (_hue ? widget.action.hueRoomId : widget.action.groupId) ?? '';
  // on/off/alternar compartido: al aplicar cae en groupAction o hueRoomAction.
  late String _mode =
      _hue ? widget.action.hueRoomAction : widget.action.groupAction;

  void _apply() {
    if (_hue) {
      widget.action
          .updateHueRoom(hueRoomId: _targetId, hueRoomAction: _mode);
    } else {
      widget.action.updateGroup(groupId: _targetId, groupAction: _mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.devices;
    final empty = devices.groups.isEmpty && devices.hueRooms.isEmpty;
    return _EditorScaffold(
      title: 'Acción de grupo',
      scroll: widget.scroll,
      onApply: _targetId.isEmpty ? null : _apply,
      children: [
        if (empty)
          const Text('No hay grupos ni rooms de Hue configurados.',
              style: CceText.caption)
        else ...[
          ..._groupSectionList(
            devices: devices,
            label: _editorLabel,
            cceTile: (g) => _pickerChip(
              name: g.name,
              selected: !_hue && _targetId == g.id,
              onTap: () => setState(() {
                _hue = false;
                _targetId = g.id;
              }),
            ),
            hueTile: (r) => _pickerChip(
              name: r.name,
              hueBorder: true,
              selected: _hue && _targetId == r.id,
              onTap: () => setState(() {
                _hue = true;
                _targetId = r.id;
              }),
            ),
          ),
          _editorLabel('Acción'),
          CceSegmented<String>(
            value: _mode,
            segments: const [
              CceSegment(value: 'on', label: 'Prender'),
              CceSegment(value: 'off', label: 'Apagar'),
              CceSegment(value: 'toggle', label: 'Alternar'),
            ],
            onChanged: (v) => setState(() => _mode = v),
          ),
        ],
      ],
    );
  }
}

/// Escena como acción: UNA escena CCE o Hue (las Hue con el borde de
/// gradiente de marca), combinable con las demás acciones. Usa el picker
/// agrupado por plano ([_sceneSectionList]) y al aplicar escribe el contrato
/// del backend que corresponda: on:'scene'+sceneId o
/// on:'hueScene'+hueSceneId+sceneSmart.
class _SceneActionEditor extends StatefulWidget {
  const _SceneActionEditor({
    required this.action,
    required this.devices,
    required this.scroll,
  });

  final AutomationAction action;
  final DevicesService devices;
  final ScrollController scroll;

  @override
  State<_SceneActionEditor> createState() => _SceneActionEditorState();
}

class _SceneActionEditorState extends State<_SceneActionEditor> {
  // Selección única entre dos namespaces de id: _hue dice de cuál viene.
  late bool _hue = widget.action.kind == AutomationActionKind.hueScene;
  late String _sceneId =
      (_hue ? widget.action.hueSceneId : widget.action.sceneId) ?? '';

  void _apply() {
    if (_hue) {
      // sceneSmart sale del flag REAL de la lista de escenas Hue (no lo
      // elige el usuario); si la escena ya no está publicada en el bridge se
      // conserva lo persistido en la acción.
      var smart = widget.action.sceneSmart;
      for (final s in widget.devices.hueScenes) {
        if (s.id == _sceneId) {
          smart = s.isSmart;
          break;
        }
      }
      widget.action.updateHueScene(hueSceneId: _sceneId, sceneSmart: smart);
    } else {
      widget.action.updateScene(sceneId: _sceneId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.devices;
    final empty = devices.scenes.isEmpty && devices.hueScenes.isEmpty;
    return _EditorScaffold(
      title: 'Escena',
      scroll: widget.scroll,
      onApply: _sceneId.isEmpty ? null : _apply,
      children: [
        if (empty)
          const Text('No hay escenas configuradas.', style: CceText.caption)
        else
          ..._sceneSectionList(
            devices: devices,
            label: _editorLabel,
            cceTile: (s) => _pickerChip(
              name: s.name,
              selected: !_hue && _sceneId == s.id,
              onTap: () => setState(() {
                _hue = false;
                _sceneId = s.id;
              }),
            ),
            hueTile: (s) => _pickerChip(
              name: s.name,
              swatch: s.swatch,
              isSmart: s.isSmart,
              hueBorder: true,
              selected: _hue && _sceneId == s.id,
              onTap: () => setState(() {
                _hue = true;
                _sceneId = s.id;
              }),
            ),
          ),
      ],
    );
  }
}

/// Acción por CAPABILITY sobre cualquier device: elegís device → verbo del
/// catálogo (no sensitive) → args (enum/bool/número). Persiste {deviceId, verb,
/// args} y se ejecuta por POST /actions/:verb (mismo contrato que el Dashboard).
class _DeviceActionEditor extends StatefulWidget {
  const _DeviceActionEditor({
    required this.action,
    required this.devices,
    required this.scroll,
  });

  final AutomationAction action;
  final DevicesService devices;
  final ScrollController scroll;

  @override
  State<_DeviceActionEditor> createState() => _DeviceActionEditorState();
}

class _DeviceActionEditorState extends State<_DeviceActionEditor> {
  late String _deviceId = widget.action.deviceId;
  late String _verb = widget.action.verb;
  late Map<String, dynamic> _args = Map<String, dynamic>.from(widget.action.args);

  CapabilityCatalog get _cat => widget.devices.capabilityCatalog;

  List<Device> get _actionableDevices => widget.devices.all.where((d) {
        for (final cap in d.capabilities) {
          final spec = _cat.specFor(cap);
          if (spec != null && spec.actions.any((a) => !a.isSensitive)) {
            return true;
          }
        }
        return false;
      }).toList();

  List<CatalogActionSpec> _verbsFor(Device d) {
    final out = <CatalogActionSpec>[];
    for (final cap in d.capabilities) {
      final spec = _cat.specFor(cap);
      if (spec == null) continue;
      for (final a in spec.actions) {
        if (!a.isSensitive) out.add(a);
      }
    }
    return out;
  }

  CatalogActionSpec? get _verbSpec {
    final d = widget.devices.byId(_deviceId);
    if (d == null) return null;
    for (final a in _verbsFor(d)) {
      if (a.verb == _verb) return a;
    }
    return null;
  }

  List<String> _resolveEnum(String ref, Device d) {
    switch (ref) {
      case 'VACUUM_CLEAN_MODES':
        return d.state.cleanModes ?? const [];
      case 'VACUUM_FAN_SPEEDS':
        return d.state.fanSpeeds ?? const [];
      case 'VACUUM_ROOMS':
        return (d.state.rooms ?? const []).map((r) => r.name).toList();
      default:
        return _cat.enumValues(ref);
    }
  }

  bool get _argsComplete {
    final spec = _verbSpec;
    if (spec == null) return false;
    for (final a in spec.args) {
      if (a.required && _args[a.name] == null) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final devices = _actionableDevices;
    final selected = widget.devices.byId(_deviceId);
    final verbs = selected != null ? _verbsFor(selected) : <CatalogActionSpec>[];
    final valid = _deviceId.isNotEmpty && _verb.isNotEmpty && _argsComplete;

    return _EditorScaffold(
      title: 'Acción de dispositivo',
      scroll: widget.scroll,
      onApply: valid
          ? () => widget.action
              .updateDevice(deviceId: _deviceId, verb: _verb, args: _args)
          : null,
      children: [
        _editorLabel('Dispositivo'),
        if (devices.isEmpty)
          const Text('No hay dispositivos con acciones disponibles.',
              style: CceText.caption)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in devices)
                ChoiceChip(
                  label: Text(widget.devices.displayName(d)),
                  selected: _deviceId == d.id,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _deviceId = d.id;
                    _verb = '';
                    _args = {};
                  }),
                ),
            ],
          ),
        if (selected != null) ...[
          _editorLabel('Acción'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in verbs)
                ChoiceChip(
                  label: Text(verbLabel(a.verb)),
                  selected: _verb == a.verb,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _verb = a.verb;
                    _args = _defaultArgs(a);
                  }),
                ),
            ],
          ),
          ..._argControls(selected),
        ],
      ],
    );
  }

  Map<String, dynamic> _defaultArgs(CatalogActionSpec spec) {
    final out = <String, dynamic>{};
    for (final a in spec.args) {
      if (a.defaultValue != null) out[a.name] = a.defaultValue;
    }
    return out;
  }

  List<Widget> _argControls(Device d) {
    final spec = _verbSpec;
    if (spec == null || spec.args.isEmpty) return const [];
    final widgets = <Widget>[];
    for (final arg in spec.args) {
      if (arg.type == 'boolean') {
        widgets.add(_editorLabel(arg.name));
        widgets.add(CceSegmented<bool>(
          value: _args[arg.name] == true,
          segments: const [
            CceSegment(value: true, label: 'Sí'),
            CceSegment(value: false, label: 'No'),
          ],
          onChanged: (v) => setState(() => _args[arg.name] = v),
        ));
      } else if (arg.enumRef != null) {
        final opts = _resolveEnum(arg.enumRef!, d);
        if (opts.isEmpty) continue;
        widgets.add(_editorLabel(verbLabel(spec.verb)));
        widgets.add(Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in opts)
              ChoiceChip(
                label: Text(o),
                selected: _args[arg.name] == o,
                showCheckmark: false,
                onSelected: (_) => setState(() => _args[arg.name] = o),
              ),
          ],
        ));
      } else if (arg.type == 'number' && arg.min != null && arg.max != null) {
        final v = (_args[arg.name] as num?)?.toDouble() ?? arg.min!.toDouble();
        widgets.add(_editorLabel('${arg.name}  ·  ${v.round()}'));
        widgets.add(Slider(
          value: v.clamp(arg.min!.toDouble(), arg.max!.toDouble()),
          min: arg.min!.toDouble(),
          max: arg.max!.toDouble(),
          onChanged: (nv) => setState(() => _args[arg.name] = nv.round()),
        ));
      }
    }
    return widgets;
  }
}

/// Aviso: mensaje + sonido (con preview ▶) + tipo.
class _NotificationActionEditor extends StatefulWidget {
  const _NotificationActionEditor({required this.action, required this.scroll});

  final AutomationAction action;
  final ScrollController scroll;

  @override
  State<_NotificationActionEditor> createState() =>
      _NotificationActionEditorState();
}

class _NotificationActionEditorState extends State<_NotificationActionEditor> {
  late final TextEditingController _message =
      TextEditingController(text: widget.action.notificationMessage);
  late String _sound = widget.action.notificationSound;
  late String _type = widget.action.notificationType;
  final AudioPlayer _player = AudioPlayer();

  static const _presets = [
    'Movimiento detectado',
    'Puerta abierta',
    'Llegó alguien',
    'Todo apagado',
  ];

  static const _soundAssets = {
    'alarm': 'sounds/alarm_siren.wav',
    'doorbell': 'sounds/doorbell.wav',
    'alert': 'sounds/alert.wav',
  };

  @override
  void dispose() {
    _player.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final asset = _soundAssets[_sound];
    if (asset == null) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'Aviso',
      scroll: widget.scroll,
      onApply: _message.text.trim().isEmpty
          ? null
          : () => widget.action.updateNotification(
                message: _message.text.trim(),
                sound: _sound,
                type: _type,
              ),
      children: [
        _editorLabel('Mensaje'),
        TextField(
          controller: _message,
          style: CceText.body,
          decoration: const InputDecoration(
            hintText: 'Texto de la notificación',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              ActionChip(
                label: Text(p),
                onPressed: () => setState(() => _message.text = p),
              ),
          ],
        ),
        _editorLabel('Sonido'),
        Row(
          children: [
            Expanded(
              child: CceSegmented<String>(
                value: _sound,
                segments: const [
                  CceSegment(value: 'alarm', label: 'Alarma'),
                  CceSegment(value: 'doorbell', label: 'Timbre'),
                  CceSegment(value: 'alert', label: 'Alerta'),
                ],
                onChanged: (v) => setState(() => _sound = v),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Escuchar',
              onPressed: _preview,
              icon: const CceIcon(CceIcons.play,
                  size: 18, color: CceColors.textSecondary),
              style: IconButton.styleFrom(
                backgroundColor: CceColors.surfaceHigh,
              ),
            ),
          ],
        ),
        _editorLabel('Importancia'),
        CceSegmented<String>(
          value: _type,
          segments: const [
            CceSegment(value: 'info', label: 'Info'),
            CceSegment(value: 'alert', label: 'Alerta'),
            CceSegment(value: 'critical', label: 'Crítica'),
          ],
          onChanged: (v) => setState(() => _type = v),
        ),
        if (_type == 'critical')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Crítica hace sonar el teléfono hasta que la atiendas',
              style: TextStyle(color: CceColors.textTertiary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Alarma: Armar / Desarmar / Alternar.
class _AlarmActionEditor extends StatefulWidget {
  const _AlarmActionEditor({required this.action, required this.scroll});

  final AutomationAction action;
  final ScrollController scroll;

  @override
  State<_AlarmActionEditor> createState() => _AlarmActionEditorState();
}

class _AlarmActionEditorState extends State<_AlarmActionEditor> {
  late String _alarmAction = widget.action.alarmAction;

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'Alarma',
      scroll: widget.scroll,
      onApply: () => widget.action.updateAlarm(_alarmAction),
      children: [
        _editorLabel('Acción'),
        CceSegmented<String>(
          value: _alarmAction,
          segments: const [
            CceSegment(value: 'arm', label: 'Armar'),
            CceSegment(value: 'disarm', label: 'Desarmar'),
            CceSegment(value: 'toggle', label: 'Alternar'),
          ],
          onChanged: (v) => setState(() => _alarmAction = v),
        ),
      ],
    );
  }
}

/// Música (JBL): On/Off; On → Reanudar / Solo encender / Radio.
class _JblActionEditor extends StatefulWidget {
  const _JblActionEditor({
    required this.action,
    required this.config,
    required this.scroll,
  });

  final AutomationAction action;
  final ServerConfig config;
  final ScrollController scroll;

  @override
  State<_JblActionEditor> createState() => _JblActionEditorState();
}

class _JblActionEditorState extends State<_JblActionEditor> {
  late String _jblAction = widget.action.jblAction == 'off' ? 'off' : 'on';
  late String _onMode = widget.action.jblOnMode ?? 'resume';
  late String? _radioName = widget.action.jblRadioName;
  // Volumen de arranque (escala display 0..31); null = no fijar.
  late int? _volume = widget.action.jblVolume;
  // Iniciar en modo noche al prender.
  late bool _nightMode = widget.action.jblNightMode;
  late final Future<List<String>> _radios = _fetchRadios();

  Future<List<String>> _fetchRadios() async {
    try {
      final resp = await http
          .get(Uri.parse('${widget.config.baseUrl}/jbl/radios'), headers: ServerConfig.tokenHeaders)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final list = data is List ? data : (data is Map ? data['radios'] : null);
      if (list is! List) return [];
      return [
        for (final r in list)
          if (r is String)
            r
          else if (r is Map && r['name'] != null)
            r['name'].toString(),
      ];
    } catch (_) {
      return [];
    }
  }

  bool get _valid =>
      _jblAction == 'off' ||
      _onMode != 'radio' ||
      (_radioName != null && _radioName!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return _EditorScaffold(
      title: 'Música',
      scroll: widget.scroll,
      onApply: _valid
          ? () => widget.action.updateJbl(
                action: _jblAction,
                onMode: _jblAction == 'on' ? _onMode : null,
                radioName: _radioName,
                volume: _jblAction == 'on' ? _volume : null,
                nightMode: _jblAction == 'on' && _nightMode,
              )
          : null,
      children: [
        _editorLabel('Parlante'),
        CceSegmented<String>(
          value: _jblAction,
          segments: const [
            CceSegment(value: 'on', label: 'Prender'),
            CceSegment(value: 'off', label: 'Apagar'),
          ],
          onChanged: (v) => setState(() => _jblAction = v),
        ),
        if (_jblAction == 'on') ...[
          _editorLabel('Al prender'),
          CceSegmented<String>(
            value: _onMode,
            segments: const [
              CceSegment(value: 'resume', label: 'Reanudar'),
              CceSegment(value: 'plain', label: 'Solo encender'),
              CceSegment(value: 'radio', label: 'Radio'),
            ],
            onChanged: (v) => setState(() => _onMode = v),
          ),
          if (_onMode == 'radio') ...[
            _editorLabel('Radio'),
            FutureBuilder<List<String>>(
              future: _radios,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: CceColors.textTertiary),
                      ),
                    ),
                  );
                }
                final radios = snap.data!;
                if (radios.isEmpty) {
                  return const Text('No se pudieron cargar las radios',
                      style: CceText.caption);
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in radios)
                      ChoiceChip(
                        label: Text(r),
                        selected: _radioName == r,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _radioName = r),
                      ),
                  ],
                );
              },
            ),
          ],
          _editorLabel('Volumen de arranque'),
          Row(
            children: [
              Switch(
                value: _volume != null,
                onChanged: (on) => setState(() => _volume = on ? 12 : null),
              ),
              Expanded(
                child: _volume == null
                    ? const Text('Dejar el que tenga',
                        style: CceText.caption)
                    : Slider(
                        value: _volume!.toDouble().clamp(0, 31),
                        min: 0,
                        max: 31,
                        divisions: 31,
                        label: '${_volume}',
                        onChanged: (v) => setState(() => _volume = v.round()),
                      ),
              ),
              if (_volume != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('${_volume}', style: CceText.body),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Iniciar en modo noche', style: CceText.body),
            value: _nightMode,
            onChanged: (v) => setState(() => _nightMode = v),
          ),
        ],
      ],
    );
  }
}
