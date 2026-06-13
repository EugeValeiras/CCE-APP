import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/room_ref.dart';
import '../models/scene.dart';
import '../services/devices_service.dart';
import '../theme/components/scene_card.dart';
import '../theme/components/section_header.dart';

/// Sección "Mis escenas": grilla de escenas Hue nativas + escenas CCE.
/// [room] == null = "Toda la casa" (todas las Hue + CCE con planId == null).
/// Gestiona busy + anti doble-tap; se auto-oculta si no hay escenas.
///
/// Si la sala tiene plano (planId != null) las escenas se muestran en el
/// orden unificado de `actionOrder` (el MISMO que usa el dashboard web) y
/// se reordenan con long-press + drag, persistiendo vía
/// [DevicesService.reorderSceneKey].
class ScenesSection extends StatefulWidget {
  const ScenesSection({
    super.key,
    required this.service,
    this.room,
    this.title = 'Mis escenas',
    this.maxCrossAxisExtent = 150,
    this.neo = false,
  });

  final DevicesService service;
  final RoomRef? room;
  final String title;
  final double maxCrossAxisExtent;

  /// OPT-IN: relieve neumórfico en las scene cards (default false).
  final bool neo;

  @override
  State<ScenesSection> createState() => _ScenesSectionState();
}

class _ScenesSectionState extends State<ScenesSection> {
  String? _busyId;
  bool _dragging = false;

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busyId != null) return; // anti doble-tap
    setState(() => _busyId = id);
    HapticFeedback.mediumImpact();
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo aplicar la escena')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Ícono de una escena CCE: nombre mdi (kebab-case) → MdiIcons.
  Widget? _cceIcon(CceScene s) {
    final raw = s.icon?.trim();
    if (raw == null || raw.isEmpty) {
      return const Icon(Icons.auto_awesome);
    }
    var name = raw.toLowerCase();
    if (name.startsWith('mdi:')) name = name.substring(4);
    if (name.startsWith('mdi-')) name = name.substring(4);
    // kebab-case → camelCase para MdiIcons.fromString.
    final parts = name.split('-').where((p) => p.isNotEmpty).toList();
    final camel = parts.isEmpty
        ? name
        : parts.first +
            parts
                .skip(1)
                .map((p) => p[0].toUpperCase() + p.substring(1))
                .join();
    final data = MdiIcons.fromString(camel);
    return Icon(data ?? Icons.auto_awesome);
  }

  Future<void> _reorder(String planId, String fromKey, String toKey) async {
    final ok = await widget.service.reorderSceneKey(planId, fromKey, toKey);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo reordenar la escena')),
      );
    }
  }

  /// Envuelve la card para drag&drop (solo salas con plano).
  Widget _draggable(String planId, String key, Widget card) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != key,
      onAcceptWithDetails: (d) => _reorder(planId, d.data, key),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return LongPressDraggable<String>(
          data: key,
          onDragStarted: () => setState(() => _dragging = true),
          onDragEnd: (_) => setState(() => _dragging = false),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 150,
              height: 132,
              child: Opacity(opacity: 0.92, child: card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.30, child: card),
          child: AnimatedScale(
            scale: hovering ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: card,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final room = widget.room;
        final planId = room?.planId;
        final hue = room == null
            ? widget.service.hueScenes
            : widget.service.hueScenesForRoom(room);
        final cce = room == null
            ? widget.service.scenes
                .where((s) => s.planId == null)
                .toList()
            : widget.service.scenesForRoom(room);

        if (hue.isEmpty && cce.isEmpty) return const SizedBox.shrink();

        // Entradas con su key tipada (la misma del actionOrder del dashboard).
        final entries = <(String, Widget)>[
          for (final s in hue)
            (
              'hueScene:${s.id}',
              SceneCard(
                name: s.name,
                colors: s.swatch,
                active: s.isActive,
                isSmart: s.isSmart,
                busy: _busyId == s.id,
                neo: widget.neo,
                onTap: () =>
                    _run(s.id, () => widget.service.recallHueScene(s)),
              ),
            ),
          for (final s in cce)
            (
              'scene:${s.id}',
              SceneCard(
                name: s.name,
                icon: _cceIcon(s),
                busy: _busyId == s.id,
                neo: widget.neo,
                onTap: () => _run(s.id, () => widget.service.applyScene(s)),
              ),
            ),
        ];

        // Orden del dashboard si la sala tiene plano: índice en actionOrder;
        // lo que no figura conserva el orden por defecto al final (sort
        // estable vía decorate con índice original).
        if (planId != null) {
          final orderKeys = widget.service.actionOrderFor(planId);
          final decorated = [
            for (var i = 0; i < entries.length; i++)
              (
                orderKeys.indexOf(entries[i].$1) >= 0
                    ? orderKeys.indexOf(entries[i].$1)
                    : orderKeys.length + i,
                i,
                entries[i],
              ),
          ];
          decorated.sort((a, b) {
            final byOrder = a.$1.compareTo(b.$1);
            return byOrder != 0 ? byOrder : a.$2.compareTo(b.$2);
          });
          entries
            ..clear()
            ..addAll(decorated.map((d) => d.$3));
        }

        final cards = <Widget>[
          for (final e in entries)
            planId != null ? _draggable(planId, e.$1, e.$2) : e.$2,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(title: widget.title),
            // Hint sutil mientras se arrastra.
            if (_dragging)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Soltá sobre otra escena para reordenar',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.maxCrossAxisExtent,
                mainAxisExtent: 132, // alto fijo = SceneCard._height
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              children: cards,
            ),
          ],
        );
      },
    );
  }
}
