import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/capability.dart';
import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_switch.dart';
import '../utils/capability_renderers.dart';
import '../utils/contact_words.dart';
import '../widgets/detach_tile.dart';
import '../utils/enum_options.dart';
import '../utils/verb_labels.dart';

/// Vista unificada por capabilities: renderiza los controles de CUALQUIER
/// device a partir de `device.capabilities` + el catálogo (GET /api/capabilities),
/// iterando `capabilityRenderersFor`. Coexiste con las pantallas dedicadas
/// (no las reemplaza). Respeta las escalas trampa: brillo 1-254 (nunca 0), ct
/// mireds 153-500, volumen 0-100; clamp en el cliente; guard del `on` polisémico.
class UnifiedDeviceScreen extends StatefulWidget {
  const UnifiedDeviceScreen({
    super.key,
    required this.device,
    required this.service,
  });

  final Device device;
  final DevicesService service;

  @override
  State<UnifiedDeviceScreen> createState() => _UnifiedDeviceScreenState();
}

class _UnifiedDeviceScreenState extends State<UnifiedDeviceScreen> {
  // Overrides optimistas para verbos (el estado real llega por WS/poll).
  int? _volumeOverride;
  bool? _mutedOverride;
  Timer? _clearOverrides;
  bool _unlocking = false;

