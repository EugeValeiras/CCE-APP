import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/cce_segmented.dart';
import '../theme/components/cce_switch.dart';

/// Pantalla de control de un termostato (Tuya cat 'wk'). Estilo neumórfico
/// alineado con el control de luz: temp actual grande, setpoint editable con
/// +/- (paso 0.5 °C, clamp [minTemp,maxTemp]), power toggle y modo Manual /
/// Program. Todos los íconos salen de icons0.dev ([CceIcons]).
class ThermostatScreen extends StatelessWidget {
  final Device device;
  final DevicesService service;
  const ThermostatScreen({
    super.key,
    required this.device,
    required this.service,
  });

  /// Acento por modo de sistema: calor → cálido/llama, frío → frío/copo.
  Color _accentFor(DeviceState s) {
    final mode = (s.systemMode ?? '').toLowerCase();
    if (mode.contains('cool') || mode.contains('frio') || mode.contains('frío')) {
      return CceColors.info;
    }
    return CceColors.warm;
  }

  /// Glifo del modo de sistema (llama / copo) desde icons0.dev.
  String _modeIconFor(DeviceState s) {
    final mode = (s.systemMode ?? '').toLowerCase();
    if (mode.contains('cool') || mode.contains('frio') || mode.contains('frío')) {
      return CceIcons.snowflake;
    }
    return CceIcons.flame;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(service.displayName(device), style: CceText.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: CceColors.textSecondary),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final d = service.byId(device.id) ?? device;
          final s = d.state;
          final on = s.on;
          final reachable = s.reachable;
          final accent = on ? _accentFor(s) : CceColors.textTertiary;
          final target = s.targetTemp;
          final current = s.currentTemp;

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              // ── Power + estado ───────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: on
                          ? accent.withValues(alpha: 0.18)
                          : CceColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(CceRadii.control),
                      border: Border.all(
                        color: on ? accent : CceColors.stroke,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: CceIcon(
                      _modeIconFor(s),
                      size: 30,
                      color: on ? accent : CceColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !reachable
                              ? 'Sin conexión'
                              : (on ? 'Encendido' : 'Apagado'),
                          style: CceText.title,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d.type,
                          style: CceText.caption.copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  CceSwitch(
                    value: on,
                    onChanged: reachable
                        ? (v) {
                            HapticFeedback.selectionClick();
                            service.setThermostatPower(d, v);
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Temperatura actual ───────────────────────────────────────
              if (current != null) ...[
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CceIcon(
                        CceIcons.thermometer,
                        size: 18,
                        color: CceColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Ambiente ${current.toStringAsFixed(1)}°',
                        style: CceText.caption.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Setpoint editable (+ / -) ────────────────────────────────
              _SectionLabel(
                'Objetivo',
                trailing: (s.minTemp != null && s.maxTemp != null)
                    ? '${s.minTemp!.toStringAsFixed(0)}° – ${s.maxTemp!.toStringAsFixed(0)}°'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CceNeoSvgIconButton(
                    svg: CceIcons.minus,
                    size: 56,
                    iconColor: accent,
                    onPressed: (reachable && target != null)
                        ? () {
                            HapticFeedback.selectionClick();
                            service.setTargetTemp(d, target - 0.5);
                          }
                        : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        target != null ? '${target.toStringAsFixed(1)}°' : '—',
                        style: CceText.display.copyWith(
                          fontSize: 56,
                          color: reachable ? accent : CceColors.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  CceNeoSvgIconButton(
                    svg: CceIcons.plus,
                    size: 56,
                    iconColor: accent,
                    onPressed: (reachable && target != null)
                        ? () {
                            HapticFeedback.selectionClick();
                            service.setTargetTemp(d, target + 0.5);
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Modo (Manual / Program) ──────────────────────────────────
              if (s.tempMode != null) ...[
                const _SectionLabel('Modo'),
                const SizedBox(height: 12),
                CceSegmented<String>(
                  value: _normalizeMode(s.tempMode!),
                  segments: const [
                    CceSegment(value: 'Manual', label: 'Manual'),
                    CceSegment(value: 'Program', label: 'Programa'),
                  ],
                  onChanged: reachable
                      ? (m) {
                          HapticFeedback.selectionClick();
                          service.setTempMode(d, m);
                        }
                      : (_) {},
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Normaliza el tempMode reportado al value del segmented (Manual/Program).
  static String _normalizeMode(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('program') || m.contains('auto')) return 'Program';
    return 'Manual';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const _SectionLabel(this.text, {this.trailing});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text.toUpperCase(), style: CceText.section),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: CceColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
