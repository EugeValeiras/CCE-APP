import 'package:flutter/material.dart';
import '../models/room_ref.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../services/socket_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_segmented.dart';
import '../theme/components/section_header.dart';
import '../widgets/light_tile.dart';
import '../widgets/sensor_tile.dart';
import '../widgets/thermostat_tile.dart';
import '../widgets/thermostat_home_card.dart';
import '../widgets/room_temperature_header.dart';
import 'agent/chat_screen_tablet.dart';
import 'alarm_view.dart';
import 'automations/automations_view.dart';
import 'floor_plan_tab.dart';
import 'history_screen.dart';
import 'settings_view.dart';
import 'thermostat_screen.dart';
import 'soundbar/soundbar_screen.dart';
import 'soundbar/soundbar_home_card.dart';
import 'tv/tv_screen.dart';
import 'tv/tv_home_card.dart';
import 'tablet/room_panel.dart';
import 'tablet/rooms_sidebar.dart';

/// Shell tablet estilo Hue: barra de navegación ABAJO (Casa,
/// Automatizaciones, Historial, Agente, Alarma, Ajustes — labels en
/// mayúsculas chicas como Hue) y la tab Casa como split view:
/// sidebar de habitaciones + panel derecho (plano de toda la casa o detalle
/// de la habitacion seleccionada).
class TabletHomeView extends StatefulWidget {
  final ServerConfig config;
  const TabletHomeView({super.key, required this.config});

  @override
  State<TabletHomeView> createState() => _TabletHomeViewState();
}

