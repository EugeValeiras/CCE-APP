import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/ezviz_lock.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Pantalla de control de una CERRADURA EZVIZ (capability 'lock', provider
/// ezviz). Portada del dashboard (lock-sidebar.component.ts), estilo neumórfico
/// alineado con el resto de la app (thermostat_screen). Todos los íconos salen
/// de icons0.dev ([CceIcons]).
///
/// - Estado grande Trabada (verde) / Destrabada (ámbar) con glifo candado.
/// - Métricas: batería (parsea "NN%") + conexión.
/// - Botón "Abrir" HOLD-TO-CONFIRM (~1,5 s presionado) → unlock(serial). Nunca
///   es un click idempotente; el backend loguea cada apertura. Si el modelo no
///   soporta apertura remota (501), el botón queda deshabilitado con el texto.
/// - Historial de eventos (aperturas, timbre, intentos) en es-AR.
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
  // Verde "trabada" y ámbar "destrabada" del diseño del dashboard.
  static const Color _locked = Color(0xFF34C759); // #34c759
  static const Color _unlocked = Color(0xFFFF9F0A); // #ff9f0a (≈ CceColors.warm)
  static const Color _danger = Color(0xFFFF453A);

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
  String? get _batteryRaw =>
      _status?.battery ?? widget.device.sensor?.battery;

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
    final accent = _isLocked ? _locked : _unlocked;
    final glyph = _isLocked ? CceIcons.lockLocked : CceIcons.lockUnlocked;

    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(widget.service.displayName(widget.device), style: CceText.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: CceColors.textSecondary),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          // ── Estado grande Trabada / Destrabada ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(CceRadii.card),
            ),
            child: Column(
              children: [
                CceIcon(glyph, size: 64, color: accent),
                const SizedBox(height: 10),
                Text(
                  _isLocked ? 'Trabada' : 'Destrabada',
                  style: CceText.display.copyWith(
                    fontSize: 30,
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Métricas: batería + conexión ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: CceIcons.power,
                  iconColor: _batteryColor(),
                  value: _batteryLabel,
                  label: 'Batería',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  icon: CceIcons.bluetooth,
                  iconColor: _online ? _locked : CceColors.textTertiary,
                  value: _online ? 'En línea' : 'Sin conexión',
                  label: 'Conexión',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Botón abrir (hold-to-confirm) ───────────────────────────────
          _buildUnlockSection(),

          const SizedBox(height: 28),

          // ── Historial ───────────────────────────────────────────────────
          _buildEventsSection(),
        ],
      ),
    );
  }

  Color _batteryColor() {
    final pct = _batteryPct;
    if (pct == null) return CceColors.textTertiary;
    if (pct <= 15) return _danger;
    if (pct <= 35) return _unlocked;
    return _locked;
  }

  Widget _buildUnlockSection() {
    if (!_unlockSupported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CceColors.surfaceHigh,
              borderRadius: BorderRadius.circular(CceRadii.control),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CceIcon(CceIcons.lockLocked,
                    size: 20, color: CceColors.textTertiary),
                const SizedBox(width: 8),
                const Text(
                  'No soportado por el modelo',
                  style: TextStyle(
                    color: CceColors.textTertiary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _unlockReason ??
                'Esta cerradura no admite apertura remota vía la API de EZVIZ.',
            style: CceText.caption.copyWith(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final enabled = _online && !_unlocking;
    final bg = _unlockDone
        ? _locked
        : (_holding ? const Color(0xFFFF8800) : _unlocked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Listener(
          onPointerDown: enabled ? (_) => _startHold() : null,
          onPointerUp: (_) => _cancelHold(),
          onPointerCancel: (_) => _cancelHold(),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.55,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CceRadii.control),
              child: Stack(
                children: [
                  Container(height: 56, color: bg),
                  // Relleno de progreso del hold.
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _holdPct,
                      child: Container(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(child: _unlockLabel()),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Acción de seguridad: mantené presionado 1,5 s para confirmar.',
          style: CceText.caption.copyWith(fontSize: 12),
          textAlign: TextAlign.center,
        ),
        if (_lastUnlockAt != null) ...[
          const SizedBox(height: 10),
          Text(
            'Última apertura: ${_fmtDateTime(_lastUnlockAt!)}',
            style: CceText.caption.copyWith(fontSize: 12),
            textAlign: TextAlign.center,
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

  Widget _unlockLabel() {
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    if (_unlocking) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 10),
          Text('Abriendo…', style: labelStyle),
        ],
      );
    }
    if (_unlockDone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CceIcon(CceIcons.check, size: 20, color: Colors.white, emboss: false),
          const SizedBox(width: 8),
          const Text('Abierta', style: labelStyle),
        ],
      );
    }
    if (_holding) {
      return const Text('Mantené presionado…', style: labelStyle);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CceIcon(CceIcons.lockUnlocked, size: 20, color: Colors.white, emboss: false),
        const SizedBox(width: 8),
        const Text('Mantené para abrir', style: labelStyle),
      ],
    );
  }

  Widget _buildEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HISTORIAL', style: CceText.section),
            IconButton(
              icon: _eventsLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: CceColors.textSecondary),
                    )
                  : const CceIcon(CceIcons.history,
                      size: 20, color: CceColors.textSecondary),
              tooltip: 'Actualizar',
              onPressed: _eventsLoading ? null : _loadEvents,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_eventsLoading && _events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Cargando eventos…',
                  style: TextStyle(color: CceColors.textTertiary)),
            ),
          )
        else if (_events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CceIcon(CceIcons.history,
                    size: 28, color: CceColors.textTertiary),
                const SizedBox(height: 8),
                const Text('Sin eventos registrados',
                    style: TextStyle(color: CceColors.textTertiary)),
              ],
            ),
          )
        else
          ..._events.map(_buildEventRow),
      ],
    );
  }

  Widget _buildEventRow(EzvizLockEvent ev) {
    final color = _eventColor(ev.kind);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CceColors.stroke)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: CceIcon(_eventIconSvg(ev), size: 18, color: color),
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
                  style: CceText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una métrica (batería / conexión) en card neumórfica chica.
class _Metric extends StatelessWidget {
  final String icon;
  final Color iconColor;
  final String value;
  final String label;
  const _Metric({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: CceColors.surface,
        borderRadius: BorderRadius.circular(CceRadii.control),
      ),
      child: Column(
        children: [
          CceIcon(icon, size: 22, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: CceText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: CceText.section.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
