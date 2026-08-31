import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/floor_plan.dart';
import '../models/room_ref.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_switch.dart';
import '../theme/components/light_card.dart';
import '../theme/components/section_header.dart';
import '../utils/room_icon.dart';
import '../widgets/light_tile.dart';
import '../widgets/lock_tile.dart';
import '../models/hue_room.dart';
import '../theme/components/hue_room_card.dart';
import '../widgets/vacuum_room_button.dart';
import '../widgets/vacuum_tile.dart';
import '../widgets/media_device_tile.dart';
import '../widgets/room_temperature_header.dart';
import '../widgets/scenes_section.dart';
import '../widgets/sensor_tile.dart';
import '../widgets/thermostat_tile.dart';

class RoomDetailScreen extends StatefulWidget {
  final String title;
  final List<String> deviceIds;
  final DevicesService service;
  final RoomRef? room; // opcional: habilita la sección de escenas

  /// Servicios dedicados de TV / JBL (opcionales): habilitan sus filas en la
  /// sección "Devices" cuando el room los contiene (por posición en su plano).
  final TvService? tv;
  final JblService? jbl;

  const RoomDetailScreen({
    super.key,
    required this.title,
    required this.deviceIds,
    required this.service,
    this.room,
    this.tv,
    this.jbl,
    this.automations,
  });

  /// Opcional: alimenta el indicador de automatizaciones de los tiles.
  final AutomationsService? automations;

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

  /// Spinner del master de Hue mientras el bridge confirma. Es un solo room por
  /// pantalla, así que alcanza un bool (no hace falta un set de ids).
  bool _hueRoomBusy = false;

