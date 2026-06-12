import 'package:flutter/material.dart';
import '../models/room_ref.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../widgets/temperature_summary_card.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'floor_plan_tab.dart';
import 'history_screen.dart';
import 'settings_view.dart';
import 'tablet/room_panel.dart';
import 'tablet/rooms_sidebar.dart';

/// Shell tablet estilo Hue: NavigationRail fino a la izquierda (Casa,
/// Historial, Agente, Alarma + ajustes al pie) y la tab Casa como split view
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
  final UiSettingsService _ui = UiSettingsService();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
    _ui.load();
  }

  @override
  void dispose() {
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
          _CasaSplit(devices: _devices, ui: _ui),
          HistoryScreen(config: widget.config, devices: _devices),
          ChatScreen(config: widget.config),
          AlarmView(initialConfig: widget.config),
        ];

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  minWidth: 72,
                  selectedIndex: _tab,
                  groupAlignment: -1,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationRailDestination(
                      icon: CceIcon(CceIcons.allHouse),
                      label: Text('Casa'),
                    ),
                    NavigationRailDestination(
                      icon: CceIcon(CceIcons.history),
                      label: Text('Historial'),
                    ),
                    NavigationRailDestination(
                      icon: CceIcon(CceIcons.agent),
                      label: Text('Agente'),
                    ),
                    NavigationRailDestination(
                      icon: CceIcon(CceIcons.alarmShield),
                      label: Text('Alarma'),
                    ),
                  ],
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: IconButton(
                          tooltip: 'Ajustes',
                          icon: const CceIcon(CceIcons.settings),
                          onPressed: _openSettings,
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: IndexedStack(index: _tab, children: tabs),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Split view de la tab Casa: sidebar de habitaciones (320 px) + panel
/// derecho ("Toda la casa" con el plano completo, o RoomPanel de la sala
/// seleccionada).
class _CasaSplit extends StatefulWidget {
  const _CasaSplit({required this.devices, required this.ui});

  final DevicesService devices;
  final UiSettingsService ui;

  @override
  State<_CasaSplit> createState() => _CasaSplitState();
}

class _CasaSplitState extends State<_CasaSplit> {
  String? _selectedRoomId; // null = Toda la casa

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

        return Row(
          children: [
            SizedBox(
              width: 320,
              child: RoomsSidebar(
                service: widget.devices,
                selectedRoomId: _selectedRoomId,
                onSelect: (id) => setState(() => _selectedRoomId = id),
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: room == null
                  ? _buildAllHouse()
                  : RoomPanel(
                      service: widget.devices,
                      room: room,
                      tileSize: widget.ui.tileSize,
                      onCycleTileSize: widget.ui.cycle,
                      onRefresh: widget.devices.refresh,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAllHouse() {
    final tileSize = widget.ui.tileSize;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mi casa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.display,
                ),
              ),
              Tooltip(
                message: 'Tamaño: ${tileSize.label}',
                child: IconButton(
                  icon: Icon(_sizeIcon(tileSize)),
                  onPressed: widget.ui.cycle,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: widget.devices.refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TemperatureSummaryCard(service: widget.devices),
          Expanded(
            child: FloorPlanPanel(
              service: widget.devices,
              dotSize: tileSize.floorPlanDotSize,
            ),
          ),
        ],
      ),
    );
  }
}
