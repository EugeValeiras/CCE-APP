import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_switch.dart';
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

  // Orden de los elementos (deviceIds) por sección, persistido por habitación.
  List<String> _lightOrder = [];
  List<String> _sensorOrder = [];

  String get _roomKey => widget.room?.id ?? widget.title;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_orderKey);
      final lo = prefs.getStringList('room.$_roomKey.lightOrder');
      final so = prefs.getStringList('room.$_roomKey.sensorOrder');
      setState(() {
        if (saved != null &&
            saved.length == _defaultOrder.length &&
            _defaultOrder.every(saved.contains)) {
          _order = saved;
        }
        if (lo != null) _lightOrder = lo;
        if (so != null) _sensorOrder = so;
      });
    } catch (_) {}
  }

  Future<void> _saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, _order);
    } catch (_) {}
  }

  Future<void> _saveItemOrder(String section, List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('room.$_roomKey.${section}Order', ids);
    } catch (_) {}
  }

  /// Ordena [items] según [order] (los conocidos en ese orden; el resto al
  /// final, alfabético). Si [order] está vacío → alfabético.
  List<Device> _applyOrder(List<Device> items, List<String> order) {
    items.sort((a, b) => a.name.compareTo(b.name));
    if (order.isEmpty) return items;
    final idx = {for (var i = 0; i < order.length; i++) order[i]: i};
    items.sort((a, b) {
      final ia = idx[a.id], ib = idx[b.id];
      if (ia != null && ib != null) return ia.compareTo(ib);
      if (ia != null) return -1;
      if (ib != null) return 1;
      return a.name.compareTo(b.name);
    });
    return items;
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
            ListTile(
              leading:
                  const Icon(Icons.drag_indicator, color: CceColors.textPrimary),
              title: const Text('Reordenar elementos',
                  style: TextStyle(color: CceColors.textPrimary)),
              subtitle: const Text('Ordená las luces y sensores de la habitación',
                  style: TextStyle(color: CceColors.textTertiary)),
              onTap: () {
                Navigator.of(context).pop();
                _openReorderItems();
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

  void _openReorderItems() {
    final devices =
        widget.deviceIds.map(service.byId).whereType<Device>().toList();
    final lightIds = _applyOrder(
            devices.where((d) => d.isLight && !d.isSensorDevice).toList(),
            _lightOrder)
        .map((d) => d.id)
        .toList();
    final sensorIds = _applyOrder(
            devices.where((d) => d.isSensorDevice || d.isSwitch).toList(),
            _sensorOrder)
        .map((d) => d.id)
        .toList();
    if (lightIds.isEmpty && sensorIds.isEmpty) return;

    String nameOf(String id) {
      final d = service.byId(id);
      return d != null ? service.displayName(d) : id;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: CceColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (_) {
        final lo = List.of(lightIds);
        final so = List.of(sensorIds);
        return StatefulBuilder(
          builder: (context, setSheet) {
            Widget reorderTile(String id) => Container(
                  key: ValueKey(id),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: CceColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(CceRadii.control),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(nameOf(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: CceColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.drag_handle,
                          color: CceColors.textTertiary),
                    ],
                  ),
                );

            Widget section(String title, List<String> ids,
                void Function(int, int) onReorder) {
              if (ids.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(title.toUpperCase(), style: CceText.section),
                  ),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: onReorder,
                    children: [for (final id in ids) reorderTile(id)],
                  ),
                ],
              );
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reordenar elementos', style: CceText.title),
                      const SizedBox(height: 4),
                      const Text('Mantené y arrastrá cada elemento.',
                          style: TextStyle(color: CceColors.textTertiary)),
                      section('Luces', lo, (oldI, newI) {
                        setSheet(() {
                          if (newI > oldI) newI -= 1;
                          lo.insert(newI, lo.removeAt(oldI));
                        });
                        setState(() => _lightOrder = List.of(lo));
                        _saveItemOrder('light', lo);
                      }),
                      section('Sensores', so, (oldI, newI) {
                        setSheet(() {
                          if (newI > oldI) newI -= 1;
                          so.insert(newI, so.removeAt(oldI));
                        });
                        setState(() => _sensorOrder = List.of(so));
                        _saveItemOrder('sensor', so);
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final devices =
            widget.deviceIds.map(service.byId).whereType<Device>().toList();
        final lights = _applyOrder(
            devices.where((d) => d.isLight && !d.isSensorDevice).toList(),
            _lightOrder);
        final sensors = _applyOrder(
            devices.where((d) => d.isSensorDevice || d.isSwitch).toList(),
            _sensorOrder);
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
            // Sin flecha de atrás: se vuelve con el swipe nativo de iOS.
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Text(widget.title),
            actions: [
              // Menú "..." (incluye Reordenar secciones).
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CceNeoIconButton(
                  icon: Icons.more_horiz,
                  onPressed: _openMenu,
                  tooltip: 'Menú',
                ),
              ),
              // Master toggle de la habitación.
              if (lights.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Transform.scale(
                    scale: 1.2,
                    child: CceSwitch(
                      value: onCount > 0,
                      onChanged: (v) => _toggleAll(lights, v),
                    ),
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
