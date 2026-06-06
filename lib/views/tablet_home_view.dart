import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import '../services/ui_settings_service.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'floor_plan_tab.dart';
import 'history_screen.dart';
import 'rooms_list_screen.dart';
import 'settings_view.dart';

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
  final _casaNavKey = GlobalKey<NavigatorState>();

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

  IconData _sizeIcon(TileSize s) {
    switch (s) {
      case TileSize.small: return Icons.view_comfy;
      case TileSize.medium: return Icons.grid_view;
      case TileSize.large: return Icons.view_module;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ui,
      builder: (context, _) {
        final tileSize = _ui.tileSize;
        final tabs = <Widget>[
          Navigator(
            key: _casaNavKey,
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => RoomsListScreen(service: _devices),
            ),
          ),
          FloorPlanTab(service: _devices, tileSize: tileSize),
          HistoryScreen(config: widget.config, devices: _devices),
          ChatScreen(config: widget.config),
          AlarmView(initialConfig: widget.config),
        ];

        // AppBar belongs to tab 1 (Planos). Casa (0), Historial (2), Agente (3)
        // and Alarma (4) manage their own app bars.
        return Scaffold(
          backgroundColor: const Color(0xFF0B1D38),
          appBar: _tab == 1
              ? AppBar(
                  backgroundColor: const Color(0xFF152D54),
                  title: const Text('Planos', style: TextStyle(color: Colors.white)),
                  actions: [
                    Tooltip(
                      message: 'Tamaño: ${tileSize.label}',
                      child: IconButton(
                        icon: Icon(_sizeIcon(tileSize), color: Colors.white70),
                        onPressed: _ui.cycle,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: _devices.refresh,
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white54),
                      onPressed: _openSettings,
                    ),
                  ],
                )
              : null,
          body: IndexedStack(index: _tab, children: tabs),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF152D54),
            indicatorColor: const Color(0xFF0F3460),
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              if (i == _tab && i == 0) {
                _casaNavKey.currentState?.popUntil((r) => r.isFirst);
              }
              setState(() => _tab = i);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.home, color: Colors.white),
                label: 'Casa',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.map, color: Colors.white),
                label: 'Planos',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.history, color: Colors.white),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.smart_toy, color: Colors.white),
                label: 'Agente',
              ),
              NavigationDestination(
                icon: Icon(Icons.shield_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.shield, color: Colors.white),
                label: 'Alarma',
              ),
            ],
          ),
        );
      },
    );
  }
}
