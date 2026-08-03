import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../utils/button_events.dart';
import '../widgets/device_automations_sheet.dart';
import '../widgets/device_state_panel.dart';
import '../widgets/event_history_section.dart';

/// Pantalla de un device de UN solo botón (eWeLink Button y similares).
///
/// Mismo molde que SensorDetailScreen/LockScreen: el botón grande sigue siendo
/// el protagonista (tocar = click, doble tap = doble, mantener = long-press,
/// todo vía simulateButton) pero ahora la pantalla también CUENTA el estado —
/// última pulsación, batería, conexión — e incluye el HISTORIAL real de
/// pulsaciones con la automatización que disparó cada una.
class SingleButtonScreen extends StatefulWidget {
  final Device device;
  final DevicesService service;
  const SingleButtonScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  State<SingleButtonScreen> createState() => _SingleButtonScreenState();
}

class _SingleButtonScreenState extends State<SingleButtonScreen> {
  /// Último evento del historial. Sirve de respaldo para la métrica "ÚLTIMA"
  /// cuando el proveedor no manda trigTime (Hue no lo manda; eWeLink sí).
  DateTime? _lastFromHistory;

  /// Se crea acá para no cambiar la firma de la pantalla ni sus call sites.
  AutomationsService? _autos;
  AutomationsService get autos => _autos ??= AutomationsService(
    config: widget.service.config,
    devices: widget.service,
  );

  int get _autoCount {
    final ids = <String>{widget.device.id, ...widget.device.bindingIds};
    return autos.automations
        .where(
          (a) => a.trigger.sensorTriggers.any((t) => ids.contains(t.sensorId)),
        )
        .length;
  }

  void _openAutomations() {
    DeviceAutomationsSheet.show(
      context,
      device: widget.device,
      devices: widget.service,
      automations: autos,
    );
  }

  bool _pressed = false; // feedback visual (hundido)
  String? _feedback; // 'Click' / 'Doble click' / 'Mantenido'
  Timer? _flashTimer;
  Timer? _fbTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _fbTimer?.cancel();
    super.dispose();
  }

  Device get _device => widget.service.byId(widget.device.id) ?? widget.device;

  /// Hundido instantáneo al apoyar el dedo (no espera al backend).
  void _flash() {
    setState(() => _pressed = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  Future<void> _press(int key) async {
    HapticFeedback.mediumImpact();
    setState(() => _feedback = pressKindLabel(key));
    _fbTimer?.cancel();
    _fbTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _feedback = null);
    });
    final ok = await widget.service.simulateButton(
      widget.device,
      key: key,
      outlet: 0,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo accionar el botón')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) {
            final d = _device;
            final sensor = d.sensor;
            final lastKey = sensor?.lastKey;
            // Mientras hay feedback local mostramos ESO (respuesta inmediata);
            // si no, la última pulsación reportada por el device.
            final live = _feedback != null;
            final label =
                _feedback ??
                (lastKey != null ? pressKindLabel(lastKey) : 'Tocá el botón');

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeviceStatePanel(
                    label: label,
                    sublabel: widget.service.displayName(d),
                    accent: live || lastKey != null
                        ? CceColors.warm
                        : CceColors.textTertiary,
                    glowing: live,
                    child: _button(),
                  ),
                  const SizedBox(height: 22),
                  DeviceMetricsRow(
                    metrics: [
                      DeviceMetric(
                        svg: CceIcons.batteryFull,
                        iconColor: DeviceMetric.batteryColor(sensor?.battery),
                        value: sensor?.battery != null
                            ? '${sensor!.battery}%'
                            : '—',
                        label: 'BATERÍA',
                      ),
                      DeviceMetric(
                        svg: CceIcons.clock,
                        iconColor: CceColors.textSecondary,
                        value: lastPressValue(
                          sensor?.trigTime,
                          fallback: _lastFromHistory,
                        ),
                        label: 'ÚLTIMA',
                      ),
                      DeviceMetric(
                        svg: CceIcons.sensors,
                        iconColor: d.state.reachable
                            ? CceColors.ok
                            : CceColors.textTertiary,
                        value: d.state.reachable ? 'En línea' : 'Sin señal',
                        label: 'ESTADO',
                      ),
                      DeviceMetric(
                        svg: CceIcons.automations,
                        iconColor: CceColors.textSecondary,
                        value: '$_autoCount',
                        label: 'AUTOMATIZ.',
                        onTap: _openAutomations,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  EventHistorySection(
                    onLoaded: (at) {
                      if (mounted && at != _lastFromHistory) {
                        setState(() => _lastFromHistory = at);
                      }
                    },
                    service: widget.service,
                    historyId: historyIdOf(d),
                    emptyLabel: 'Sin pulsaciones registradas',
                    builder: (events) => buttonHistoryEntries(
                      events,
                      service: widget.service,
                      outletCount: 1,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DeviceWordmark('CCE BUTTON'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// El botón: disco elevado dentro de un "pozo" circular hundido. Se hunde con
  /// glow cálido al tocar. Acotado a 200 (antes 300) para convivir con el resto
  /// de la pantalla sin empujar el historial fuera de vista.
  Widget _button() {
    const well = 200.0;
    return Container(
      width: well,
      height: well,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CceColors.neoBase,
        boxShadow: [
          ...CceShadows.neoInset(blur: 20, offset: 8, intensity: 1.2),
          BoxShadow(
            color: CceColors.warm.withValues(alpha: _pressed ? 0.22 : 0.10),
            blurRadius: 40,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _flash(),
        onTap: () => _press(0),
        onDoubleTap: () => _press(1),
        onLongPress: () => _press(2),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          scale: _pressed ? 0.95 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              // Reposo = disco ELEVADO; pulsado = HUNDIDO profundo + glow.
              boxShadow: _pressed
                  ? CceShadows.neoInset(blur: 14, offset: 6, intensity: 1.2)
                  : CceShadows.neo(blur: 18, offset: 9, intensity: 1.1),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _pressed ? CceColors.warm : CceColors.neoTextSub,
                  shape: BoxShape.circle,
                  boxShadow: _pressed
                      ? [
                          BoxShadow(
                            color: CceColors.warm.withValues(alpha: 0.6),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