  @override
  void dispose() {
    _clearOverrides?.cancel();
    super.dispose();
  }

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  void _scheduleClear() {
    _clearOverrides?.cancel();
    _clearOverrides = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() {
        _volumeOverride = null;
        _mutedOverride = null;
      });
    });
  }

  Future<void> _invoke(String verb, [Map<String, dynamic>? args]) async {
    HapticFeedback.selectionClick();
    try {
      await widget.service.invokeCapability(_device, verb, args);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_humanizeError(e))),
        );
      }
    }
  }

  String _humanizeError(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final d = _device;
        final entries = capabilityRenderersFor(d.capabilities);
        return Scaffold(
          backgroundColor: CceColors.bg,
          appBar: AppBar(
            backgroundColor: CceColors.bg,
            title: Text(widget.service.displayName(d)),
            elevation: 0,
          ),
          body: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Este dispositivo no tiene controles genéricos disponibles.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: CceColors.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (d.state.reachable == false)
                      _card(const _OfflineBanner()),
                    for (final e in entries) _renderEntry(d, e),
                  ],
                ),
        );
      },
    );
  }

  Widget _renderEntry(Device d, CapabilityRendererEntry e) {
    final spec = widget.service.capabilityCatalog.specFor(e.capability);
    switch (e.kind) {
      case CapabilityRendererKind.onoff:
        return _card(_onoff(d));
      case CapabilityRendererKind.brightness:
        return _card(_brightness(d));
      case CapabilityRendererKind.colorTemperature:
        return _card(_colorTemp(d));
      case CapabilityRendererKind.volume:
        return _card(_volume(d));
      case CapabilityRendererKind.thermostat:
        return _card(_thermostat(d));
      case CapabilityRendererKind.lock:
        return _card(_lock(d));
      case CapabilityRendererKind.sensor:
        return _card(_sensor(d));
      case CapabilityRendererKind.detach:
        // DetachTile trae su propia card y su propio estado optimista.
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DetachTile(device: d, service: widget.service),
        );
      case CapabilityRendererKind.vacuum:
      case CapabilityRendererKind.vacuumRooms:
      case CapabilityRendererKind.soundMode:
      case CapabilityRendererKind.mediaPlayback:
      case CapabilityRendererKind.inputSelect:
      case CapabilityRendererKind.appLauncher:
      case CapabilityRendererKind.channel:
      // CCE#100 — modo y escenas de la luz: chips de verbo, igual que los modos
      // de limpieza del robot. Las opciones salen del ESTADO del device, no del
      // catálogo (que las manda vacías a propósito).
      case CapabilityRendererKind.lightMode:
      case CapabilityRendererKind.scene:
        return _verbs(d, e, spec);
      case CapabilityRendererKind.colorHsv:
      case CapabilityRendererKind.alarm:
      case CapabilityRendererKind.button:
      case CapabilityRendererKind.dial:
        // Kinds con pantalla dedicada rica: un aviso suave (no rompen la vista).
        return _card(_bespokeHint(e.kind));
    }
  }

  // ── Wrappers de UI ──────────────────────────────────────────────────────

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CceColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CceColors.stroke),
        ),
        child: child,
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CceColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
      );

  // ── Renderers de estado (PUT /state) ────────────────────────────────────

  // Que el toggle diga lo que hace: en el área MotionAware de Hue `on` no
  // enciende ninguna luz, prende y apaga la detección del área (CCE#96).
  Widget _onoff(Device d) => Row(
        children: [
          Expanded(
            child: Text(d.isHueMotionArea ? 'MotionAware' : 'Encendido',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CceColors.textPrimary)),
          ),
          CceSwitch(
            value: d.state.on,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              widget.service.applyCapabilityState(
                d, d.state.copyWith(on: v), {'on': v});
            },
          ),
        ],
      );

  Widget _brightness(Device d) {
    final pct = (d.state.bri.clamp(1, 254)) / 254.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Brillo'),
        _PlainSlider(
          value: pct,
          min: 0,
          max: 1,
          activeColor: CceColors.warm,
          onChangeEnd: (v) {
            // Brillo NUNCA 0 (apagar es on:false). Clamp 1-254.
            final bri = (v * 254).round().clamp(1, 254);
            widget.service.applyCapabilityState(
              d, d.state.copyWith(bri: bri, on: true), {'bri': bri, 'on': true});
          },
        ),
      ],
    );
  }

  Widget _colorTemp(Device d) {
    // Mireds 153 (frío) → 500 (cálido).
    final ct = (d.state.ct ?? 300).clamp(153, 500).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Temperatura de color'),
        _PlainSlider(
          value: ct,
          min: 153,
          max: 500,
          activeColor: const Color(0xFFFFC766),
          onChangeEnd: (v) {
            final mireds = v.round().clamp(153, 500);
            widget.service.applyCapabilityState(
              d, d.state.copyWith(ct: mireds, on: true), {'ct': mireds, 'on': true});
          },
        ),
      ],
    );
  }

  Widget _volume(Device d) {
    final vol = _volumeOverride ?? (d.state.volume ?? 0);
    final muted = _mutedOverride ?? (d.state.muted ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _label('Volumen  ·  $vol')),
            IconButton(
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
                  color: muted ? CceColors.danger : CceColors.textSecondary),
              onPressed: () {
                final next = !muted;
                setState(() => _mutedOverride = next);
                _scheduleClear();
                _invoke('mute', {'muted': next});
              },
            ),
          ],
        ),
        _PlainSlider(
          value: vol.toDouble(),
          min: 0,
          max: 100,
          activeColor: CceColors.info,
          onChanged: (v) => setState(() => _volumeOverride = v.round()),
          onChangeEnd: (v) {
            final level = v.round().clamp(0, 100); // volumen SIEMPRE 0-100
            setState(() => _volumeOverride = level);
            _scheduleClear();
            _invoke('setVolume', {'volume': level});
          },
        ),
      ],
    );
  }

  Widget _thermostat(Device d) {
    final target = d.state.targetTemp;
    final min = d.state.minTemp ?? 5;
    final max = d.state.maxTemp ?? 35;
    void bump(double delta) {
      final base = target ?? 21.0;
      final next = (base + delta).clamp(min, max).toDouble();
      widget.service.applyCapabilityState(
        d, d.state.copyWith(targetTemp: next), {'targetTemp': next});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Termostato'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundBtn(icon: Icons.remove, onTap: () => bump(-0.5)),
            Column(
              children: [
                Text(
                  target != null ? '${target.toStringAsFixed(1)}°' : '--',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: CceColors.textPrimary),
                ),
                if (d.state.currentTemp != null)
                  Text('actual ${d.state.currentTemp!.toStringAsFixed(1)}°',
                      style: const TextStyle(
                          fontSize: 12, color: CceColors.textTertiary)),
              ],
            ),
            _RoundBtn(icon: Icons.add, onTap: () => bump(0.5)),
          ],
        ),
      ],
    );
  }

  // ── Lock (POST /actions/unlock, sensitive) ──────────────────────────────

  Widget _lock(Device d) {
    final locked = d.state.on; // lock: on = trabada
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Cerradura'),
        Row(
          children: [
            Icon(locked ? Icons.lock : Icons.lock_open,
                color: locked ? CceColors.ok : CceColors.warm),
            const SizedBox(width: 8),
            Text(locked ? 'Trabada' : 'Destrabada',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CceColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 12),
        // Hold-to-confirm: el tap corto no destraba; exige mantener apretado.
        GestureDetector(
          onLongPress: _unlocking ? null : () => _doUnlock(d),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CceColors.warm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_unlocking)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.lock_open, size: 18, color: CceColors.warm),
                const SizedBox(width: 8),
                Text(_unlocking ? 'Destrabando…' : 'Mantené para destrabar',
                    style: const TextStyle(
                        color: CceColors.warm, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _doUnlock(Device d) async {
    setState(() => _unlocking = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.service.invokeCapability(d, 'unlock', {'confirm': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_humanizeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  // ── Sensores (read-only) ─────────────────────────────────────────────────

  Widget _sensor(Device d) {
    final s = d.sensor;
    final rows = <Widget>[];
    void add(String k, String v) => rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: const TextStyle(color: CceColors.textTertiary)),
              Text(v,
                  style: const TextStyle(
                      color: CceColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ));
    if (s != null) {
      if (s.temperature != null) add('Temperatura', '${s.temperature!.toStringAsFixed(1)}°');
      if (s.humidity != null) add('Humedad', '${s.humidity!.toStringAsFixed(0)}%');
      // CCE#112 — el lux numérico de los SNZB-03PR2.
      if (s.lux != null) add('Luz', '${s.lux} lx');
      if (s.motion != null) add('Movimiento', s.motion! ? 'Detectado' : 'Sin movimiento');
      // CCE#115 — `contact: true` es ABIERTA (esta fila decía lo contrario).
      // El rótulo es «Apertura» y no «Contacto» para que concuerde con la
      // palabra que usa el resto de la App (y con la sección «Aperturas»).
      if (s.contact != null) add('Apertura', ContactWords.label(s.contact!));
      if (s.battery != null) add('Batería', s.battery!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Sensor'),
        if (rows.isEmpty)
          const Text('Sin lecturas disponibles',
              style: TextStyle(color: CceColors.textTertiary))
        else
          ...rows,
      ],
    );
  }

  // ── Verbos genéricos (POST /actions/:verb), data-driven del catálogo ─────

  Widget _verbs(Device d, CapabilityRendererEntry e, CapabilitySpec? spec) {
    if (spec == null || spec.actions.isEmpty) {
      return _card(_bespokeHint(e.kind));
    }
    final controls = <Widget>[];
    for (final a in spec.actions) {
      if (a.isSensitive) continue; // sensitive (p.ej. unlock) no en genérico
      final w = _verbControl(d, a);
      if (w != null) controls.add(w);
    }
    if (controls.isEmpty) return _card(_bespokeHint(e.kind));
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(_kindTitle(e.kind)),
        Wrap(spacing: 8, runSpacing: 8, children: controls),
      ],
    ));
  }

  /// Un control para una acción del catálogo: sin args → botón; 1 arg bool →
  /// toggle chip; 1 arg enum resoluble → chips; 1 arg number → slider. Multi-arg
  /// o enum sin opciones → se omite (lo cubren las pantallas dedicadas).
  Widget? _verbControl(Device d, CatalogActionSpec a) {
    if (a.args.isEmpty) {
      return _ActionChip(label: _verbLabel(a.verb), onTap: () => _invoke(a.verb));
    }
    if (a.args.length == 1) {
      final arg = a.args.first;
      if (arg.type == 'boolean') {
        return _ActionChip(
          label: _verbLabel(a.verb),
          onTap: () => _invoke(a.verb, {arg.name: true}),
        );
      }
      if (arg.enumRef != null) {
        final opts = _resolveEnum(arg.enumRef!, d);
        if (opts.isEmpty) return null;
        // Cuál está PUESTO ahora: sale de `affects` del catálogo (setMode
        // afecta `mode`, setScene afecta `sceneId`), así que no hace falta un
        // if por verbo. Marcar el activo es lo que convierte los chips en un
        // selector y no en una fila de botones.
        final actual = _currentEnumValue(a, d);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_verbLabel(a.verb),
                style: const TextStyle(
                    fontSize: 12, color: CceColors.textTertiary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in opts)
                  _ActionChip(
                    label: o.label,
                    selected: o.value == actual,
                    onTap: () => _invoke(a.verb, {arg.name: o.value}),
                  ),
              ],
            ),
          ],
        );
      }
      if (arg.type == 'number' && arg.min != null && arg.max != null) {
        return _NumberVerb(
          label: _verbLabel(a.verb),
          min: arg.min!.toDouble(),
          max: arg.max!.toDouble(),
          onCommit: (v) => _invoke(a.verb, {arg.name: v.round()}),
        );
      }
    }
    return null; // multi-arg / no resoluble → omitido
  }

  /// Las opciones de un enum del catálogo, con su valor y su etiqueta
  /// separados. La lógica vive en `utils/enum_options.dart`, compartida con el
  /// sheet de acciones de las automatizaciones.
  List<EnumOption> _resolveEnum(String ref, Device d) => resolveEnumOptions(
        ref,
        d.state,
        widget.service.capabilityCatalog.enumValues,
      );

  /// El valor vigente del enum de una acción, leído del campo que declara
  /// afectar (`affects`). null si el device no lo reporta.
  String? _currentEnumValue(CatalogActionSpec a, Device d) {
    for (final field in a.affects) {
      switch (field) {
        case 'mode':
          if (d.state.mode != null) return d.state.mode;
        case 'sceneId':
          if (d.state.sceneId != null) return d.state.sceneId;
        case 'cleanMode':
          if (d.state.cleanMode != null) return d.state.cleanMode;
        case 'fanSpeed':
          if (d.state.fanSpeed != null) return d.state.fanSpeed;
        case 'mediaInput':
          if (d.state.mediaInput != null) return d.state.mediaInput;
      }
    }
    return null;
  }

  Widget _bespokeHint(CapabilityRendererKind kind) => Row(
        children: [
          const Icon(Icons.open_in_new, size: 18, color: CceColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_kindTitle(kind)}: usá la pantalla dedicada para el control completo.',
              style: const TextStyle(color: CceColors.textTertiary, fontSize: 13),
            ),
          ),
        ],
      );

  String _kindTitle(CapabilityRendererKind k) {
    switch (k) {
      case CapabilityRendererKind.vacuum:
      case CapabilityRendererKind.vacuumRooms:
        return 'Aspiradora';
      case CapabilityRendererKind.soundMode:
        return 'Modo de sonido';
      case CapabilityRendererKind.mediaPlayback:
        return 'Reproducción';
      case CapabilityRendererKind.inputSelect:
        return 'Entrada';
      case CapabilityRendererKind.appLauncher:
        return 'Apps';
      case CapabilityRendererKind.channel:
        return 'Canal';
      case CapabilityRendererKind.colorHsv:
        return 'Color';
      case CapabilityRendererKind.lightMode:
        return 'Modo de la luz';
      case CapabilityRendererKind.scene:
        return 'Escenas';
      case CapabilityRendererKind.alarm:
        return 'Alarma';
      case CapabilityRendererKind.button:
        return 'Botón';
      case CapabilityRendererKind.dial:
        return 'Rueda';
      default:
        return 'Control';
    }
  }

  String _verbLabel(String verb) => verbLabel(verb);
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────

