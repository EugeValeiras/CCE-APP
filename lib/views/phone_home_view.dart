import 'dart:async';

import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/push_channel.dart';
import '../services/tv_service.dart';
import '../services/telephony_service.dart';
import '../services/socket_service.dart';
import '../theme/cce_tokens.dart';
import 'agent/chat_screen.dart';
import 'alarm_view.dart';
import 'automations/automations_view.dart';
import 'history_screen.dart';
import 'in_app_notification.dart';
import 'rooms_list_screen.dart';
import 'telephony/sms_screen.dart';

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
  late final TvService _tv;
  late final TelephonyService _telephony;

  StreamSubscription<Map<String, dynamic>>? _pushTapSub;
  StreamSubscription<Map<String, dynamic>>? _pushReceivedSub;

  @override
  void initState() {
    super.initState();
    _socket = SocketService();
    _socket.connect(widget.config);
    _devices = DevicesService(config: widget.config, socket: _socket);
    _devices.refresh();
    _jbl = JblService(config: widget.config, socket: _socket);
    _tv = TvService(config: widget.config, socket: _socket);
    // El home muestra las cards del soundbar y el TV y está siempre vivo →
    // seed + suscripción al socket una sola vez (F13: sin timer; dev_jbl/dev_tv
    // empujan device:state-changed) para que las cards se mantengan frescas.
    _telephony = TelephonyService(
      config: widget.config,
      socket: _socket,
      // Si el placeholder de "marcando" expira sin estado, se re-lee dev_phone
      // donde la pantalla lo mira: DevicesService, no el seed del teléfono.
      reloadPhoneDevice: () => _devices.refreshDevice(kPhoneDeviceId),
    );
    _jbl.startPolling();
    _tv.startPolling();
    // El teléfono arranca con el shell y NO con su pantalla: el contador de
    // perdidas de la card tiene que estar bien aunque nunca se entre, y una
    // llamada entrante mientras mirás las luces igual tiene que llegar.
    _telephony.start();

    // La push de un SMS (CCE#23): tocarla abre el mensaje, y si llega con la
    // app abierta se muestra como aviso in-app (iOS suprime el banner del
    // sistema en primer plano). Vive en el shell y no en AlarmView porque
    // el shell es lo único que está siempre montado.
    final push = PushChannel.instance;
    _pushTapSub = push.onPushTapped.listen(_onPushTapped);
    _pushReceivedSub = push.onPushReceived.listen(_onPushReceived);
    // Arranque en frío desde una push: el toque llegó antes que esta pantalla.
    final pending = push.takePendingTap();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPushTapped(pending));
    }
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    _pushReceivedSub?.cancel();
    _jbl.dispose();
    _tv.dispose();
    _telephony.dispose();
    _devices.dispose();
    _socket.dispose();
    super.dispose();
  }

  bool _isSmsPush(Map<String, dynamic> data) => data['kind'] == 'phone-sms';

  void _onPushTapped(Map<String, dynamic> data) {
    if (!mounted || !_isSmsPush(data)) return;
    _openSms(focusId: data['smsId']?.toString());
  }

  void _onPushReceived(Map<String, dynamic> data) {
    if (!mounted || !_isSmsPush(data)) return;
    final smsId = data['smsId']?.toString();
    InAppNotification.show(
      context,
      title: (data['title'] ?? 'SMS').toString(),
      body: (data['body'] ?? '').toString(),
      icon: Icons.sms_outlined,
      iconColor: CceColors.accent,
      duration: const Duration(seconds: 6),
      onTap: () => _openSms(focusId: smsId),
    );
  }

  void _openSms({String? focusId}) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SmsScreen(telephony: _telephony, focusId: focusId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return RoomsListScreen(
      service: _devices,
      jbl: _jbl,
      tv: _tv,
      telephony: _telephony,
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
      // Automatizaciones en el TELÉFONO: la misma AutomationsView de la
      // tablet (lista + editor + crear). Trae su propio Scaffold; volver =
      // swipe iOS (canon: sin AppBar), igual que AlarmView.
      onOpenAutomations: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => AutomationsView(devices: _devices, config: widget.config),
      )),
    );
  }
}