  /// Prende/apaga el room ENTERO de Hue (grouped_light, una sola llamada).
  Future<void> _toggleHueRoom(HueRoom hueRoom) async {
    if (_hueRoomBusy) return;
    setState(() => _hueRoomBusy = true);
    try {
      await widget.service.setHueRoomOn(hueRoom, hueRoom.on != true);
    } finally {
      if (mounted) setState(() => _hueRoomBusy = false);
    }
  }

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
              subtitle: const Text('Cambiá el orden de Escenas, Luces y Dispositivos',
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
              subtitle: const Text('Ordená las luces y devices de la habitación',
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

  // OJO: solo cambia el LABEL visible ('Devices'); el key persistido sigue
  // siendo 'sensors' (room.sectionOrder) — renombrarlo invalidaría el orden
  // guardado de todos los usuarios.
  String _sectionLabel(String key) => switch (key) {
        'scenes' => 'Escenas',
        'lights' => 'Luces',
        _ => 'Dispositivos',
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
            devices
                .where((d) => d.isLight && !d.isSensorDevice && !d.isThermostat)
                .toList(),
            _lightOrder)
        .map((d) => d.id)
        .toList();
    final sensorIds = _applyOrder(
            devices
                .where((d) =>
                    (d.isSensorDevice || d.isSwitch) && !d.isThermostat && !d.isLock && !d.isVacuum)
                .toList(),
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
                      section('Dispositivos', so, (oldI, newI) {
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
      // También escucha a las automatizaciones: sin esto, el indicador de los
      // tiles se quedaría con el conteo del momento en que se abrió la
      // pantalla — pausar una automatización desde otro lado no lo movería.
      animation: widget.automations == null
          ? service
          : Listenable.merge([service, widget.automations!]),
      builder: (context, _) {
        final devices =
            widget.deviceIds.map(service.byId).whereType<Device>().toList();
        final lights = _applyOrder(
            devices
                .where((d) => d.isLight && !d.isSensorDevice && !d.isThermostat)
                .toList(),
            _lightOrder);
        // Termostato del room → header fijo arriba del contenido (no es una
        // sección reordenable). Tomamos el primario (alfabético) si hay varios.
        final thermostats =
            devices.where((d) => d.isThermostat).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        // (El termostato ya no se renderiza aparte: RoomTemperatureHeader es
        // el header único de clima y lo muestra con +/− si es lo elegido.)
        final sensors = _applyOrder(
            devices
                .where((d) =>
                    (d.isSensorDevice || d.isSwitch) && !d.isThermostat && !d.isLock && !d.isVacuum)
                .toList(),
            _sensorOrder);
        // Cerraduras del room → sección propia (no reordenable, fija al final).
        final locks = devices.where((d) => d.isLock).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        // Pertenencia de TV/JBL derivada de los DEVICES del room ("todos son
        // dispositivos"): dev_tv-*/dev_jbl existen en /merged y desde CCE#54
        // `rooms` los mete en los deviceIds de la habitación cuyo PLANO los
        // ubica, además de las rooms de fallback (groups/_orphans). Así que
        // alcanza con mirar los devices: ya no hace falta cruzar
        // tv/jblPositions acá, y un Samsung por habitación tiene su tile.
        final planId = widget.room?.planId;
        final tvsInRoom = devices
            .where((d) =>
                DevicesService.isDedicatedDevice(d, DedicatedFamily.tv))
            .toList();
        final jblsInRoom = devices
            .where((d) =>
                DevicesService.isDedicatedDevice(d, DedicatedFamily.jbl))
            .toList();
        final hasTv = widget.tv != null && tvsInRoom.isNotEmpty;
        final hasJbl = widget.jbl != null && jblsInRoom.isNotEmpty;
        // TODOS los termostatos entran a la sección Devices como tiles
        // (pedido del dueño v1.62): el primario aparece dos veces a propósito
        // — como ThermostatHeaderCard fijo arriba Y como tile en la lista.
        final extraThermostats = thermostats;
        // Room de Hue vinculado: el master on/off de las luces de esta room.
        // Va PINNEADO al frente de la grilla de Luces (no en Escenas: prender
        // el room entero no es aplicar una escena, es el master del grupo).
        final hueRoom =
            widget.room == null ? null : service.hueRoomForRoom(widget.room!);
        final hasHueRoom = hueRoom != null;

        final vacuums = devices.where((d) => d.isVacuum).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        // El robot es un device MÁS: entra a la grilla de "Devices" junto a los
        // termostatos, el TV y el JBL, en vez de tener su sección aparte.
        final extraCount = extraThermostats.length +
            (hasTv ? tvsInRoom.length : 0) +
            (hasJbl ? jblsInRoom.length : 0) +
            vacuums.length;
        final onCount = lights.where((l) => l.state.on).length;
        // Color representativo del room (mismo tint normalizado que usa RoomCard
        // en la home): el master toggle PRENDE con el color del room en vez del
        // ámbar por defecto. Sin RoomRef (vistas sin sala) cae a cálido.
        final Color masterAccent =
            (widget.room != null ? service.statsFor(widget.room!).tint : null) ??
                CceColors.warm;

        // Sección "Robot": fija (como Cerraduras) — solo si el room tiene
        // asignado un robot aspiradora.
        // Botón "Limpiar esta habitación": sale del vínculo que se configura
        // en el dashboard (floorPlans[].vacuumRoom). El widget se auto-oculta
        // si no hay vínculo, robot o habitación resoluble.
        final fp = service.floorPlans;
        final FloorPlan? roomPlan = (planId != null && fp != null)
            ? fp.plans.where((p) => p.id == planId).firstOrNull
            : null;
        final vacuumRoomSlivers = <Widget>[
          if (roomPlan?.vacuumRoom != null)
            SliverPadding(
              // Mismo ritmo que el header de clima que tiene arriba (16/8/16/4),
              // con un poco más de aire abajo para separarlo de las secciones.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverToBoxAdapter(
                child: VacuumRoomButton(
                  service: service,
                  plan: roomPlan,
                  neo: true,
                ),
              ),
            ),
        ];
        final lockSlivers = <Widget>[
          if (locks.isNotEmpty) ...[
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: 'Cerraduras'),
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
                      final d = service.byId(locks[i].id) ?? locks[i];
                      return LockTile(
                          device: d,
                          service: service,
                          size: TileSize.medium,
                          neo: true);
                    },
                  ),
                  childCount: locks.length,
                ),
              ),
            ),
          ],
        ];

        // Slivers por sección, renderizados según _order.
        final sectionSlivers = <String, List<Widget>>{
          // Escenas como chips de 44 px en una fila con scroll horizontal
          // (antes una grilla de cards de 118 px donde una escena sola
          // parecía un error de layout).
          'scenes': widget.room != null
              ? [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ScenesSection(
                        service: service,
                        room: widget.room,
                        title: 'Escenas',
                        chips: true,
                      ),
                    ),
                  ),
                ]
              : const [],
          // Luces en grilla de DOS columnas de tiles compactos (78 px): con
          // tres columnas de 113 px los nombres de dos líneas se cortaban a
          // media altura; con dos, el nombre entra entero y en una pantalla
          // caben 14 de 15 luces en vez de 6.
          'lights': (lights.isNotEmpty || hasHueRoom)
              ? [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        title: 'Luces',
                        counter: '$onCount de ${lights.length} encendidas',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        // El gap entre tiles es el mismo aire que tienen
                        // adentro (ver LightCard.kCompactPadding).
                        mainAxisSpacing: LightCard.kCompactPadding,
                        crossAxisSpacing: LightCard.kCompactPadding,
                        mainAxisExtent: LightCard.kCompactHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ListenableBuilder(
                          listenable: service,
                          builder: (ctx, _) {
                            if (hasHueRoom && i == 0) {
                              final hr = service.hueRoomForRoom(widget.room!) ??
                                  hueRoom;
                              return HueRoomCard(
                                name: hr.name,
                                on: hr.on,
                                archetype: hr.archetype,
                                busy: _hueRoomBusy,
                                neo: true,
                                compact: true,
                                onTap: () => _toggleHueRoom(hr),
                              );
                            }
                            final li = hasHueRoom ? i - 1 : i;
                            final d = service.byId(lights[li].id) ?? lights[li];
                            return LightTile(
                                device: d,
                                service: service,
                                size: TileSize.medium,
                                neo: true,
                                compact: true,
                                automations: widget.automations);
                          },
                        ),
                        childCount: lights.length + (hasHueRoom ? 1 : 0),
                      ),
                    ),
                  ),
                ]
              : const [],
          // "Devices" (ex "Sensores"): sensores (orden persistido intacto) →
          // termostatos extra → TV → JBL, en UN solo grid indexado. Los tiles
          // nuevos van fijos al final (no participan del reorder).
          'sensors': (sensors.isNotEmpty || extraCount > 0)
              ? [
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(title: 'Dispositivos'),
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
                        (context, i) {
                          if (i < sensors.length) {
                            return ListenableBuilder(
                              listenable: service,
                              builder: (ctx, _) {
                                final d =
                                    service.byId(sensors[i].id) ?? sensors[i];
                                return SensorTile(
                                    device: d,
                                    service: service,
                                    size: TileSize.medium,
                                    neo: true);
                              },
                            );
                          }
                          var j = i - sensors.length;
                          if (j < extraThermostats.length) {
                            final t = extraThermostats[j];
                            return ListenableBuilder(
                              listenable: service,
                              builder: (ctx, _) {
                                final d = service.byId(t.id) ?? t;
                                return ThermostatTile(
                                    device: d,
                                    service: service,
                                    size: TileSize.medium,
                                    neo: true);
                              },
                            );
                          }
                          j -= extraThermostats.length;
                          if (j < vacuums.length) {
                            final v = vacuums[j];
                            return ListenableBuilder(
                              listenable: service,
                              builder: (ctx, _) {
                                final d = service.byId(v.id) ?? v;
                                return VacuumTile(
                                    device: d,
                                    service: service,
                                    size: TileSize.medium,
                                    neo: true);
                              },
                            );
                          }
                          j -= vacuums.length;
                          if (hasTv) {
                            if (j < tvsInRoom.length) {
                              return TvDeviceTile(
                                  service: widget.tv!,
                                  devices: service,
                                  deviceId: tvsInRoom[j].id,
                                  size: TileSize.medium,
                                  neo: true);
                            }
                            j -= tvsInRoom.length;
                          }
                          return JblDeviceTile(
                              service: widget.jbl!,
                              size: TileSize.medium,
                              neo: true);
                        },
                        childCount: sensors.length + extraCount,
                      ),
                    ),
                  ),
                ]
              : const [],
        };

        return Scaffold(
          backgroundColor: CceColors.bg,
          appBar: AppBar(
            backgroundColor: CceColors.bg,
            // Sin flecha de atrás: se vuelve con el swipe nativo de iOS.
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            // Icono de la habitación junto al nombre (mismo que la card y el
            // dashboard). Solo en rooms reales (no en pantallas sin RoomRef).
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.room != null) ...[
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Center(
                      child: roomGlyphBuilder(widget.room!, service, size: 24)(
                          CceColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(widget.title, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
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
                      accent: masterAccent,
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
                // Clima de la room (termómetro/higrómetro): header fijo arriba
                // de todo, espejo del banner del tablet. Se auto-oculta sin
                // sensores. Solo con RoomRef real: sin room el scope caería a
                // toda la casa.
                if (widget.room != null)
                  SliverPadding(
                    // compact anula el padding vertical interno de la card:
                    // este wrapper repone el ritmo, espejo del tablet
                    // (room_panel.dart usa fromLTRB(24, 4, 24, 4)).
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: RoomTemperatureHeader(
                        service: service,
                        room: widget.room!,
                        compact: true,
                        neo: true,
                      ),
                    ),
                  ),
                // "Limpiar esta habitación" va ARRIBA, junto al clima: es una
                // acción de la room entera, como el master de luces, no un
                // apéndice. Al fondo —después de luces, devices y cerraduras—
                // quedaba fuera de pantalla en cualquier room con varias luces.
                ...vacuumRoomSlivers,
                // El termostato YA NO tiene card propia acá: RoomTemperatureHeader
                // es el header ÚNICO de clima y lo renderiza con +/− cuando es
                // lo elegido (antes se duplicaba la misma temperatura en dos
                // cards, una encima de la otra).
                for (final key in _order) ...sectionSlivers[key] ?? const [],
                ...lockSlivers,
                // Una room de plano solo-con-TV/JBL ya no es "vacía".
                if (devices.isEmpty && !hasTv && !hasJbl)
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
