import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/phone_call.dart';
import '../services/devices_service.dart';
import '../services/telephony_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../utils/dial_number.dart';
import 'telephony/audio_notice.dart';
import 'telephony/call_audio_panel.dart';
import 'telephony/call_confirm_sheet.dart';
import 'telephony/call_history_screen.dart';
import 'telephony/contacts_sheet.dart';
import 'telephony/dial_actions.dart';
import 'telephony/dial_display.dart';
import 'telephony/dial_pad.dart';
import 'telephony/line_status_chip.dart';
import 'telephony/phone_surface.dart';

/// Pantalla del teléfono 4G (HAT SIM7600G-H).
///
/// Es, ante todo, UN TECLADO PARA DISCAR (issue #10, que reemplaza la decisión
/// de #4 de no discar desde la app). El historial pasó detrás de un botón:
/// [CallHistoryScreen].
///
/// LO QUE ESTA PANTALLA TIENE QUE DECIR SIEMPRE QUE IMPORTA: **dónde se escucha
/// la voz**. Con el #12 el celular puede llevar el audio (`CallAudioPanel`),
/// pero mientras no lo tenga tomado sigue siendo cierto lo del #10 — la llamada
/// sale de verdad y el destino suena, pero la voz va al jack del HAT o al
/// navegador del dashboard. Un usuario que disca, no escucha nada y no sabe por
/// qué, concluye que la app está rota.
///
/// El #14 reordenó la pantalla alrededor del número discado. La mitad de
/// arriba se lee así, de arriba hacia abajo:
///
///  1. Header: nombre, número propio, historial (con las perdidas sin ver) y
///     refresh.
///  2. Un chip fino con el estado de la línea ([LineStatusChip]).
///  3. UN bloque de estado, según el momento:
///     - en reposo, el número que se está discando ([DialDisplay]), y debajo el
///       panel del audio SÓLO cuando el audio ya está acá, se está tomando, o
///       falló. Con el audio en la casa no hay ningún aviso al discar: se da
///       al tocar Llamar, en el sheet (CCE#16);
///     - con una entrante sonando, la card de la entrante;
///     - con una llamada viva, la card de la llamada — con el ruteo real de la
///       voz en sus dos direcciones y los controles del audio adentro.
///  4. El teclado, con el aire que liberan los bloques que ya no están.
///  5. La botonera.
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
          animation: Listenable.merge([
            widget.service,
            widget.telephony,
            // El audio del celular tiene su propio estado (niveles, altavoz,
            // desalojo) y cambia varias veces por segundo mientras hay llamada.
            widget.telephony.audio,
          ]),
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
                _block(LineStatusChip(status: t.status, state: s)),
                if (t.actionError != null) _block(_errorBanner(t.actionError!)),
                if (ringingIn)
                  _block(_incomingCard(d, incoming, t))
                else if (live)
                  _block(_activeCall(d, t))
                else ...[
                  _block(
                    DialDisplay(
                      controller: _number,
                      focusNode: _numberFocus,
                      enabled: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // El teclado se corre suave cuando el aviso entra o sale, en
                  // vez de saltar al primer dígito.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: switch (_idleAudioBlock(t)) {
                      final block? => _block(block),
                      null => const SizedBox(width: double.infinity),
                    },
                  ),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CceSpace.lg,
                      vertical: CceSpace.md,
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

  /// Todo bloque de la mitad de arriba lleva el mismo margen lateral y el
  /// mismo aire con el de arriba: es lo que hace que se lean como una pila y
  /// no como parches (CCE#14).
  Widget _block(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(
          CceSpace.lg,
          CceSpace.md,
          CceSpace.lg,
          0,
        ),
        child: child,
      );

  /// El bloque de audio en REPOSO, sólo cuando importa (CCE#14, CCE#16):
  ///
  ///  - con el audio tomado, tomándose o fallado, el panel: un micrófono
  ///    abierto no se esconde, y un error hay que poder leerlo y cerrarlo;
  ///  - con el audio en la casa, nada, haya número escrito o no: la pantalla
  ///    es teclado. El aviso del #10/#12 vive en el sheet al tocar Llamar
  ///    ([showCallConfirmSheet]), que es el momento en que la pregunta "¿por
  ///    dónde voy a escuchar?" existe y se contesta con las dos salidas.
  Widget? _idleAudioBlock(TelephonyService t) {
    final audio = t.audio;
    if (audio.taken || audio.busy || audio.error != null) {
      return CallAudioPanel(audio: audio);
    }
    return null;
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

  // Pegar un número no tiene botón propio: el campo es un TextField y el
  // long-press abre el menú del sistema, como en cualquier app. Lo que entre
  // pasa igual por [sanitizeDialInput] (DialInputFormatter).

  // ── Comandos ──────────────────────────────────────────────────────────────

  /// Disca, avisando ANTES cuando corresponde (espejo de CCE#15): con el
  /// audio en la casa, la llamada saldría, el destino sonaría y el usuario no
  /// escucharía nada — se entera acá, no con la llamada en curso. Con el
  /// audio ya en este celular no se pregunta nada: el caso normal no gana
  /// ningún toque.
  Future<void> _call({String? number, PhoneContact? contact}) async {
    final t = widget.telephony;
    _numberFocus.unfocus();
    if (!t.audio.isOn) {
      final choice = await showCallConfirmSheet(
        context,
        telephony: t,
        who: contact?.displayName ?? number ?? '',
        number: contact?.number ?? number,
      );
      if (choice == null || !mounted) return;
      if (choice == CallChoice.takeAudioAndCall) {
        // Primero el audio, después el POST, como en el dashboard. Si tomarlo
        // falla (micrófono negado, red), la llamada sale IGUAL — nunca se
        // deja al usuario sin llamar — y el panel de la card explica qué pasó.
        await t.audio.take();
        if (!mounted) return;
      }
    }
    HapticFeedback.mediumImpact();
    setState(() => _dtmfSent = '');
    await t.call(number: number, contactId: contact?.id);
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
    // El visor muestra a quién se llama venga de donde venga el número: la
    // fila lo cargaba y el botón de llamar no, y la llamada entera transcurría
    // con el visor vacío (CCE#19).
    _setNumber(pick.contact.number);
    if (pick.callNow) await _call(contact: pick.contact);
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(Device d, TelephonyService t) {
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

  // ── Llamada entrante y en curso ───────────────────────────────────────────

  /// La card de una llamada, entrante o en curso: quién arriba, y debajo —
  /// separado por un hairline— el ruteo de la voz con los controles del audio
  /// ([CallAudioPanel] embebido, con [AudioRouteLine] como titular). Una
  /// superficie, un lenguaje: antes eran dos cards y una caja adentro de otra.
  ///
  /// Los tonos DTMF que salieron ([tones]) van acá y no en un visor aparte: el
  /// acuse importa, pero un visor de 68 px para él dejaba al teclado —que en
  /// llamada ES el teclado de tonos— en teclas de 40 px.
  Widget _callCard({
    required Widget glyph,
    required String who,
    required Widget subtitle,
    required Widget trailing,
    required Widget routeLine,
    required TelephonyService t,
    String tones = '',
  }) {
    return PhoneSurface(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              glyph,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      who,
                      style: CceText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    subtitle,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
          if (tones.isNotEmpty) ...[
            const SizedBox(height: 10),
            _tonesLine(tones),
          ],
          const SizedBox(height: 12),
          const PhoneDivider(),
          const SizedBox(height: 12),
          CallAudioPanel(
            audio: t.audio,
            embedded: true,
            headline: routeLine,
          ),
        ],
      ),
    );
  }

  /// El acuse de los tonos mandados a la llamada. Sin esto el teclado DTMF no
  /// devuelve nada: el menú de voz que responde está sonando en la casa.
  Widget _tonesLine(String tones) {
    return Semantics(
      label: 'Tonos enviados: $tones',
      child: Row(
        children: [
          const Icon(Icons.dialpad, size: 16, color: CceColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tones,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CceText.data.copyWith(
                fontSize: 17,
                letterSpacing: 3,
                color: CceColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// El ícono de la llamada, en un disco del color del estado.
  Widget _callGlyph(String icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: CceIcon(icon, size: 20, color: color),
    );
  }

  Widget _incomingCard(
    Device d,
    Map<String, dynamic>? incoming,
    TelephonyService t,
  ) {
    final s = d.state;
    final name = (incoming?['contactName'] ?? s.peerName ?? '').toString();
    final number = (incoming?['number'] ?? s.peerNumber ?? '').toString();
    final who = name.isNotEmpty
        ? name
        : (number.isEmpty ? 'Número desconocido' : number);

    return _callCard(
      t: t,
      glyph: _callGlyph(CceIcons.phoneIncoming, CceColors.ok),
      who: who,
      subtitle: Row(
        children: [
          // El pulso es para lo que hay que atender AHORA.
          const StatusDot(CceColors.ok, size: 6, pulse: true),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name.isNotEmpty && number.isNotEmpty
                  ? 'Entrante · $number'
                  : 'Llamada entrante',
              style: CceText.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: TextButton(
        onPressed: t.dismissIncoming,
        style: TextButton.styleFrom(
          foregroundColor: CceColors.textSecondary,
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('Ocultar'),
      ),
      // Atender desde la app no trae el audio al celular por sí solo: hay que
      // decirlo ANTES de atender, y ofrecer traerlo ahí mismo.
      // `taken` y no `isOn`: con el motor parado el audio SIGUE ruteado acá
      // (no suena en la casa), y el panel de abajo es el que dice que ahora
      // mismo no suena y ofrece reintentar.
      routeLine: AudioRouteLine.forIncoming(
        onThisPhone: t.audio.taken,
        stalled: t.audio.stalled,
      ),
    );
  }

  Widget _activeCall(Device d, TelephonyService t) {
    final s = d.state;
    final pending = t.dialingNumber;
    // Con quién: el nombre si el backend lo resolvió, si no el número — el que
    // dice el device, o mientras no lo diga, el que se discó (placeholder o
    // visor). "Sin identificar" es el último recurso, no el primero.
    final name = s.peerName;
    final number = s.peerNumber ??
        pending ??
        (_number.text.isEmpty ? null : _number.text);
    final who = name ?? number ?? 'Sin identificar';
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

    return _callCard(
      t: t,
      tones: _dtmfSent,
      glyph: _callGlyph(
        s.callDirection == 'in' ? CceIcons.phoneIncoming : CceIcons.phoneOutgoing,
        CceColors.accent,
      ),
      who: who,
      // Con nombre arriba, el número va abajo: se ve con quién Y a qué número.
      subtitle: Text(
        name != null && number != null ? '$label · $number' : label,
        style: CceText.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: elapsed != null && elapsed.inSeconds >= 0
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                formatCallDuration(elapsed),
                style: CceText.data.copyWith(
                  fontSize: 17,
                  color: CceColors.textSecondary,
                ),
              ),
            )
          : const SizedBox.shrink(),
      // EL aviso, mientras la llamada está viva y el usuario se pregunta por
      // qué no escucha nada — o, con el audio ya en el celular, por qué sí lo
      // escucha.
      routeLine: AudioRouteLine.forCall(
        t.status,
        onThisPhone: t.audio.taken,
        stalled: t.audio.stalled,
      ),
    );
  }

  /// El motivo REAL del rechazo, como lo redactó el backend ("hay una llamada
  /// en curso", "rate limit de llamadas por hora alcanzado"). Un genérico haría
  /// que el usuario reintente contra un límite que no va a ceder.
  Widget _errorBanner(String reason) {
    return PhoneSurface(
      tint: CceColors.danger,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
          const SizedBox(width: CceSpace.xxxl),
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
      padding: const EdgeInsets.fromLTRB(
        CceSpace.lg,
        CceSpace.sm,
        CceSpace.lg,
        CceSpace.lg,
      ),
      child: Center(child: row),
    );
  }
}
