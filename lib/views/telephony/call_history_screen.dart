import 'package:flutter/material.dart';

import '../../models/phone_call.dart';
import '../../services/telephony_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';

/// Historial de llamadas, en su propia pantalla.
///
/// Salió del cuerpo de [TelephonyScreen] cuando el dial pad pasó a ser el foco
/// (issue #10): el historial es a lo que se entra, no lo que se ve al abrir el
/// teléfono. Entrar acá ES ver las perdidas, así que el contador de no vistas
/// se pone en cero al montar.
///
/// Al tocar una llamada VUELVE con el número cargado en el teclado en vez de
/// discar: un tap suelto en una lista no puede gastar una llamada.
class CallHistoryScreen extends StatefulWidget {
  final TelephonyService telephony;

  const CallHistoryScreen({super.key, required this.telephony});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.telephony.markMissedSeen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.telephony,
          builder: (context, _) {
            return Column(
              children: [
                _header(),
                Expanded(child: _list()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CceSpace.sm,
        CceSpace.sm,
        CceSpace.lg,
        CceSpace.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: CceColors.textSecondary,
          ),
          Expanded(child: Text('Historial', style: CceText.title)),
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

  Widget _list() {
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
    final number = c.number.trim();

    return CceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Sin número (entrante sin caller ID) no hay nada que devolver.
      onTap: number.isEmpty
          ? null
          : () => Navigator.of(context).pop(number),
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
              Text(formatCallWhen(c.startedAt), style: CceText.caption),
              if (c.duration.inSeconds > 0)
                Text(
                  formatCallDuration(c.duration),
                  style: CceText.caption.copyWith(color: CceColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fecha corta: hora si es de hoy, día y hora si no.
String formatCallWhen(DateTime when) {
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

/// "m:ss" para duraciones cortas, "h:mm:ss" cuando la llamada pasó la hora.
String formatCallDuration(Duration d) {
  final s = d.inSeconds % 60;
  final m = d.inMinutes % 60;
  if (d.inHours > 0) {
    return '${d.inHours}:${m.toString().padLeft(2, '0')}'
        ':${s.toString().padLeft(2, '0')}';
  }
  return '${d.inMinutes}:${s.toString().padLeft(2, '0')}';
}
