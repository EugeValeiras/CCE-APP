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
class ScenesSection extends StatefulWidget {
  const ScenesSection({
    super.key,
    required this.service,
    this.room,
    this.title = 'Mis escenas',
    this.maxCrossAxisExtent = 200,
  });

  final DevicesService service;
  final RoomRef? room;
  final String title;
  final double maxCrossAxisExtent;

  @override
  State<ScenesSection> createState() => _ScenesSectionState();
}

class _ScenesSectionState extends State<ScenesSection> {
  String? _busyId;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final room = widget.room;
        // Orden: primero Hue (smart primero — ya vienen ordenadas por la API),
        // luego las escenas CCE.
        final hue = room == null
            ? widget.service.hueScenes
            : widget.service.hueScenesForRoom(room);
        final cce = room == null
            ? widget.service.scenes
                .where((s) => s.planId == null)
                .toList()
            : widget.service.scenesForRoom(room);

        if (hue.isEmpty && cce.isEmpty) return const SizedBox.shrink();

        final cards = <Widget>[
          for (final s in hue)
            SceneCard(
              name: s.name,
              colors: s.swatch,
              active: s.isActive,
              isSmart: s.isSmart,
              busy: _busyId == s.id,
              onTap: () => _run(s.id, () => widget.service.recallHueScene(s)),
            ),
          for (final s in cce)
            SceneCard(
              name: s.name,
              icon: _cceIcon(s),
              busy: _busyId == s.id,
              onTap: () => _run(s.id, () => widget.service.applyScene(s)),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(title: widget.title),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.maxCrossAxisExtent,
                mainAxisExtent: 100, // alto fijo = SceneCard
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              children: cards,
            ),
          ],
        );
      },
    );
  }
}
