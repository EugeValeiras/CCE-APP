import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../views/thermostat_screen.dart';

/// Header de termostato para [RoomDetailScreen]: vive arriba del contenido,
/// junto al lector de temperatura. Lenguaje visual de [TemperatureSummaryCard]
/// (CceCard neo, padding/altura compacta): glifo de modo (llama/copo según
/// systemMode), temperatura ambiente grande y setpoint con botones - / +
/// (paso 0.5 °C, clamp [minTemp,maxTemp]). Tap en el cuerpo → [ThermostatScreen].
class ThermostatHeaderCard extends StatelessWidget {
  final Device device;
  final DevicesService service;

  /// OPT-IN: relieve neumórfico (igual que el resto del header). Default false.
  final bool neo;

  /// Override de apertura: en la TABLET el control se abre INLINE en el panel
  /// derecho (igual que TV/JBL) en vez de empujar una ruta fullscreen. Si es
  /// null (teléfono), cae al `Navigator.push(ThermostatScreen)` de siempre.
  final VoidCallback? onOpen;

  /// Long-press: abre el selector de qué mostrar en el header de clima.
  final VoidCallback? onLongPress;

  const ThermostatHeaderCard({
    super.key,
    required this.device,
    required this.service,
    this.neo = false,
    this.onOpen,
    this.onLongPress,
  });

  bool _isCool(DeviceState s) {
    final m = (s.systemMode ?? '').toLowerCase();
    return m.contains('cool') || m.contains('frio') || m.contains('frío');
  }

  Future<void> _step(double delta) async {
    final s = device.state;
    final min = s.minTemp ?? 5;
    final max = s.maxTemp ?? 45;
    final base = s.targetTemp ?? min;
    final next = (base + delta).clamp(min, max).toDouble();
    if (next == base) return;
    HapticFeedback.selectionClick();
    await service.setTargetTemp(device, next);
  }

  @override
  Widget build(BuildContext context) {
    final s = device.state;
    final cool = _isCool(s);
    final on = s.on;
    final Color color =
        on ? (cool ? CceColors.info : CceColors.warm) : CceColors.textSecondary;
    final String svg = cool ? CceIcons.snowflake : CceIcons.flame;

    final current = s.currentTemp;
    final target = s.targetTemp;
    final min = s.minTemp ?? 5;
    final max = s.maxTemp ?? 45;
    final canDown = !on || target == null ? false : target > min;
    final canUp = !on || target == null ? false : target < max;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CceCard(
        // En neo iguala el radio de TemperatureSummaryCard (hueCard 24) para
        // que ambas placas del header se lean del mismo material; en plano
        // conserva el default (28).
        radius: neo ? CceRadii.hueCard : CceRadii.card,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        border: !neo,
        color: neo ? CceColors.neoBase : CceColors.surface,
        neo: neo,
        onLongPress: onLongPress,
        onTap: onOpen ??
            () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ThermostatScreen(device: device, service: service),
                  ),
                ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Glifo de modo + temperatura ambiente grande.
            CceIcon(svg, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.displayName(device),
                    overflow: TextOverflow.ellipsis,
                    style: CceText.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        current != null ? current.toStringAsFixed(1) : '—',
                        style: CceText.display.copyWith(
                          fontSize: 30,
                          height: 1.0,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '°C',
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Setpoint + botones - / +.
            _StepButton(
              icon: CceIcons.minus,
              onTap: canDown ? () => _step(-0.5) : null,
            ),
            Container(
              width: 64,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    target != null ? '${target.toStringAsFixed(1)}°' : '—',
                    style: TextStyle(
                      color: on ? color : CceColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    'Objetivo',
                    style: CceText.caption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: CceIcons.plus,
              onTap: canUp ? () => _step(0.5) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón de paso de temperatura: SOLO el glifo − / + en RELIEVE (embossed,
/// como goma que sobresale de la pantalla), SIN círculo/contenedor de fondo ni
/// borde. El glifo flota; el área táctil (≥40px) se mantiene con padding y un
/// HitTestBehavior.opaque que captura el tap en todo el cuadro. Deshabilitado =
/// glifo atenuado.
class _StepButton extends StatelessWidget {
  /// SVG del glifo ([CceIcons.minus] / [CceIcons.plus]).
  final String icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Padding → área táctil ≥40px (glifo 22 + 9*2) sin fondo visible.
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: CceIcon(
          icon,
          size: 22,
          color: enabled ? CceColors.textPrimary : CceColors.textTertiary,
          // Relieve embossed (default true): el glifo sobresale de la pantalla.
        ),
      ),
    );
  }
}
