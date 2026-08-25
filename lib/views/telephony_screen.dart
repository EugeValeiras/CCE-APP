import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/phone_call.dart';
import '../services/devices_service.dart';
import '../services/telephony_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../utils/dial_number.dart';
import 'telephony/audio_notice.dart';
import 'telephony/call_history_screen.dart';
import 'telephony/contacts_sheet.dart';
import 'telephony/dial_actions.dart';
import 'telephony/dial_display.dart';
import 'telephony/dial_pad.dart';

/// Pantalla del teléfono 4G (HAT SIM7600G-H).
///
/// Es, ante todo, UN TECLADO PARA DISCAR (issue #10, que reemplaza la decisión
/// de #4 de no discar desde la app). El historial pasó detrás de un botón:
/// [CallHistoryScreen].
///
/// LO QUE ESTA PANTALLA TIENE QUE DECIR SIEMPRE: **la app no lleva audio**. La
/// llamada sale de verdad y el destino suena, pero la voz va al jack del HAT o
/// al navegador del dashboard, nunca al celular. Un usuario que disca, no
/// escucha nada y no sabe por qué, concluye que la app está rota — por eso el
/// aviso está a la vista en reposo y en grande durante la llamada, y no en
/// letra chica.
///
/// Se llama `TelephonyScreen` y no `PhoneScreen` (como decía el plan) porque en
/// este repo `phone_*` ya significa "layout de celular" (phone_home_view.dart):
/// un `phone_screen.dart` de telefonía al lado sería una trampa para el próximo
/// que abra la carpeta. Misma razón para la carpeta `views/telephony/`.
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

  final TextEditingController _number = TextEditingController();
  final FocusNode _numberFocus = FocusNode();

  /// Tonos mandados en la llamada en curso. Sin esto el teclado DTMF no da
  /// ningún acuse: el menú de voz que responde está sonando en la casa.
  String _dtmfSent = '';

  /// Sólo mueve el cronómetro de la llamada. NO es polling: no toca la red.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.telephony.refresh();
    // Precargar la libreta para que el sheet abra lleno, no vacío y parpadeando.
    widget.telephony.loadContacts();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_device.phoneInCall) {
        setState(() {});
      } else if (_dtmfSent.isNotEmpty) {
        // Los tonos eran de la llamada que terminó. Si no se limpian acá,
        // reaparecen en la próxima (por ejemplo una entrante que atendieron
        // desde el dashboard) como si se hubieran mandado a ESA.
        setState(() => _dtmfSent = '');
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _number.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      // El teclado del sistema (si alguien tocó el campo para pegar a mano) no
      // tiene que empujar el dial pad: se lo cierra con un toque afuera.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([widget.service, widget.telephony]),
          builder: (context, _) {
            final d = _device;
            final t = widget.telephony;
            final s = d.state;
            final incoming = t.incoming;

            // Una entrante SONANDO no es una llamada en curso: no se cuelga, se
            // atiende o se rechaza. Llega por dos vías (el banner del socket y
            // el estado del device) y basta con cualquiera de las dos.
            final ringingIn = incoming != null ||
                (s.callState == 'ringing' && s.callDirection == 'in');
            final live = (d.phoneInCall && !ringingIn) || t.dialingNumber != null;

            return Column(
              children: [
                _header(d, t),
                _lineStrip(d, t),
                if (t.actionError != null) _errorBanner(t.actionError!),
                if (ringingIn)
                  _incomingCard(d, incoming)
                else if (live)
                  _activeCall(d, t)
                else
                  _audioNotice(t.status),
                _display(live: live, enabled: !ringingIn),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: CceSpace.lg,
                      vertical: CceSpace.sm,
                    ),
                    child: DialPad(
                      enabled: !ringingIn,
                      // Un '+' no es un tono DTMF: en llamada el 0 es sólo 0.
                      plusOnZero: !live,
                      onKey: (key) => _onKey(key, live: live),
                    ),
                  ),
                ),
                _actions(d, t, ringingIn: ringingIn, live: live),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Teclado ───────────────────────────────────────────────────────────────

  void _onKey(String key, {required bool live}) {
    // Si el campo tenía el foco (alguien lo tocó para pegar a mano), el teclado
    // del sistema estorba: el input de acá es el dial pad.
    _numberFocus.unfocus();
    if (live) {
      _sendTone(key);
      return;
    }
    final text = _number.text + key;
    _number.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _sendTone(String digit) async {
    setState(() => _dtmfSent += digit);
    final ok = await widget.telephony.sendDtmf(digit);
    if (!ok && mounted) {
      // El tono no salió: sacarlo del acuse, o la pantalla estaría mintiendo
      // sobre lo que recibió el menú de voz del otro lado.
      setState(() {
        if (_dtmfSent.isNotEmpty) {
          _dtmfSent = _dtmfSent.substring(0, _dtmfSent.length - 1);
        }
      });
    }
  }

  void _backspace() {
    final text = _number.text;
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    final next = text.substring(0, text.length - 1);
    _number.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _clearNumber() {
    if (_number.text.isEmpty) return;
    HapticFeedback.mediumImpact();
    _number.clear();
    setState(() {});
  }

  void _setNumber(String value) {
    final clean = sanitizeDialInput(value);
    _number.value = TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
    setState(() {});
  }

  /// Pegar un número copiado de otra app. Existe como BOTÓN además del menú
  /// contextual del campo porque el long-press sobre un número que se está
  /// escribiendo no es un gesto que nadie descubra solo.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clean = sanitizeDialInput(data?.text ?? '');
    if (!mounted) return;
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay un número en el portapapeles.')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    _setNumber(clean);
  }

  // ── Comandos ──────────────────────────────────────────────────────────────

  Future<void> _call({String? number, String? contactId}) async {
    HapticFeedback.mediumImpact();
    _numberFocus.unfocus();
    setState(() => _dtmfSent = '');
    await widget.telephony.call(number: number, contactId: contactId);
    // No se hace polling: el estado real llega por `device:state-changed`.
  }

  Future<void> _hangup() async {
    HapticFeedback.mediumImpact();
    await widget.telephony.hangup();
  }

  Future<void> _answer() async {
    HapticFeedback.mediumImpact();
    setState(() => _dtmfSent = '');
    await widget.telephony.answer();
  }

  Future<void> _openHistory() async {
    final number = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CallHistoryScreen(telephony: widget.telephony),
      ),
    );
    if (number != null && number.isNotEmpty) _setNumber(number);
  }

  Future<void> _openContacts() async {
    final pick = await showContactsSheet(context, widget.telephony);
    if (pick == null || !mounted) return;
    if (pick.callNow) {
      await _call(contactId: pick.contact.id);
    } else {
      _setNumber(pick.contact.number);
    }
  }

  // ── Header y estado de la línea ───────────────────────────────────────────

  Widget _header(Device d, TelephonyService t) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.sm, CceSpace.sm, CceSpace.sm, 0),
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
                  t.status.ownNumber ?? 'Sin número configurado',
                  style: CceText.caption,
                ),
              ],
            ),
          ),
          _historyButton(t.unseenMissed),
          IconButton(
            onPressed: () => t.refresh(),
            icon: const Icon(Icons.refresh, size: 20),
            color: CceColors.textSecondary,
            tooltip: 'Actualizar',
          ),
        ],
      ),
    );
  }

  /// El historial detrás de un botón, con el contador de perdidas no vistas
  /// encima: dejó de ser el cuerpo de la pantalla, pero una perdida sigue
  /// siendo el aviso de último recurso de la casa y tiene que verse sin entrar.
  Widget _historyButton(int missed) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _openHistory,
          icon: const CceIcon(
            CceIcons.history,
            size: 20,
            color: CceColors.textSecondary,
          ),
          tooltip: 'Historial de llamadas',
        ),
        if (missed > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: CceColors.danger,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  missed > 99 ? '99+' : '$missed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: CceColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Estado de la línea, compacto: dejó de ser una card grande porque el lugar
  /// principal es del teclado.
  ///
  /// Registrado y OPERATIVO son cosas distintas: una línea sin habilitar se
  /// registra igual y muestra operador y señal impecables sin poder cursar
  /// nada. Por eso el estado de la línea se dice aparte del operador.
  Widget _lineStrip(Device d, TelephonyService t) {
    final st = t.status;
    final s = d.state;
    final bars = s.signalBars ?? st.signalBars;
    final lineActive = s.lineActive ?? st.lineActive;

    final (String lineText, Color lineColor) = switch (lineActive) {
      'active' => ('Línea activa', CceColors.ok),
      'inactive' => ('Línea inactiva', CceColors.danger),
      _ => ('Línea sin verificar', CceColors.textTertiary),
    };

    final detail = [
      s.networkTech ?? st.tech ?? 'sin red',
      lineText,
      if (st.balance != null) 'Saldo ${st.balance}',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.sm, CceSpace.lg, 0),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: lineColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.networkOperator ?? st.operator ?? 'Sin operador',
                        style: CceText.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        detail,
                        style: CceText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _bars(bars),
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
            ] else if (st.rateLimitNear) ...[
              const SizedBox(height: 6),
              // El tope del backend existe y corta: mejor verlo venir que
              // descubrirlo con un rechazo.
              Text(
                '${st.rateLimitLabel}. Al llegar al tope el servidor no deja '
                'llamar por un rato.',
                style: CceText.caption.copyWith(color: CceColors.accent),
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

  // ── El aviso del audio ────────────────────────────────────────────────────

  /// En reposo: qué esperar ANTES de discar. Va acá arriba y no en un tooltip
  /// porque es la diferencia entre "la app anda" y "la app está rota" para
  /// quien disca por primera vez desde el celular.
  Widget _audioNotice(PhoneStatus st) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.sm, CceSpace.lg, 0),
      child: AudioRouteNotice(status: st),
    );
  }

  // ── Llamada entrante y en curso ───────────────────────────────────────────

  Widget _incomingCard(Device d, Map<String, dynamic>? incoming) {
    final s = d.state;
    final name = (incoming?['contactName'] ?? s.peerName ?? '').toString();
    final number = (incoming?['number'] ?? s.peerNumber ?? '').toString();
    final who = name.isNotEmpty
        ? name
        : (number.isEmpty ? 'Número desconocido' : number);

    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.sm, CceSpace.lg, 0),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                const CceIcon(CceIcons.phoneIncoming,
                    size: 22, color: CceColors.ok),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who, style: CceText.title.copyWith(fontSize: 15)),
                      Text(
                        name.isNotEmpty && number.isNotEmpty
                            ? number
                            : 'Llamada entrante',
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
            const SizedBox(height: 8),
            const AudioRouteLine.forIncoming(),
          ],
        ),
      ),
    );
  }

  Widget _activeCall(Device d, TelephonyService t) {
    final s = d.state;
    final pending = t.dialingNumber;
    final who = s.peerName ?? s.peerNumber ?? pending ?? 'Sin identificar';
    final label = switch (s.callState) {
      'dialing' => 'Marcando…',
      'ringing' => s.callDirection == 'in' ? 'Llamada entrante' : 'Llamando…',
      'active' => 'En curso',
      // Todavía no llegó el estado del módem: el `ATD` puede tardar y quedarse
      // sin decir nada haría parecer que la app se colgó.
      _ => pending != null ? 'Marcando…' : 'Llamada',
    };

    final started = s.callStartedAt;
    final elapsed = started == null
        ? null
        : DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(started),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.sm, CceSpace.lg, 0),
      child: CceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                CceIcon(
                  s.callDirection == 'in'
                      ? CceIcons.phoneIncoming
                      : CceIcons.phoneOutgoing,
                  size: 22,
                  color: CceColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        who,
                        style: CceText.title.copyWith(fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(label, style: CceText.caption),
                    ],
                  ),
                ),
                if (elapsed != null && elapsed.inSeconds >= 0)
                  Text(
                    formatCallDuration(elapsed),
                    style: CceText.label.copyWith(
                      color: CceColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // EL aviso, mientras la llamada está viva y el usuario se pregunta
            // por qué no escucha nada.
            AudioRouteLine.forCall(t.status),
          ],
        ),
      ),
    );
  }

  /// El motivo REAL del rechazo, como lo redactó el backend ("hay una llamada
  /// en curso", "rate limit de llamadas por hora alcanzado"). Un genérico haría
  /// que el usuario reintente contra un límite que no va a ceder.
  Widget _errorBanner(String reason) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.sm, CceSpace.lg, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: CceColors.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: Border.all(color: CceColors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: CceColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                reason,
                style: CceText.caption.copyWith(color: CceColors.textPrimary),
              ),
            ),
            IconButton(
              onPressed: widget.telephony.clearActionError,
              icon: const Icon(Icons.close, size: 16),
              color: CceColors.textTertiary,
              visualDensity: VisualDensity.compact,
              tooltip: 'Cerrar',
            ),
          ],
        ),
      ),
    );
  }

  // ── Display del número / de los tonos ─────────────────────────────────────

  Widget _display({required bool live, required bool enabled}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(CceSpace.lg, CceSpace.md, CceSpace.lg, 0),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            // Contrapeso del botón de pegar, para que el número quede centrado.
            const SizedBox(width: 44),
            Expanded(
              child: live
                  ? _toneDisplay()
                  : DialNumberField(
                      controller: _number,
                      focusNode: _numberFocus,
                      enabled: enabled,
                      onChanged: (_) => setState(() {}),
                    ),
            ),
            SizedBox(
              width: 44,
              child: live
                  ? null
                  : IconButton(
                      onPressed: enabled ? _paste : null,
                      icon: const Icon(Icons.content_paste_rounded, size: 20),
                      color: CceColors.textTertiary,
                      tooltip: 'Pegar un número',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toneDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _dtmfSent.isEmpty ? 'Teclado de tonos' : _dtmfSent,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _dtmfSent.isEmpty ? 15 : 26,
            letterSpacing: 3,
            color: _dtmfSent.isEmpty
                ? CceColors.textTertiary
                : CceColors.textPrimary,
          ),
        ),
        Text(
          'Los tonos van a la llamada',
          style: CceText.caption.copyWith(color: CceColors.textMuted),
        ),
      ],
    );
  }

  // ── Botonera ──────────────────────────────────────────────────────────────

  Widget _actions(
    Device d,
    TelephonyService t, {
    required bool ringingIn,
    required bool live,
  }) {
    final Widget row;

    if (ringingIn) {
      row = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhoneRoundButton(
            icon: CceIcons.phone,
            rotate: true,
            color: CceColors.danger,
            label: 'Rechazar',
            onPressed: t.busy ? null : _hangup,
          ),
          const SizedBox(width: 40),
          PhoneRoundButton(
            icon: CceIcons.phone,
            color: CceColors.ok,
            label: 'Atender',
            onPressed: t.busy ? null : _answer,
          ),
        ],
      );
    } else if (live) {
      row = PhoneRoundButton(
        icon: CceIcons.phone,
        rotate: true,
        color: CceColors.danger,
        label: 'Colgar',
        onPressed: t.busy ? null : _hangup,
      );
    } else {
      row = DialActions(
        hasNumber: _number.text.isNotEmpty,
        canDial: isDialable(_number.text) && !t.busy,
        onContacts: _openContacts,
        onCall: () => _call(number: _number.text),
        onBackspace: _backspace,
        onClear: _clearNumber,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        CceSpace.lg,
        CceSpace.sm,
        CceSpace.lg,
        CceSpace.md,
      ),
      child: Center(child: row),
    );
  }
}