class _PlainSlider extends StatelessWidget {
  const _PlainSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: activeColor,
        inactiveTrackColor: CceColors.surfaceHigh,
        thumbColor: activeColor,
        overlayColor: activeColor.withValues(alpha: 0.15),
        trackHeight: 6,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged ?? (_) {},
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

class _NumberVerb extends StatefulWidget {
  const _NumberVerb({
    required this.label,
    required this.min,
    required this.max,
    required this.onCommit,
  });
  final String label;
  final double min;
  final double max;
  final ValueChanged<double> onCommit;

  @override
  State<_NumberVerb> createState() => _NumberVerbState();
}

class _NumberVerbState extends State<_NumberVerb> {
  late double _v = widget.min;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.label}  ·  ${_v.round()}',
            style: const TextStyle(fontSize: 12, color: CceColors.textTertiary)),
        _PlainSlider(
          value: _v,
          min: widget.min,
          max: widget.max,
          activeColor: CceColors.info,
          onChanged: (v) => setState(() => _v = v),
          onChangeEnd: widget.onCommit,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;

  /// CCE#100 — marca el valor PUESTO en un enum. Sin esto los chips de un
  /// selector (modo, escena) se ven todos iguales y no se sabe dónde está.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CceColors.accent.withValues(alpha: 0.18) : CceColors.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CceColors.accent),
                )
              : null,
          child: Text(label,
              style: TextStyle(
                  color: selected ? CceColors.accent : CceColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CceColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: CceColors.textPrimary),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) => const Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: CceColors.textTertiary),
          SizedBox(width: 8),
          Text('Sin conexión con el dispositivo',
              style: TextStyle(color: CceColors.textTertiary)),
        ],
      );
}
