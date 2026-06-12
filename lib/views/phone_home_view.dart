import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_icons.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'history_screen.dart';
import 'rooms_list_screen.dart';
import 'soundbar/soundbar_screen.dart';

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
  late final JblService _jbl;
  int _tab = 0;
  final _casaNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
    _jbl = JblService(config: widget.config);
  }

  @override
  void dispose() {
    _jbl.dispose();
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
            SoundbarScreen(service: _jbl),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            if (i == _tab && i == 0) {
              _casaNavKey.currentState?.popUntil((r) => r.isFirst);
            }
            // El shell posee el ciclo de polling del soundbar: solo pollea
            // mientras Sonido (idx 4) es el destino activo.
            final wasSound = _tab == 4;
            final isSound = i == 4;
            if (isSound && !wasSound) _jbl.startPolling();
            if (!isSound && wasSound) _jbl.stopPolling();
            setState(() => _tab = i);
          },
          // El tinte selected/unselected lo provee el IconTheme del tema —
          // nunca hardcodear color en estos CceIcon.
          destinations: const [
            NavigationDestination(
              icon: CceIcon(CceIcons.allHouse, size: 26),
              label: 'Casa',
            ),
            NavigationDestination(
              icon: CceIcon(CceIcons.history, size: 26),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: CceIcon(CceIcons.agent, size: 26),
              label: 'Agente',
            ),
            NavigationDestination(
              icon: CceIcon(CceIcons.alarmShield, size: 26),
              label: 'Alarma',
            ),
            NavigationDestination(
              icon: CceIcon(CceIcons.speaker, size: 26),
              label: 'Sonido',
            ),
          ],
        ),
      ),
    );
  }
}
