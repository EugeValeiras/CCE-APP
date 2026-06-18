import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/ezviz_lock.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Pantalla de control de una CERRADURA EZVIZ (capability 'lock', provider
/// ezviz). Espejo del control neumórfico del dashboard (lock-sidebar
/// .component.ts) a ancho de celular: un PANEL PLANO full-screen (fondo neoBase
/// de borde a borde, SIN tarjeta flotante) sobre el que cada bloque hace su
/// propio relieve.
///
/// Es de SOLO ESTADO + HISTORIAL: sin header ni botón de apertura (no se abre la
/// casa desde el celular manteniendo presionado; eso además evita el preview de
/// drag de iOS). El código del botón ABRIR queda en el archivo
/// (_buildUnlockSection / _UnlockButton) por si se reconecta, pero NO se monta.
///
/// Recetas del manual de diseño del dashboard, traducidas a los tokens/helpers
/// existentes (CceColors, CceShadows.neo/neoInset/plato/glowDot,
/// CceGradients.concave/convex, _PressFx, _lerp):
///  - Estado grande Trabada/Destrabada = PLATO CÓNCAVO (relieve externo + cara
///    hundida) con el candado y el label "encendidos" en el color de estado
///    (verde trabada / ámbar destrabada) con glow (SOLO vía BoxShadow).
///  - Métricas (batería/conexión/último evento) en huecos HUNDIDOS (inset).
///  - Historial de eventos en un hueco hundido; cada evento es un chip redondo
///    CONVEXO tintado + glow según tipo, en filas con hairline oscuro.
///
/// Todos los íconos salen de icons0.dev (colección lucide): los de [CceIcons]
/// más los cuatro vendoreados localmente acá ([_kBatteryFull], [_kWifi],
/// [_kWifiOff], [_kRefreshCw]) que el catálogo compartido aún no expone.
///
/// Convención de estado (diseño): `state.on` = trabada (isLocked).
class LockScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  const LockScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  // ── Colores de estado del dashboard (tema oscuro) ──
  // Verde "trabada" (--neo-ok #34D399) y ámbar "destrabada" (--lock-amber
  // #FF9F0A) idénticos al manual del dashboard.
  static const Color _locked = CceColors.ok; // #34D399 (encendido = trabada)
  static const Color _unlocked = Color(0xFFFF9F0A); // ámbar (destrabada)
  static const Color _danger = CceColors.danger; // #FF4D5E

  static const Duration _holdDuration = Duration(milliseconds: 1500);

  late final ApiService _api;

  // Estado fresco de /status (cae al merged device si todavía no llegó).
  EzvizLockStatus? _status;

  // Eventos.
  List<EzvizLockEvent> _events = const [];
  bool _eventsLoading = false;

  // Unlock.
  bool _unlockSupported = true;
  String? _unlockReason;
  bool _unlocking = false;
  bool _unlockDone = false;
  String? _unlockError;
  int? _lastUnlockAt;

  // Hold-to-confirm.
  bool _holding = false;
  double _holdPct = 0;
  Timer? _holdTimer;
  Timer? _doneTimer;

  String? get _serial => widget.device.ezvizSerial;

  // ── Estado derivado: prioriza el /status fresco; cae al merged device ──
  bool get _isLocked => _status?.isLocked ?? widget.device.state.on;
  bool get _online => _status?.online ?? widget.device.state.reachable;
  String? get _batteryRaw => _status?.battery ?? widget.device.sensor?.battery;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.service.config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadStatus();
      _loadEvents();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _doneTimer?.cancel();
    super.dispose();
  }

  // ── Carga ──────────────────────────────────────────────────────────────
  Future<void> _loadStatus() async {
    final serial = _serial;
    if (serial == null) return;
    try {
      final s = await _api.getLockStatus(serial);
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // Silencioso: cae al estado del merged device.
    }
  }

  Future<void> _loadEvents() async {
    final serial = _serial;
    if (serial == null) return;
    setState(() => _eventsLoading = true);
    final evs = await _api.getLockEvents(serial);
    if (!mounted) return;
    // Ordenar desc por fecha.
    final sorted = [...evs]..sort((a, b) => b.at.compareTo(a.at));
    setState(() {
      _events = sorted;
      _eventsLoading = false;
    });
  }

  // ── Hold-to-confirm ──────────────────────────────────────────────────────
  void _startHold() {
    if (_unlocking || !_online || !_unlockSupported) return;
    setState(() {
      _unlockError = null;
      _holding = true;
      _holdPct = 0;
    });
    final start = DateTime.now();
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final pct =
          (elapsed / _holdDuration.inMilliseconds).clamp(0.0, 1.0).toDouble();
      if (mounted) setState(() => _holdPct = pct);
      if (pct >= 1.0) {
        _clearHold();
        HapticFeedback.mediumImpact();
        _doUnlock();
      }
    });
  }

  void _cancelHold() {
    if (_holdPct >= 1.0) return; // ya disparó
    _clearHold();
  }

  void _clearHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) {
      setState(() {
        _holding = false;
        _holdPct = 0;
      });
    }
  }

  Future<void> _doUnlock() async {
    final serial = _serial;
    if (serial == null) return;
    setState(() {
      _unlocking = true;
      _unlockError = null;
    });
    try {
      final res = await _api.unlock(serial);
      if (!mounted) return;
      if (res.supported == false) {
        setState(() {
          _unlocking = false;
          _unlockSupported = false;
          _unlockReason = res.reason;
        });
        return;
      }
      if (res.success) {
        setState(() {
          _unlocking = false;
          _unlockDone = true;
          _lastUnlockAt = res.ts != null
              ? (DateTime.tryParse(res.ts!)?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch)
              : DateTime.now().millisecondsSinceEpoch;
        });
        _doneTimer?.cancel();
        _doneTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _unlockDone = false);
        });
        // El unlock genera un evento → refrescar historial y estado.
        _loadEvents();
        _loadStatus();
      } else {
        setState(() {
          _unlocking = false;
          _unlockError = res.reason ?? 'No se pudo abrir la cerradura';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _unlockError = 'Error al abrir la cerradura';
      });
    }
  }

  // ── Formato es-AR ────────────────────────────────────────────────────────
  String _fmtDateTime(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    final yy = two(d.year % 100);
    return '${two(d.day)}/${two(d.month)}/$yy ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtRelative(int ms) {
    if (ms <= 0) return '—';
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    final min = (diff / 60000).floor();
    if (min < 1) return 'ahora';
    if (min < 60) return 'hace $min min';
    final hr = (min / 60).floor();
    if (hr < 24) return 'hace $hr h';
    final d = (hr / 24).floor();
    return 'hace $d d';
  }

  String get _batteryLabel {
    final b = _batteryRaw;
    if (b == null || b.isEmpty) return '—';
    return b.endsWith('%') ? b : '$b%';
  }

  int? get _batteryPct {
    final b = _batteryRaw;
    if (b == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(b);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// "Último evento" (métrica): tiempo relativo del evento más reciente del
  /// historial cargado (los eventos vienen ordenados desc por fecha). El modelo
  /// mobile no expone `sensor.lockEventAt` como el dashboard, así que derivamos
  /// del historial, que ya cargamos al abrir.
  String get _lastEventLabel {
    if (_events.isEmpty) return '—';
    return _fmtRelative(_events.first.at);
  }

  // ── Mapeo de tipos de evento → UI es-AR (espejo del dashboard) ───────────
  String? _methodFromMessage(String? message) {
    final m = (message ?? '').toLowerCase();
    if (m.isEmpty) return null;
    if (m.contains('fingerprint') || m.contains('huella')) return 'huella';
    if (m.contains('face') || m.contains('rostro')) return 'rostro';
    if (m.contains('card') || m.contains('tarjeta')) return 'tarjeta';
    if (m.contains('password') ||
        m.contains('pin') ||
        m.contains('code') ||
        m.contains('código')) return 'código';
    if (m.contains('remote') || m.contains('app') || m.contains('remoto')) {
      return 'remoto';
    }
    if (m.contains('key') || m.contains('llave')) return 'llave';
    if (m.contains('temporary') || m.contains('temporal')) return 'temporal';
    return null;
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'open':
        return 'Apertura';
      case 'unlock':
        return 'Destrabada';
      case 'lock':
        return 'Trabada';
      case 'doorbell':
        return 'Timbre';
      case 'attempt':
        return 'Intento fallido';
      case 'ajar':
        return 'Puerta abierta';
      default:
        return kind;
    }
  }

  String _eventLabel(EzvizLockEvent ev) {
    // Priorizamos el mensaje humano de EZVIZ.
    if (ev.message != null && ev.message!.isNotEmpty) return ev.message!;
    final action = _kindLabel(ev.kind);
    final method = _methodFromMessage(ev.message);
    if (ev.actor != null && ev.actor!.isNotEmpty) {
      return method != null
          ? '${ev.actor} · $action ($method)'
          : '${ev.actor} · $action';
    }
    return method != null ? '$action ($method)' : action;
  }

  String _eventIconSvg(EzvizLockEvent ev) {
    switch (ev.kind) {
      case 'open':
      case 'ajar':
        return CceIcons.doorOpen;
      case 'unlock':
        return CceIcons.lockUnlocked;
      case 'lock':
        return CceIcons.lockLocked;
      case 'doorbell':
        return CceIcons.handTap;
      case 'attempt':
        return CceIcons.alarmShield;
      default:
        return CceIcons.history;
    }
  }

  Color _eventColor(String kind) {
    switch (kind) {
      case 'open':
      case 'unlock':
        return _unlocked;
      case 'lock':
        return _locked;
      case 'doorbell':
        return CceColors.info;
      case 'attempt':
      case 'ajar':
        return _danger;
      default:
        return CceColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    // PANEL PLANO full-screen (espejo del lock-sidebar del dashboard a ancho de
    // celular): fondo neoBase de borde a borde, SIN tarjeta flotante. Cada
    // bloque (estado/métricas/historial) hace su propio relieve sobre el panel.
    // SIN header externo (el swipe iOS vuelve atrás). Scroll estándar y simple,
    // alineado ARRIBA, para historial largo (patrón confiable: nada de
    // FittedBox/minHeight que dejaban el render vacío en versiones previas).
    return Scaffold(
      backgroundColor: CceColors.neoBase,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: _buildPanel(),
        ),
      ),
    );
  }

  // ── PANEL ─────────────────────────────────────────────────────────────────
  /// El cuerpo del control, ahora un PANEL PLANO (sin tarjeta flotante): los
  /// bloques (estado · métricas · historial) se apilan directo sobre el fondo
  /// neoBase del Scaffold, cada uno con su propio relieve neumórfico.
  Widget _buildPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Estado grande Trabada / Destrabada (PLATO cóncavo) ──────────
        _buildState(),
        const SizedBox(height: 22),

        // ── Métricas: batería · conexión · último evento (huecos inset) ─
        _buildMetrics(),
        const SizedBox(height: 22),

        // (Sin botón de apertura: el usuario no abre la casa desde el celular
        // manteniendo presionado; esta pantalla es para VER estado + historial.
        // Eso además elimina el preview de drag de iOS que aparecía al mantener.)

        // ── Historial ───────────────────────────────────────────────────
        _buildEventsSection(),
        const SizedBox(height: 18),
        // Wordmark al pie (estilo termostato).
        const _Wordmark('CCE SMARTLOCK'),
      ],
    );
  }

  // ── ESTADO GRANDE ───────────────────────────────────────────────────────────
  /// Pieza que SOBRESALE de la carcasa (par de sombras externas marcado) con un
  /// disco PLATO CÓNCAVO al centro (gradiente cóncavo + relieve externo + cara
  /// hundida). El candado y el label se "encienden" en el color de estado.
  Widget _buildState() {
    final accent = _isLocked ? _locked : _unlocked;
    final glyph = _isLocked ? CceIcons.lockLocked : CceIcons.lockUnlocked;

    // Disco PLATO de tamaño FIJO (132) y candado de tamaño FIJO (56). NADA de
    // tamaños derivados: todo glifo queda acotado dentro de su SizedBox.square.
    // El glow del candado sale EXCLUSIVAMENTE de BoxShadow (glowDot) y de los
    // Text.shadows del label — NUNCA de blur/filtros de imagen.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(28),
        // El bloque SOBRESALE de la carcasa (par de sombras externas marcado).
        boxShadow: CceShadows.neo(blur: 16, offset: 6),
      ),
      child: Column(
        children: [
          // Disco PLATO CÓNCAVO con el candado encendido. Tamaño FIJO 132.
          Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.concave(CceColors.neoBase),
              // PLATO (relieve externo + cara hundida) + glow del color de
              // estado, SOLO via BoxShadow.
              boxShadow: [
                ...CceShadows.plato(blur: 15, offset: 6),
                ...CceShadows.glowDot(accent),
              ],
            ),
            // Candado acotado: SizedBox.square fijo + CceIcon emboss:false.
            child: SizedBox.square(
              dimension: 56,
              child: CceIcon(glyph, size: 56, color: accent, emboss: false),
            ),
          ),
          const SizedBox(height: 16),
          // Label en el color de estado, con text-shadow (glow).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _isLocked ? 'Trabada' : 'Destrabada',
              maxLines: 1,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: accent,
                shadows: [
                  Shadow(
                      color: accent.withValues(alpha: 0.65), blurRadius: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── MÉTRICAS ──────────────────────────────────────────────────────────────
  /// Tres huecos HUNDIDOS (inset puro) fundidos en la carcasa: batería ·
  /// conexión · último evento.
  Widget _buildMetrics() {
    // El gap fijo de 12 entre las 3 métricas comía demasiado ancho en teléfonos
    // angostos (≈85px por slot), dejando los valores apretados/recortados. Lo
    // hacemos relativo: 8px en pantallas chicas (espejo del breakpoint <480px
    // del dashboard), 12px en tablet. Cada métrica vive en un Expanded (1fr) y
    // su contenido se auto-escala (FittedBox) para no desbordar nunca.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final gap = narrow ? 8.0 : 12.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Metric(
                svg: _kBatteryFull,
                iconColor: _batteryColor(),
                value: _batteryLabel,
                label: 'Batería',
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _Metric(
                svg: _online ? _kWifi : _kWifiOff,
                iconColor: _online ? _locked : CceColors.textTertiary,
                value: _online ? 'OK' : '—',
                label: 'Conexión',
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _Metric(
                svg: CceIcons.history,
                iconColor: CceColors.textSecondary,
                value: _lastEventLabel,
                label: 'Último evento',
              ),
            ),
          ],
        );
      },
    );
  }

  Color _batteryColor() {
    final pct = _batteryPct;
    if (pct == null) return CceColors.textTertiary;
    if (pct <= 15) return _danger;
    if (pct <= 35) return _unlocked;
    return _locked;
  }

  // ── BOTÓN ABRIR ─────────────────────────────────────────────────────────────
  Widget _buildUnlockSection() {
    // No soportado: botón HUNDIDO (inset) deshabilitado + razón.
    if (!_unlockSupported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: BorderRadius.circular(18),
              boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                CceIcon(CceIcons.lockLocked,
                    size: 20, color: CceColors.textTertiary, emboss: false),
                const SizedBox(width: 8),
                // Flexible para que la leyenda no desborde el botón en pantallas
                // angostas (cae a "…" antes que tirar un RenderFlex overflow).
                const Flexible(
                  child: Text(
                    'No soportado por el modelo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CceColors.textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _unlockReason ??
                'Esta cerradura no admite apertura remota vía la API de EZVIZ.',
            style: CceText.caption.copyWith(
              fontSize: 12,
              color: CceColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final enabled = _online && !_unlocking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnlockButton(
          enabled: enabled,
          holding: _holding,
          done: _unlockDone,
          unlocking: _unlocking,
          holdPct: _holdPct,
          unlockedColor: _unlocked,
          doneColor: _locked,
          onPointerDown: enabled ? _startHold : null,
          onPointerEnd: _cancelHold,
        ),
        const SizedBox(height: 10),
        Text(
          'Acción de seguridad: mantené presionado 1,5 s para confirmar.',
          style: CceText.caption.copyWith(
            fontSize: 12,
            color: CceColors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
        if (_lastUnlockAt != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 16, color: CceColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Última apertura: ${_fmtDateTime(_lastUnlockAt!)}',
                  style: CceText.caption.copyWith(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
        if (_unlockError != null) ...[
          const SizedBox(height: 8),
          Text(
            _unlockError!,
            style: const TextStyle(color: _danger, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // ── HISTORIAL ───────────────────────────────────────────────────────────────
  Widget _buildEventsSection() {
    final loading = _eventsLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header del historial: título + refrescar (simple, sin _RoundKey).
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HISTORIAL', style: CceText.section),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: loading ? null : _loadEvents,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CceColors.neoBase,
                  boxShadow: CceShadows.neo(blur: 6, offset: 2),
                ),
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CceColors.textSecondary,
                        ),
                      )
                    : SizedBox.square(
                        dimension: 16,
                        child: CceIcon(_kRefreshCw,
                            size: 16,
                            color: CceColors.textSecondary,
                            emboss: false),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                loading ? 'Cargando eventos…' : 'Sin eventos registrados',
                style:
                    const TextStyle(color: CceColors.textTertiary, fontSize: 13),
              ),
            ),
          )
        else
          // Lista en un well HUNDIDO (neoBase + inset) para separarla (espejo
          // del dashboard, que usa --neo-base en .events-list).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: BorderRadius.circular(18),
              boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _events.length; i++)
                  _buildEventRow(_events[i], last: i == _events.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEventRow(EzvizLockEvent ev, {required bool last}) {
    final color = _eventColor(ev.kind);
    // Glow solo en los tipos tintados; el 'otro'/default queda neutro (en el
    // dashboard sólo las clases ev-* llevan drop-shadow).
    final glow = color != CceColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                // hairline oscuro (espejo de rgba(12,13,17,0.55) del dashboard).
                bottom: BorderSide(
                    color: CceColors.neoDark.withValues(alpha: 0.55)),
              ),
      ),
      child: Row(
        children: [
          // Chip redondo CONVEXO tintado + glow según tipo (espejo .event-icon
          // del dashboard: gradiente convexo + par de sombras neo + aura del
          // color, SOLO vía BoxShadow — nunca filtros de imagen, por Impeller).
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.convex(CceColors.neoBase),
              boxShadow: [
                ...CceShadows.neo(blur: 8, offset: 3),
                if (glow)
                  BoxShadow(
                    color: color.withValues(alpha: 0.40),
                    blurRadius: 8,
                  ),
              ],
            ),
            child: SizedBox.square(
              dimension: 16,
              child: CceIcon(_eventIconSvg(ev),
                  size: 16, color: color, emboss: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _eventLabel(ev),
                  style: CceText.body.copyWith(fontSize: 13.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtDateTime(ev.at),
                  style: CceText.caption.copyWith(
                    fontSize: 11.5,
                    color: CceColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SUBWIDGETS NEUMÓRFICOS
// ════════════════════════════════════════════════════════════════════════════

/// Botón circular neumórfico genérico (badge / cerrar / refrescar). Convexo por
/// defecto (gradiente + sombra externa estándar); `flat:true` lo deja plano
/// (neoBase) como `.btn-close`/`.btn-refresh`. `accent` tiñe el glyph (badge en
/// info). Se hunde (inset) al presionar vía [_PressFx]+[_lerp]. `spinning` lo
/// reemplaza por un spinner (refrescar cargando).
class _RoundKey extends StatelessWidget {
  const _RoundKey({
    this.svg,
    this.icon,
    required this.semantic,
    required this.onTap,
    this.size = 48,
    this.flat = false,
    this.accent,
    this.spinning = false,
    this.dimWhenDisabled = true,
  });

  final String? svg;
  final IconData? icon;
  final String semantic;
  final VoidCallback? onTap;
  final double size;
  final bool flat;
  final Color? accent;
  final bool spinning;

  /// Por defecto, sin `onTap` el botón se atenúa (deshabilitado). El badge del
  /// header es decorativo: pasa `false` para mantenerse a opacidad plena.
  final bool dimWhenDisabled;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    final Color glyph = accent ?? CceColors.textSecondary;

    Widget content;
    if (spinning) {
      content = SizedBox(
        width: size * 0.4,
        height: size * 0.4,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: CceColors.textSecondary,
        ),
      );
    } else if (svg != null) {
      content = CceIcon(svg!, size: size * 0.44, color: glyph, emboss: false);
    } else {
      content = Icon(icon, size: size * 0.42, color: glyph);
    }

    Widget body(double t) => Semantics(
          button: onTap != null,
          label: semantic,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: flat ? CceColors.neoBase : null,
              gradient: flat ? null : CceGradients.convex(CceColors.neoBase),
              boxShadow: _lerp(raised, inset, t),
            ),
            child: content,
          ),
        );

    // Decorativo (badge): sin onTap y sin atenuar → render directo sin gesto.
    if (onTap == null && !dimWhenDisabled) return body(0);

    return _PressFx(onTap: onTap, builder: body);
  }
}

/// Una métrica (batería / conexión / último evento): hueco HUNDIDO (inset puro)
/// fundido en la carcasa, con glyph + valor + label en mayúsculas.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.svg,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final String svg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      // padding horizontal mínimo (4) para no robar ancho al contenido en
      // teléfonos angostos (espejo del `.metric { padding: 12px 4px }` <480px
      // del dashboard).
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(16),
        boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(svg, size: 22, color: iconColor, emboss: false),
          const SizedBox(height: 6),
          // El valor (p.ej. "hace 5 min", "100%") se AUTO-ESCALA al ancho del
          // slot en vez de recortarse feo con "…": en tablet se ve a tamaño
          // pleno, en teléfono encoge lo justo para entrar.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: CceText.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: CceText.section.copyWith(fontSize: 9.5, letterSpacing: 0.6),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Estado vacío / cargando del historial (centrado, atenuado).
class _EventsState extends StatelessWidget {
  const _EventsState({
    required this.svg,
    required this.text,
    required this.spinner,
  });

  final String? svg;
  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          if (spinner)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CceColors.textTertiary,
              ),
            )
          else if (svg != null)
            CceIcon(svg!, size: 28, color: CceColors.textTertiary, emboss: false),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(color: CceColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Wordmark al pie del control (estilo termostato): texto grabado en la
/// carcasa con doble sombra (luz arriba-izq + oscura abajo-der).
class _Wordmark extends StatelessWidget {
  const _Wordmark(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: CceColors.textTertiary,
          shadows: [
            Shadow(
              color: Color(0x2EFFFFFF),
              offset: Offset(-0.6, -0.8),
            ),
            Shadow(
              color: Color(0xCC05060A),
              offset: Offset(0.8, 1.2),
              blurRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón ABRIR: barra CONVEXA prominente que se "enciende" (ámbar + glow) al
/// mantener y se hunde (inset) al presionar. El relleno de progreso del hold
/// sube de izq→der con un glow ámbar (réplica del `.unlock-fill`). Conserva el
/// HOLD-TO-CONFIRM: el padre arranca/cancela el timer vía los callbacks.
class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.enabled,
    required this.holding,
    required this.done,
    required this.unlocking,
    required this.holdPct,
    required this.unlockedColor,
    required this.doneColor,
    required this.onPointerDown,
    required this.onPointerEnd,
  });

  final bool enabled;
  final bool holding;
  final bool done;
  final bool unlocking;
  final double holdPct;
  final Color unlockedColor;
  final Color doneColor;
  final VoidCallback? onPointerDown;
  final VoidCallback onPointerEnd;

  @override
  Widget build(BuildContext context) {
    // Color del label "encendido": verde al completar; ámbar en reposo/holding
    // (el reposo ya tinta el icono en ámbar para invitar a apretarse).
    final Color accent = done ? doneColor : unlockedColor;
    final bool glow = holding || done;

    final labelStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: accent,
      shadows: glow
          ? [Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 10)]
          : null,
    );

    Widget label;
    if (unlocking) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text('Abriendo…',
              style: labelStyle.copyWith(color: CceColors.neoText)),
        ],
      );
    } else if (done) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 20,
            child:
                CceIcon(CceIcons.check, size: 20, color: accent, emboss: false),
          ),
          const SizedBox(width: 8),
          Text('Abierta', style: labelStyle),
        ],
      );
    } else if (holding) {
      label = Text('Mantené presionado…', style: labelStyle);
    } else {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(CceIcons.lockUnlocked, size: 20, color: accent, emboss: false),
          const SizedBox(width: 8),
          Text('Mantené para abrir', style: labelStyle),
        ],
      );
    }

    return Listener(
      onPointerDown: enabled ? (_) => onPointerDown?.call() : null,
      onPointerUp: (_) => onPointerEnd(),
      onPointerCancel: (_) => onPointerEnd(),
      child: Opacity(
        opacity: enabled || unlocking ? 1.0 : 0.55,
        child: _UnlockBody(
          holding: holding,
          holdPct: holdPct,
          fillColor: unlockedColor,
          label: label,
        ),
      ),
    );
  }
}