class _TabletHomeViewState extends State<TabletHomeView> {
  late SocketService _socket;
  late DevicesService _devices;
  late final JblService _jbl;
  late final TvService _tv;
  final UiSettingsService _ui = UiSettingsService();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
    _jbl = JblService(config: widget.config, socket: _socket);
    _tv = TvService(config: widget.config, socket: _socket);
    // Seed + suscripción al socket (como el phone): las cards de TV/JBL viven en
    // la home (lista), así que el estado debe estar siempre fresco. F13: sin
    // timer; dev_jbl/dev_tv empujan device:state-changed.
    _jbl.startPolling();
    _tv.startPolling();
    _ui.load();
  }

  @override
  void dispose() {
    _jbl.dispose();
    _tv.dispose();
    _devices.dispose();
    _socket.dispose();
    _ui.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsView(
          config: widget.config,
          onSaved: () {
            _socket.disconnect();
            _socket.connect(widget.config);
            _devices.refresh();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ui,
      builder: (context, _) {
        // AlarmView SIEMPRE montada (IndexedStack) para escuchar
        // alarm:triggered en foreground aunque se este en otra tab.
        final tabs = <Widget>[
          _CasaSplit(devices: _devices, ui: _ui, jbl: _jbl, tv: _tv),
          AutomationsView(devices: _devices, config: widget.config),
          HistoryScreen(config: widget.config, devices: _devices, neo: true),
          ChatScreenTablet(config: widget.config),
          AlarmView(initialConfig: widget.config, neo: true),
        ];

        return Scaffold(
          backgroundColor: CceColors.neoBase,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(index: _tab, children: tabs),
                ),
                _HueBottomNav(
                  selected: _tab,
                  // El polling de soundbar/TV es continuo (ver initState), así
                  // que el cambio de tab solo actualiza el índice.
                  onSelect: (i) => setState(() => _tab = i),
                  onSettings: _openSettings,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Barra de navegación inferior estilo Hue: íconos + labels en MAYÚSCULAS
/// chicas, activo blanco / inactivos gris, fondo surface con hairline arriba.
class _HueBottomNav extends StatelessWidget {
  const _HueBottomNav({
    required this.selected,
    required this.onSelect,
    required this.onSettings,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onSettings;

  static const _items = <(String, String)>[
    (CceIcons.allHouse, 'Casa'),
    (CceIcons.automations, 'Automatizaciones'),
    (CceIcons.history, 'Historial'),
    (CceIcons.agent, 'Agente'),
    (CceIcons.alarmShield, 'Alarma'),
    (CceIcons.settings, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    // Mismo patrón que el phone: barra neoBase con relieve raised (la sombra
    // inferior sale del viewport; el highlight superior es el borde visible).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        boxShadow: CceShadows.neo(blur: 16, offset: 6),
      ),
      child: Container(
        height: 64,
        color: CceColors.neoBase,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  svg: _items[i].$1,
                  label: _items[i].$2,
                  // Ajustes (último) no es tab: abre la pantalla y no queda
                  // marcado como activo.
                  active: i == selected && i < _items.length - 1,
                  onTap: i == _items.length - 1
                      ? onSettings
                      : () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.svg,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String svg;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? CceColors.neoText : CceColors.textTertiary;
    return InkWell(
      onTap: onTap,
      // El ripple sigue la esquina redondeada del item neumórfico.
      borderRadius: BorderRadius.circular(CceRadii.control),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          // color opaco obligatorio para que el BlurStyle.inner se vea.
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.control),
          // Item activo HUNDIDO; inactivos planos (sin sombra) para no pisar
          // los relieves entre items contiguos.
          boxShadow: active ? CceShadows.neoInset(blur: 6, offset: 2) : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CceIcon(svg, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Split view de la tab Casa: sidebar de habitaciones (320 px) + panel
/// derecho ("Toda la casa" con el plano completo, o RoomPanel de la sala
/// seleccionada).
class _CasaSplit extends StatefulWidget {
  const _CasaSplit({
    required this.devices,
    required this.ui,
    required this.jbl,
    required this.tv,
  });

  final DevicesService devices;
  final UiSettingsService ui;
  final JblService jbl;
  final TvService tv;

  @override
  State<_CasaSplit> createState() => _CasaSplitState();
}

class _CasaSplitState extends State<_CasaSplit> {
  String? _selectedRoomId; // null = Toda la casa
  // Device dedicado seleccionado para mostrar su control INLINE en el panel
  // derecho ('tv' | 'jbl' | null). La tablet no tiene swipe-back, así que el
  // control va en el panel (se vuelve tocando "Toda la casa" o una sala).
  String? _selectedDevice;

  IconData _sizeIcon(TileSize s) {
    switch (s) {
      case TileSize.small:
        return Icons.view_comfy;
      case TileSize.medium:
        return Icons.grid_view;
      case TileSize.large:
        return Icons.view_module;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.devices,
      builder: (context, _) {
        // Resolucion segura: si la sala seleccionada desaparecio tras un
        // refresh/config:changed, volver a "Toda la casa" en el mismo frame.
        final RoomRef? room = _selectedRoomId == null
            ? null
            : widget.devices.rooms
                .where((r) => r.id == _selectedRoomId)
                .firstOrNull;
        if (_selectedRoomId != null && room == null) {
          _selectedRoomId = null;
        }

        // Termostato destacado en la sidebar (3er dispositivo dedicado, junto a
        // TV/JBL). Vive dentro de DevicesService; tomamos el primero si existe.
        final thermostat = widget.devices.thermostats.isNotEmpty
            ? widget.devices.thermostats.first
            : null;

        // Panel derecho: si hay un device dedicado seleccionado, su control
        // INLINE; si no, la sala (RoomPanel) o "Toda la casa".
        Widget panel;
        final String? thermostatId =
            (_selectedDevice != null && _selectedDevice!.startsWith('thermostat:'))
                ? _selectedDevice!.substring('thermostat:'.length)
                : null;
        if (_selectedDevice == 'tv') {
          panel = TvScreen(service: widget.tv);
        } else if (_selectedDevice == 'jbl') {
          panel = SoundbarScreen(service: widget.jbl);
        } else if (thermostatId != null) {
          // Termostato INLINE en el panel derecho (igual que TV/JBL). Si el
          // device ya no existe, cae a "Toda la casa".
          final dev = widget.devices.byId(thermostatId);
          panel = dev != null
              ? ThermostatScreen(device: dev, service: widget.devices)
              : _buildAllHouse();
        } else if (room == null) {
          panel = _buildAllHouse();
        } else {
          panel = RoomPanel(
            service: widget.devices,
            ui: widget.ui,
            room: room,
            tileSize: widget.ui.tileSize,
            onCycleTileSize: widget.ui.cycle,
            onRefresh: widget.devices.refresh,
            neo: true,
            // Item 6: markers TV/JBL en el plano de la sala; tap abre el
            // control inline en el panel derecho (mismos callbacks que las
            // cards y que "Toda la casa").
            tv: widget.tv,
            jbl: widget.jbl,
            onOpenTv: () => setState(() => _selectedDevice = 'tv'),
            onOpenJbl: () => setState(() => _selectedDevice = 'jbl'),
            onOpenThermostat: (d) =>
                setState(() => _selectedDevice = 'thermostat:${d.id}'),
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 320,
              // Logo arriba + lista con "Toda la casa" primero y las cards de
              // TV/JBL integradas COMO PARTE de la lista (deviceCards), como en
              // la mobile app. En tablet, tocarlas muestra el control en el
              // panel derecho (onOpen), NO una pantalla pusheada full-screen.
              child: RoomsSidebar(
                service: widget.devices,
                selectedRoomId: _selectedDevice == null ? _selectedRoomId : '',
                onSelect: (id) => setState(() {
                  _selectedRoomId = id;
                  _selectedDevice = null; // volver desde un control
                }),
                neo: true,
                deviceCards: [
                  TvHomeCard(
                    service: widget.tv,
                    neo: true,
                    onOpen: () => setState(() => _selectedDevice = 'tv'),
                  ),
                  SoundbarHomeCard(
                    service: widget.jbl,
                    neo: true,
                    onOpen: () => setState(() => _selectedDevice = 'jbl'),
                  ),
                  if (thermostat != null)
                    ThermostatHomeCard(
                      service: widget.devices,
                      device: thermostat,
                      neo: true,
                      onOpen: () => setState(() =>
                          _selectedDevice = 'thermostat:${thermostat.id}'),
                    ),
                ],
              ),
            ),
            const VerticalDivider(),
            Expanded(child: panel),
          ],
        );
      },
    );
  }

  // Clave del modo Luces/Plano para "Toda la casa" en UiSettingsService.
  static const String _allHouseKey = '_all';

  Widget _buildAllHouse() {
    final tileSize = widget.ui.tileSize;
    // "Toda la casa" arranca en Plano (vista de la casa completa); la
    // elección del usuario persiste en el service como cualquier room.
    final mode = widget.ui
        .panelModeFor(_allHouseKey, fallback: RoomPanelMode.plan);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // "Mi casa" ya es el header de la sidebar: acá jerarquía menor.
              const Expanded(
                child: Text(
                  'Toda la casa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.title,
                ),
              ),
              SizedBox(
                width: 260,
                child: CceSegmented<RoomPanelMode>(
                  value: mode,
                  segments: const [
                    CceSegment(
                      value: RoomPanelMode.lights,
                      label: 'Luces',
                      icon: CceIcon(CceIcons.lights),
                    ),
                    CceSegment(
                      value: RoomPanelMode.plan,
                      label: 'Plano',
                      icon: CceIcon(CceIcons.floorPlan),
                    ),
                  ],
                  onChanged: (m) => widget.ui.setPanelMode(_allHouseKey, m),
                  neo: true,
                ),
              ),
              const SizedBox(width: 12),
              CceNeoIconButton(
                icon: _sizeIcon(tileSize),
                tooltip: 'Tamaño: ${tileSize.label}',
                onPressed: widget.ui.cycle,
              ),
              const SizedBox(width: 8),
              CceNeoIconButton(
                icon: Icons.refresh,
                tooltip: 'Actualizar',
                onPressed: widget.devices.refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Hero de clima de toda la casa, ahora tappable como el del phone:
          // room omitido ⇒ scope toda la casa + picker + persistencia en
          // 'home.tempSensorId' (la MISMA key que el hero del phone — ambos
          // form factors comparten el termómetro elegido). El estado/prefs
          // viven dentro del header; _CasaSplitState no suma estado.
          RoomTemperatureHeader(service: widget.devices, neo: true),
          Expanded(
            child: mode == RoomPanelMode.plan
                ? FloorPlanPanel(
                    service: widget.devices,
                    ui: widget.ui,
                    dotSize: tileSize.floorPlanDotSize,
                    neo: true,
                    // Markers de TV / JBL en el plano (item 4): el color sigue
                    // el status (online/power) vía AnimatedBuilder sobre los
                    // services. Tap → abre el control inline en el panel
                    // derecho (item 5), mismo destino que las cards.
                    tv: widget.tv,
                    jbl: widget.jbl,
                    onOpenTv: () => setState(() => _selectedDevice = 'tv'),
                    onOpenJbl: () => setState(() => _selectedDevice = 'jbl'),
                    onOpenThermostat: (d) => setState(
                        () => _selectedDevice = 'thermostat:${d.id}'),
                  )
                : _AllHouseLights(
                    service: widget.devices,
                    tileSize: tileSize,
                    onOpenThermostat: (id) => setState(
                        () => _selectedDevice = 'thermostat:$id'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Modo "Luces" de Toda la casa: escenas globales + grillas de todas las
/// luces y sensores (mismo layout que RoomPanel pero sin filtrar por sala).
class _AllHouseLights extends StatelessWidget {
  const _AllHouseLights({
    required this.service,
    required this.tileSize,
    this.onOpenThermostat,
  });

  final DevicesService service;
  final TileSize tileSize;

  /// TABLET: abre un termostato INLINE en el panel derecho (lo resuelve el State
  /// padre). Recibe el id del device; null ⇒ el tile cae a su push de ruta.
  final void Function(String id)? onOpenThermostat;

  @override
  Widget build(BuildContext context) {
    final lights = service.lights;
    final thermostats = service.thermostats;
    final sensors = service.sensors;
    if (lights.isEmpty && thermostats.isEmpty && sensors.isEmpty) {
      return const Center(
        child: Text('Sin dispositivos', style: CceText.caption),
      );
    }

    return CustomScrollView(
      slivers: [
        // En "Toda la casa" no se muestran escenas (son por habitación).
        if (lights.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Luces'),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tileSize.maxTileExtent,
              mainAxisExtent: tileSize.tileHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final d = service.byId(lights[i].id) ?? lights[i];
                  return LightTile(
                    device: d,
                    service: service,
                    size: tileSize,
                    neo: true,
                  );
                },
              ),
              childCount: lights.length,
            ),
          ),
        ],
        // Clima: termostatos de toda la casa (faltaba esta sección acá).
        if (thermostats.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Clima'),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tileSize.maxTileExtent,
              mainAxisExtent: tileSize.sensorTileHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final d = service.byId(thermostats[i].id) ?? thermostats[i];
                  return ThermostatTile(
                    device: d,
                    service: service,
                    size: tileSize,
                    neo: true,
                    // Tablet: abre el termostato inline (igual que TV/JBL). El
                    // State padre resuelve la selección vía onOpenThermostat.
                    onOpen: onOpenThermostat == null
                        ? null
                        : () => onOpenThermostat!(d.id),
                  );
                },
              ),
              childCount: thermostats.length,
            ),
          ),
        ],
        if (sensors.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Sensores'),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tileSize.maxTileExtent,
              mainAxisExtent: tileSize.sensorTileHeight,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final d = service.byId(sensors[i].id) ?? sensors[i];
                  return SensorTile(
                    device: d,
                    service: service,
                    size: tileSize,
                    neo: true,
                  );
                },
              ),
              childCount: sensors.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
