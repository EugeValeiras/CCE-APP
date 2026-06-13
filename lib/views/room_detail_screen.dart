import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/section_header.dart';
import '../widgets/light_tile.dart';
import '../widgets/scenes_section.dart';
import '../widgets/sensor_tile.dart';

class RoomDetailScreen extends StatefulWidget {
  final String title;
  final List<String> deviceIds;
  final DevicesService service;
  final RoomRef? room; // opcional: habilita la sección de escenas

  const RoomDetailScreen({
    super.key,
    required this.title,
    required this.deviceIds,
    required this.service,
    this.room,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  // Orden de las secciones, persistido localmente. Reordenable desde el menú.
  static const _orderKey = 'room.sectionOrder';
  static const _defaultOrder = ['scenes', 'lights', 'sensors'];
  List<String> _order = List.of(_defaultOrder);

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_orderKey);
      if (saved != null &&
          saved.length == _defaultOrder.length &&
          _defaultOrder.every(saved.contains)) {
        setState(() => _order = saved);
      }
    } catch (_) {}
  }

  Future<void> _saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, _order);
    } catch (_) {}
  }

  DevicesService get service => widget.service;

  Future<void> _toggleAll(List<Device> lights, bool on) async {
    HapticFeedback.selectionClick();
    for (final l in lights) {
      if (l.state.on != on) await service.toggleLight(l);
    }
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.swap_vert, color: CceColors.textPrimary),
              title: const Text('Reordenar secciones',
                  style: TextStyle(color: CceColors.textPrimary)),
              subtitle: const Text('Cambiá el orden de Escenas, Luces y Sensores',
                  style: TextStyle(color: CceColors.textTertiary)),
              onTap: () {
                Navigator.of(context).pop();
                _openReorder();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sectionLabel(String key) => switch (key) {
        'scenes' => 'Escenas',
        'lights' => 'Luces',
        _ => 'Sensores',
      };

  IconData _sectionIcon(String key) => switch (key) {
        'scenes' => Icons.auto_awesome,
        'lights' => Icons.lightbulb_outline,
        _ => Icons.sensors,
      };

  void _openReorder() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CceColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (_) {
        // Copia local que se edita en el sheet; al cerrar persiste.
        final local = List.of(_order);
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reordenar secciones', style: CceText.title),
                    const SizedBox(height: 4),
                    const Text('Mantené y arrastrá para cambiar el orden.',
                        style: TextStyle(color: CceColors.textTertiary)),
                    const SizedBox(height: 12),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: true,
                      onReorder: (oldIndex, newIndex) {
                        setSheet(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = local.removeAt(oldIndex);
                          local.insert(newIndex, item);
                        });
                        setState(() => _order = List.of(local));
                        _saveOrder();
                      },
                      children: [
                        for (final key in local)
                          Container(
                            key: ValueKey(key),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: CceColors.surfaceHigh,
                              borderRadius:
                                  BorderRadius.circular(CceRadii.control),
                            ),
                            child: Row(
                              children: [
                                Icon(_sectionIcon(key),
                                    color: CceColors.textSecondary, size: 20),
                                const SizedBox(width: 12),
                                Text(_sectionLabel(key),
                                    style: const TextStyle(
                                        color: CceColors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                const Icon(Icons.drag_handle,
                                    color: CceColors.textTertiary),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: CceColors.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: CceColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final devices =
            widget.deviceIds.map(service.byId).whereType<Device>().toList();
        final lights = devices
            .where((d) => d.isLight && !d.isSensorDevice)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final sensors = devices.where((d) => d.isSensorDevice).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final onCount = lights.where((l) => l.state.on).length;

        // Slivers por sección, renderizados según _order.
        final sectionSlivers = <String, List<Widget>>{
          'scenes': widget.room != null
              ? [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ScenesSection(
                          service: service, room: widget.room, neo: true),
                    ),
                  ),
                ]
              : const [],
          'lights': lights.isNotEmpty
              ? [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        title:
                            'Luces · $onCount de ${lights.length} encendidas',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: TileSize.medium.maxTileExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: TileSize.medium.tileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ListenableBuilder(
                          listenable: service,
                          builder: (ctx, _) {
                            final d = service.byId(lights[i].id) ?? lights[i];
                            return LightTile(
                                device: d,
                                service: service,
                                size: TileSize.medium,
                                neo: true);
                          },
                        ),
                        childCount: lights.length,
                      ),
                    ),
                  ),
                ]
              : const [],
          'sensors': sensors.isNotEmpty
              ? [
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(title: 'Sensores'),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: TileSize.medium.maxTileExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: TileSize.medium.sensorTileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ListenableBuilder(
                          listenable: service,
                          builder: (ctx, _) {
                            final d = service.byId(sensors[i].id) ?? sensors[i];
                            return SensorTile(
                                device: d,
                                service: service,
                                size: TileSize.medium,
                                neo: true);
                          },
                        ),
                        childCount: sensors.length,
                      ),
                    ),
                  ),
                ]
              : const [],
        };

        return Scaffold(
          backgroundColor: CceColors.neoBase,
          appBar: AppBar(
            backgroundColor: CceColors.neoBase,
            titleSpacing: 4,
            // Back circular (estilo Hue).
            leading: _circleButton(
                Icons.arrow_back, () => Navigator.of(context).maybePop()),
            leadingWidth: 56,
            title: Text(widget.title),
            actions: [
              // Menú "..." (incluye Reordenar secciones).
              _circleButton(Icons.more_horiz, _openMenu),
              // Master toggle de la habitación.
              if (lights.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Switch.adaptive(
                    value: onCount > 0,
                    onChanged: (v) => _toggleAll(lights, v),
                    thumbColor:
                        const WidgetStatePropertyAll<Color>(Colors.white),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: service.refresh,
            color: CceColors.textPrimary,
            backgroundColor: CceColors.surfaceHigh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                for (final key in _order) ...sectionSlivers[key] ?? const [],
                if (devices.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Este plano no tiene dispositivos',
                        style: TextStyle(color: CceColors.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
