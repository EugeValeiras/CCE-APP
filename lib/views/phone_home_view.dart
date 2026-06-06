import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/socket_service.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'history_screen.dart';
import 'rooms_list_screen.dart';

/// iPhone root: "Casa" tab (rooms → room detail with color control) + "Alarma" tab.
class PhoneHomeView extends StatefulWidget {
  final ServerConfig config;
  const PhoneHomeView({super.key, required this.config});

  @override
  State<PhoneHomeView> createState() => _PhoneHomeViewState();
}

class _PhoneHomeViewState extends State<PhoneHomeView> {
  late SocketService _socket;
  late DevicesService _devices;
  int _tab = 0;
  final _casaNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
  }

  @override
  void dispose() {
    _devices.dispose();
    _socket.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    // If we're in Casa tab and the nested navigator can pop, do that instead.
    if (_tab == 0) {
      final nav = _casaNavKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1D38),
        body: IndexedStack(
          index: _tab,
          children: [
            Navigator(
              key: _casaNavKey,
              onGenerateRoute: (routeSettings) {
                return MaterialPageRoute(
                  settings: routeSettings,
                  builder: (_) => RoomsListScreen(service: _devices),
                );
              },
            ),
            HistoryScreen(config: widget.config, devices: _devices),
            ChatScreen(config: widget.config),
            AlarmView(initialConfig: widget.config),
          ],
        ),
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
      ),
    );
  }
}
