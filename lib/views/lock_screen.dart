import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/ezviz_lock.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Pantalla de control de una CERRADURA EZVIZ (capability 'lock', provider
/// ezviz). Portada PÍXEL A PÍXEL del control neumórfico del dashboard
/// (lock-sidebar.component.ts): el cuerpo es una CARCASA que flota sobre un
/// fondo de drawer MÁS OSCURO (#16181D), con el HEADER fuera del control.
///
/// Recetas del manual de diseño del dashboard, traducidas a los tokens/helpers
/// existentes (CceColors, CceShadows.neo/neoInset/plato, CceGradients.concave/
/// convex, _PressFx, _lerp):
///  - HEADER (fuera de la carcasa): [badge redondo convexo · título+dot ·
///    cerrar redondo].
///  - Estado grande Trabada/Destrabada = PLATO CÓNCAVO (relieve externo + cara
///    hundida) con el candado y el label "encendidos" en el color de estado
///    (verde trabada / ámbar destrabada) con glow.
///  - Métricas (batería/conexión/último evento) en huecos HUNDIDOS (inset).
///  - Botón ABRIR CONVEXO prominente que se "enciende" (ámbar + glow) al
///    mantener; conserva el HOLD-TO-CONFIRM (~1,5 s) → unlock(serial). Nunca es
///    un click idempotente; el backend loguea cada apertura. Si el modelo no
///    soporta apertura remota (501), queda deshabilitado (inset hundido).
///  - Historial de eventos dentro de un hueco hundido; cada evento es un chip
///    redondo convexo tintado según tipo.
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
    return Scaffold(
      // Fondo de la app (#101014), MÁS oscuro que la carcasa (neoBase) para que
      // el control FLOTE con claridad (igual que la home).
      backgroundColor: CceColors.bg,
      // SIN header externo (se vuelve con el swipe iOS): consistente con el
      // termostato/Samsung. La carcasa se CENTRA verticalmente (sin el vacío de
      // abajo que se veía "roto") y, si el historial es largo, todo scrollea.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _buildCarcasa(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── CARCASA ─────────────────────────────────────────────────────────────────
  /// El cuerpo del control: radius 40, neoBase plano, padding 22, gap 22, con la
  /// sombra externa EXAGERADA del manual (10/10/28 negra abajo-der + -6/-6/20
  /// luz arriba-izq) para flotar sobre el fondo del drawer.
  Widget _buildCarcasa() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          // 10px 10px 28px rgba(0,0,0,0.45) — caída abajo-derecha.
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 28,
            offset: Offset(10, 10),
          ),
          // -6px -6px 20px rgba(42,45,55,0.25) — luz arriba-izquierda.
          BoxShadow(
            color: Color(0x402A2D37),
            blurRadius: 20,
            offset: Offset(-6, -6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Estado grande Trabada / Destrabada (PLATO cóncavo) ──────────
          _buildState(),
          const SizedBox(height: 22),

          // ── Métricas: batería · conexión · último evento (huecos inset) ─
          _buildMetrics(),
          const SizedBox(height: 22),

          // ── Botón abrir (convexo, hold-to-confirm) ──────────────────────
          _buildUnlockSection(),
          const SizedBox(height: 22),

          // ── Historial ───────────────────────────────────────────────────
          _buildEventsSection(),
        ],
      ),
    );
  }

  // ── ESTADO GRANDE ───────────────────────────────────────────────────────────
  /// Pieza que SOBRESALE de la carcasa (par de sombras externas marcado) con un
  /// disco PLATO CÓNCAVO al centro (gradiente cóncavo + relieve externo + cara
  /// hundida). El candado y el label se "encienden" en el color de estado.
  Widget _buildState() {
    final accent = _isLocked ? _locked : _unlocked;
    final glyph = _isLocked ? CceIcons.lockLocked : CceIcons.lockUnlocked;

    // El disco era de ancho FIJO (132). En la carcasa de un teléfono angosto el
    // disco + su padding lateral podían exceder el ancho disponible; lo hacemos
    // RELATIVO al ancho real del bloque (tope 132 como en el dashboard) para que
    // nunca desborde y conserve la proporción del plato en cualquier pantalla.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ancho útil dentro del padding horizontal (18*2) de este bloque.
        final double inner = (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 280.0) -
            36.0;
        final disk = inner.clamp(0.0, 132.0).toDouble();
        final glyphSize = disk * (56 / 132); // misma proporción que el original.

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(28),
            // El bloque SOBRESALE de la carcasa (par de sombras externas marcado:
            // 6/6/16 negra + -6/-6/16 luz, como el `.lock-state` del dashboard).
            boxShadow: CceShadows.neo(blur: 16, offset: 6),
          ),
          child: Column(
            children: [
              // Disco PLATO CÓNCAVO con el candado encendido + glow.
              Container(
                width: disk,
                height: disk,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: CceGradients.concave(CceColors.neoBase),
                  // PLATO: relieve externo (sobresale) + cara hundida (inset).
                  boxShadow: CceShadows.plato(blur: 15, offset: 6),
                ),
                // El candado "enciende" con el color de estado + glow neón
                // (drop-shadow del dashboard ≈ glowDot).
                child: _GlowGlyph(
                  svg: glyph,
                  size: glyphSize,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              // Label en el color de estado, con text-shadow (glow) como la web.
              // FittedBox para que "Destrabada" no desborde en anchos chicos.
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
                          color: accent.withValues(alpha: 0.65),
                          blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header del historial: título + refrescar (botón redondo).
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HISTORIAL', style: CceText.section),
            _RoundKey(
              svg: _kRefreshCw,
              semantic: 'Actualizar',
              size: 40,
              flat: true,
              spinning: _eventsLoading,
              onTap: _eventsLoading ? null : _loadEvents,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_eventsLoading && _events.isEmpty)
          const _EventsState(
            svg: null,
            text: 'Cargando eventos…',
            spinner: true,
          )
        else if (_events.isEmpty)
          const _EventsState(
            svg: CceIcons.calendar,
            text: 'Sin eventos registrados',
            spinner: false,
          )
        else
          // La lista vive en un hueco HUNDIDO para separarla de la carcasa.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: BorderRadius.circular(18),
              boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
            ),
            child: Column(
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x8C0C0D11))),
      ),
      child: Row(
        children: [
          // Chip redondo CONVEXO tintado según tipo (con glow del color).
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.convex(CceColors.neoBase),
              boxShadow: CceShadows.neo(blur: 8, offset: 3),
            ),
            child: _GlowGlyph(svg: _eventIconSvg(ev), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventLabel(ev),
                  style: CceText.body.copyWith(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtDateTime(ev.at),
                  style: CceText.caption.copyWith(
                    fontSize: 12,
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

/// Glyph SVG "encendido": el ícono tintado con su color + glow (drop-shadow),
/// réplica del `filter: drop-shadow(0 0 N color)` del dashboard. Sin emboss
/// (el glow reemplaza al relieve), con un par de copias desenfocadas detrás.
class _GlowGlyph extends StatelessWidget {
  const _GlowGlyph({
    required this.svg,
    required this.size,
    required this.color,
  });

  final String svg;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final glow = color.withValues(alpha: 0.65);
    // BLINDAJE: el Stack va envuelto en SizedBox.square(size) para fijar su
    // tamano de LAYOUT a size x size. Asi el glyph NUNCA puede expandirse a
    // tamano pantalla, aun bajo constraints infinitas. Se conserva
    // clipBehavior: Clip.none para que el halo (blur = size * 0.16) siga
    // pintandose fuera del cuadrado sin afectar el tamano de layout.
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Halo: copia desenfocada del glyph teñida con el color (el
          // "drop-shadow" neón). blur escala con el tamaño del glyph.
          ImageFilteredGlyph(
              svg: svg, size: size, color: glow, blur: size * 0.16),
          // Glyph nítido al frente.
          CceIcon(svg, size: size, color: color, emboss: false),
        ],
      ),
    );
  }
}

/// Copia desenfocada de un [CceIcon] (sirve como halo/glow detrás del glyph
/// real). Aislada en su propio widget para mantener el `build` legible.
class ImageFilteredGlyph extends StatelessWidget {
  const ImageFilteredGlyph({
    super.key,
    required this.svg,
    required this.size,
    required this.color,
    required this.blur,
  });

  final String svg;
  final double size;
  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: CceIcon(svg, size: size, color: color, emboss: false),
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
          _GlowGlyph(svg: CceIcons.check, size: 20, color: accent),
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
