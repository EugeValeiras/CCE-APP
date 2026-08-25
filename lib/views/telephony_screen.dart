import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/phone_call.dart';
import '../services/devices_service.dart';
import '../services/telephony_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';

/// Pantalla del teléfono 4G (HAT SIM7600G-H).
///
/// La app NO DISCA — decisión de producto: el dial pad vive sólo en el
/// dashboard, donde además está el parlante. Acá se ve el estado de la línea y
/// el historial, con las perdidas destacadas.
///
/// Se llama `TelephonyScreen` y no `PhoneScreen` (como decía el plan) porque en
/// este repo `phone_*` ya significa "layout de celular" (phone_home_view.dart):
/// un `phone_screen.dart` de telefonía al lado sería una trampa para el próximo
/// que abra la carpeta.
class TelephonyScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  final TelephonyService telephony;

  const TelephonyScreen({
    super.key,
    required this.device,
    required this.service,
    required this.telephony,
  });

  @override
  State<TelephonyScreen> createState() => _TelephonyScreenState();
}

class _TelephonyScreenState extends State<TelephonyScreen> {
  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  @override
  void initState() {
    super.initState();
    // Entrar acá ES ver las perdidas.
    widget.telephony.markMissedSeen();
    widget.telephony.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([widget.service, widget.telephony]),
          builder: (context, _) {
            final d = _device;
            final incoming = widget.telephony.incoming;
            return Column(
              children: [
                _header(d),
                if (incoming != null) _incomingBanner(incoming),
                if (d.phoneInCall && incoming == null) _activeCall(d),
                _lineCard(d),
                Expanded(child: _history()),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(Device d) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.sm, CceSpace.sm, CceSpace.lg, CceSpace.md),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: CceColors.textSecondary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.service.displayName(d),
                  style: CceText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.telephony.status.ownNumber ?? 'Sin número configurado',
                  style: CceText.caption,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => widget.telephony.refresh(),
            icon: const Icon(Icons.refresh, size: 20),
            color: CceColors.textSecondary,
            tooltip: 'Actualizar',
          ),
        ],
      ),
    );
  }

  // ── Llamada entrante y en curso ───────────────────────────────────────────

  /// Aviso de entrante. La app no atiende (no tiene el audio: el parlante está
  /// en el HAT), así que esto informa quién llama — atender es del dashboard.
  Widget _incomingBanner(Map<String, dynamic> incoming) {
    final name = (incoming['contactName'] ?? '').toString();
    final number = (incoming['number'] ?? '').toString();
    final who = name.isNotEmpty ? name : (number.isEmpty ? 'Número desconocido' : number);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: CceSpace.lg, vertical: CceSpace.xs),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const CceIcon(CceIcons.phoneIncoming, size: 22, color: CceColors.ok),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who, style: CceText.title.copyWith(fontSize: 15)),
                  Text(
                    name.isNotEmpty ? number : 'Llamada entrante',
                    style: CceText.caption,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.telephony.dismissIncoming,
              child: const Text('Ocultar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeCall(Device d) {
    final s = d.state;
    final who = s.peerName ?? s.peerNumber ?? 'Sin identificar';
    final label = switch (s.callState) {
      'dialing' => 'Marcando',
      'ringing' => 'Llamada entrante',
      'active' => 'En curso',
      _ => 'Llamada',
    };
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: CceSpace.lg, vertical: CceSpace.xs),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CceIcon(
              s.callDirection == 'in' ? CceIcons.phoneIncoming : CceIcons.phoneOutgoing,
              size: 22,
              color: CceColors.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who, style: CceText.title.copyWith(fontSize: 15)),
                  Text(label, style: CceText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Estado de la línea ────────────────────────────────────────────────────

  /// Registrado y OPERATIVO son cosas distintas: una línea sin habilitar se
  /// registra igual y muestra operador y señal impecables sin poder cursar
  /// nada. Por eso el chip de línea va aparte del operador.
  Widget _lineCard(Device d) {
    final st = widget.telephony.status;
    final s = d.state;
    final bars = s.signalBars ?? st.signalBars;
    final lineActive = s.lineActive ?? st.lineActive;

    final (String lineText, Color lineColor) = switch (lineActive) {
      'active' => ('Línea activa', CceColors.ok),
      'inactive' => ('Línea inactiva', CceColors.danger),
      _ => ('Estado de línea sin verificar', CceColors.textTertiary),
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.xs, CceSpace.lg, CceSpace.md),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CceIcon(CceIcons.phone, size: 20, color: CceColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.networkOperator ?? st.operator ?? 'Sin operador',
                    style: CceText.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _bars(bars),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: lineColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$lineText · ${s.networkTech ?? st.tech ?? 'sin red'}',
                    style: CceText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (!st.enabled || !st.online) ...[
              const SizedBox(height: 6),
              Text(
                !st.enabled
                    ? 'La telefonía está deshabilitada en el servidor.'
                    : 'El módem no responde. Se reconecta solo cuando vuelva.',
                style: CceText.caption.copyWith(color: CceColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bars(int bars) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++) ...[
          Container(
            width: 3,
            height: 4.0 + i * 2.4,
            decoration: BoxDecoration(
              color: i <= bars ? CceColors.accent : CceColors.strokeStrong,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          if (i < 5) const SizedBox(width: 2),
        ],
      ],
    );
  }

  // ── Historial ─────────────────────────────────────────────────────────────

  Widget _history() {
    final calls = widget.telephony.calls;
    if (calls.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(CceSpace.xl),
          child: Text(
            widget.telephony.error != null
                ? 'No se pudo leer el historial.'
                : 'Todavía no hay llamadas.',
            style: CceText.caption,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => widget.telephony.refresh(),
      color: CceColors.accent,
      backgroundColor: CceColors.surface,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(CceSpace.lg, 0, CceSpace.lg, CceSpace.xl),
        itemCount: calls.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) => _callRow(calls[i]),
      ),
    );
  }

  Widget _callRow(PhoneCall c) {
    final missed = c.isMissed;
    final icon = missed
        ? CceIcons.phoneMissed
        : (c.incoming ? CceIcons.phoneIncoming : CceIcons.phoneOutgoing);
    final color = missed ? CceColors.danger : CceColors.textTertiary;

    return CceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CceIcon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.displayName,
                  style: CceText.label.copyWith(
                    // Las perdidas se leen distinto del resto: son el aviso.
                    color: missed ? CceColors.textPrimary : CceColors.textSecondary,
                    fontWeight: missed ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(c.resultLabel, style: CceText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatWhen(c.startedAt), style: CceText.caption),
              if (c.duration.inSeconds > 0)
                Text(
                  _formatDuration(c.duration),
                  style: CceText.caption.copyWith(color: CceColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fecha corta: hora si es de hoy, día y hora si no.
  static String _formatWhen(DateTime when) {
    final now = DateTime.now();
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final sameDay =
        when.year == now.year && when.month == now.month && when.day == now.day;
    if (sameDay) return '$hh:$mm';
    final dd = when.day.toString().padLeft(2, '0');
    final mo = when.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