/// Cuerpo visual del botón ABRIR: la barra convexa (→ inset al mantener) con el
/// relleno de progreso del hold y el label centrado.
class _UnlockBody extends StatelessWidget {
  const _UnlockBody({
    required this.holding,
    required this.holdPct,
    required this.fillColor,
    required this.label,
  });

  final bool holding;
  final double holdPct;
  final Color fillColor;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    // Reposo CONVEXO (sobresale); al mantener pasa a INSET (se hunde, como el
    // `:active` del dashboard que toma el press).
    final boxShadow = holding
        ? CceShadows.neoInset(blur: 8, offset: 3)
        : CceShadows.neo(blur: 10, offset: 4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 60,
      decoration: BoxDecoration(
        gradient: CceGradients.convex(CceColors.neoBase),
        borderRadius: BorderRadius.circular(18),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Relleno de progreso del hold: glow ámbar que sube de izq→der.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: holdPct.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        fillColor.withValues(alpha: 0.10),
                        fillColor.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // El label se centra y se auto-escala si no entra (teléfonos muy
            // angostos): nunca desborda el botón.
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(fit: BoxFit.scaleDown, child: label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ÍCONOS VENDOREADOS (icons0.dev · colección lucide)
//  Los que el catálogo compartido CceIcons aún no expone. Mantienen el formato
//  exacto de CceIcons (currentColor, stroke 2, lucide) para verse idénticos.
// ════════════════════════════════════════════════════════════════════════════

/// lucide:battery-full
const String _kBatteryFull =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M10 10v4m4-4v4m8 0v-4M6 10v4"/><rect width="16" height="12" x="2" y="6" rx="2"/></g></svg>';

/// lucide:wifi
const String _kWifi =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 20h.01M2 8.82a15 15 0 0 1 20 0M5 12.859a10 10 0 0 1 14 0m-10.5 3.57a5 5 0 0 1 7 0"/></svg>';

/// lucide:wifi-off
const String _kWifiOff =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 20h.01M8.5 16.429a5 5 0 0 1 7 0M5 12.859a10 10 0 0 1 5.17-2.69m8.83 2.69a10 10 0 0 0-2.007-1.523M2 8.82a15 15 0 0 1 4.177-2.643M22 8.82a15 15 0 0 0-11.288-3.764M2 2l20 20"/></svg>';

/// lucide:refresh-cw
const String _kRefreshCw =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M3 12a9 9 0 0 1 9-9a9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5m5 4a9 9 0 0 1-9 9a9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/></g></svg>';

// ════════════════════════════════════════════════════════════════════════════
//  HELPERS COMPARTIDOS (gemelos de los de tv_screen.dart; este archivo es el
//  único editable, así que se replican acá para no depender de aquel)
// ════════════════════════════════════════════════════════════════════════════

/// Interpola dos pares de sombra (raised ↔ inset) por `t` (0..1).
List<BoxShadow> _lerp(List<BoxShadow> a, List<BoxShadow> b, double t) {
  final n = math.min(a.length, b.length);
  return [for (var i = 0; i < n; i++) BoxShadow.lerp(a[i], b[i], t)!];
}

/// Gesto neumórfico ligero (escala + háptico + reacción de relieve vía builder).
/// `onTap == null` ⇒ deshabilitado (sin gesto, atenuado al 45%).
class _PressFx extends StatefulWidget {
  const _PressFx({this.child, this.builder, required this.onTap})
      : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(double t)? builder;
  final VoidCallback? onTap;

  @override
  State<_PressFx> createState() => _PressFxState();
}

class _PressFxState extends State<_PressFx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 0,
  );

  bool get _enabled => widget.onTap != null;

  void _press() => _c.animateTo(1,
      duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
  void _release() => _c.animateBack(0,
      duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final t = _c.value;
        final w = widget.builder != null ? widget.builder!(t) : widget.child!;
        final s = 1 - 0.06 * t; // hundido sutil (0.94 a fondo).
        return Transform.scale(scale: s, child: w);
      },
    );

    if (!_enabled) {
      // Deshabilitado: atenúa al 45% para leerse "apagado" sin desmontar.
      return Opacity(opacity: 0.45, child: core);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.onTap,
      child: core,
    );
  }
}
