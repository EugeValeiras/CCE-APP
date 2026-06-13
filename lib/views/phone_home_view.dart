import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/socket_service.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'history_screen.dart';
import 'rooms_list_screen.dart';

/// iPhone root: "Casa" (RoomsListScreen) como única pantalla raíz. Historial,
/// Agente y Alarma se abren desde el header de la home, pusheados al Navigator
/// raíz de MaterialApp (swipe-back nativo iOS). Sonido se abre desde la
/// SoundbarHomeCard. Sin bottom navbar / IndexedStack / navegador anidado.
///
/// Nota de comportamiento (cambio conocido vs. el shell anterior con
/// IndexedStack): ChatScreen ya no se mantiene vivo en segundo plano. Cada vez
/// que se abre Agente desde el header se construye una ChatScreen nueva (arma su
/// propio ChatService) → la conversación en memoria se reinicia entre aperturas.
/// Historial re-suscribe limpio al socket compartido (vive en _devices, que el
/// shell mantiene vivo) y solo pierde estado de filtros/scroll, lo cual es
/// benigno para una pantalla de log.
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

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
    _jbl = JblService(config: widget.config);
    // El home muestra la card del soundbar y está siempre vivo → arrancamos el
    // polling una sola vez para que la card se mantenga fresca toda la sesión.
    _jbl.startPolling();
  }

  @override
  void dispose() {
    _jbl.dispose();
    _devices.dispose();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoomsListScreen(
      service: _devices,
      jbl: _jbl,
      onOpenHistory: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => HistoryScreen(
          config: widget.config,
          devices: _devices,
          neo: true,
        ),
      )),
      onOpenAgent: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => ChatScreen(config: widget.config),
      )),
      onOpenAlarm: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => AlarmView(initialConfig: widget.config, neo: true),
      )),
    );
  }
}
