import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/phone_sms.dart';
import '../../services/telephony_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import 'call_history_screen.dart' show formatCallWhen;
import 'phone_surface.dart';

/// Los SMS que llegaron a la línea de la casa (CCE#23), en su propia
/// pantalla, con el patrón de [CallHistoryScreen]: se entra desde el header
/// del teléfono, entrar ES ver los mensajes (el contador de no leídos se pone
/// en cero al montar), y las filas son [PhoneSurface] como todo en el
/// teléfono.
///
/// Un SMS acá es casi siempre un código de verificación: tocar la fila COPIA
/// el texto al portapapeles, que es lo que uno quiere hacer con un código.
/// No disca: el remitente de un SMS suele ser un servicio, no alguien a
/// quien llamar.
///
/// [focusId] resalta un mensaje: es lo que abre la push al tocarla.
class SmsScreen extends StatefulWidget {
  final TelephonyService telephony;
  final String? focusId;

  const SmsScreen({super.key, required this.telephony, this.focusId});

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  @override
  void initState() {
    super.initState();
    widget.telephony.markSmsSeen();
    // Lo que abrió la push puede no estar todavía en la lista (la app estaba
    // cerrada): se pide de nuevo, sin bloquear la pantalla.
    if (widget.focusId != null &&
        !widget.telephony.sms.any((s) => s.id == widget.focusId)) {
      widget.telephony.refresh();
    }
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
    final sms = widget.telephony.sms;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CceSpace.sm, CceSpace.sm, CceSpace.sm, 0),
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
                Text('Mensajes', style: CceText.title),
                Text(
                  sms.isEmpty
                      ? 'Sin mensajes'
                      : sms.length == 1
                          ? '1 mensaje'
                          : '${sms.length} mensajes',
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

  Widget _list() {
    final sms = widget.telephony.sms;
    if (sms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CceSpace.xl),
          child: Text(
            widget.telephony.error != null
                ? 'No se pudieron leer los mensajes.'
                : 'Todavía no hay mensajes.',
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
        padding: const EdgeInsets.fromLTRB(
          CceSpace.lg,
          CceSpace.md,
          CceSpace.lg,
          CceSpace.xl,
        ),
        itemCount: sms.length,
        separatorBuilder: (_, _) => const SizedBox(height: CceSpace.sm),
        itemBuilder: (context, i) => _smsRow(sms[i]),
      ),
    );
  }

  Widget _smsRow(PhoneSms m) {
    final focused = widget.focusId != null && m.id == widget.focusId;
    final name = m.displayName;
    final number = m.number.trim();
    final showNumber =
        m.contactName != null && m.contactName!.trim().isNotEmpty && number.isNotEmpty;

    return PhoneSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      tint: focused ? CceColors.accent : null,
      onTap: () => _copy(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CceIcon(CceIcons.sms, size: 18, color: CceColors.textTertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: CceText.label.copyWith(
                    fontSize: 15,
                    color: CceColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatCallWhen(m.when),
                style: CceText.caption.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (showNumber) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(number, style: CceText.caption),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              m.text,
              style: CceText.label.copyWith(
                fontSize: 15,
                height: 1.35,
                color: CceColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(PhoneSms m) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensaje copiado')),
    );
  }
}
