import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/automation.dart';
import '../models/device.dart';
import '../models/scene.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_switch.dart';
import '../theme/components/status_dot.dart';
import '../utils/icon_resolver.dart';
import '../views/automations/automation_card.dart' show automationIcon, triggerColor;
import '../views/automations/run_automation.dart';
import '../views/dial_switch_screen.dart';
import '../views/lock_screen.dart';
import '../views/sensor_detail_screen.dart';
import '../views/thermometer_screen.dart';
import '../views/light_color_screen.dart';
import '../views/single_button_screen.dart';
import '../views/switch_detail_screen.dart';

/// Row-cards para la sección "Destacados" editable de la home. Todas espejan
/// la anatomía de [ThermostatHomeCard]: CceCard neo > glyph 48 + título/estado
/// + control rápido a la derecha.

// ── Luz destacada: ícono configurado + switch rápido ───────────────────────

class LightHomeCard extends StatelessWidget {
  final DevicesService service;
  final Device device;
  final bool neo;

  const LightHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = true,
    this.trailing,
  });

  /// Override del control derecho (editor de Destacados): reemplaza el switch.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final online = d.state.reachable;
        final on = d.state.on;
        final accent = !online
            ? CceColors.textTertiary
            : (on ? CceColors.warm : CceColors.textSecondary);

        final String sub;
        if (!online) {
          sub = 'Fuera de línea';
        } else if (on && d.supportsBrightness && d.state.bri > 0) {
          sub = 'Encendida · ${(d.state.bri * 100 / 254).round()}%';
        } else {
          sub = on ? 'Encendida' : 'Apagada';
        }

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LightColorScreen(device: d, service: service),
            ));
          },
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 28,
                    color: online && on ? accent : CceColors.neoTextSub,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: IconResolver.widget(
                      d,
                      configuredIcon: service.iconFor(d.id),
                      customIcons: service.customIcons,
                      displayName: service.displayName(d),
                      size: 26,
                      color: online && on ? accent : CceColors.neoTextSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName(d),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusDot(
                          online && on ? accent : CceColors.textTertiary,
                          semanticLabel: sub,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CceText.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else if (online)
                CceSwitch(
                  value: on,
                  accent: CceColors.warm,
                  onChanged: (_) => service.toggleLight(d),
                )
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}

// ── Botón/switch destacado: abre su pantalla; el botón simple dispara ──────

class ButtonHomeCard extends StatefulWidget {
  final DevicesService service;
  final Device device;
  final bool neo;

  const ButtonHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = true,
    this.trailing,
  });

  /// Override del control derecho (editor de Destacados).
  final Widget? trailing;

  @override
  State<ButtonHomeCard> createState() => _ButtonHomeCardState();
}

class _ButtonHomeCardState extends State<ButtonHomeCard> {
  bool _busy = false;

  /// Mismo criterio que SensorTile: botón de 1 tecla = lastKey reportado o
  /// type 'button' (dispara press, NO es un toggle de relé).
  bool _isPressButton(Device d) =>
      d.sensor?.lastKey != null || d.type.toLowerCase().contains('button');

  Widget _screenFor(Device d, DevicesService service) {
    if (d.isMultiButton) return DialSwitchScreen(device: d, service: service);
    if (_isPressButton(d)) {
      return SingleButtonScreen(device: d, service: service);
    }
    return SwitchDetailScreen(device: d, service: service);
  }

  Future<void> _simulateClick(Device d) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final ok = await widget.service.simulateButton(d, key: 0);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo simular el botón')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(widget.device.id) ?? widget.device;
        final online = d.state.reachable;
        final pressButton = _isPressButton(d);
        final String sub;
        if (!online) {
          sub = 'Fuera de línea';
        } else if (d.isMultiButton) {
          sub = 'Switch · ${d.outletCount} botones';
        } else {
          sub = pressButton ? 'Botón' : 'Switch';
        }

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _screenFor(d, service),
            ));
          },
          radius: widget.neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: widget.neo ? CceColors.neoBase : null,
          neo: widget.neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 28,
                    color: online
                        ? CceColors.textSecondary
                        : CceColors.neoTextSub,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: IconResolver.widget(
                      d,
                      configuredIcon: service.iconFor(d.id),
                      customIcons: service.customIcons,
                      displayName: service.displayName(d),
                      size: 26,
                      color: online
                          ? CceColors.textSecondary
                          : CceColors.neoTextSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName(d),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botón simple online → ▶ dispara el click configurado. Dial/
              // switch → chevron (elegir la tecla es de su pantalla).
              if (widget.trailing != null)
                widget.trailing!
              else if (online && pressButton && !d.isMultiButton)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: _busy
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CceColors.textSecondary),
                          ),
                        )
                      : IconButton(
                          onPressed: () => _simulateClick(d),
                          icon: CceIcon(CceIcons.play,
                              size: 20, color: CceColors.textSecondary),
                          tooltip: 'Disparar click',
                        ),
                )
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}

// ── Cerradura destacada: estado trabada/destrabada ────────────────────────

class LockHomeCard extends StatelessWidget {
  final DevicesService service;
  final Device device;
  final bool neo;

  const LockHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = true,
    this.trailing,
  });

  /// Override del control derecho (editor de Destacados: − / +).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final online = d.state.reachable;
        // Convención del provider: state.on = trabada.
        final locked = d.state.on;
        final accent = !online
            ? CceColors.textTertiary
            : (locked ? CceColors.ok : const Color(0xFFFF9F0A));
        final sub = !online
            ? 'Fuera de línea'
            : (locked ? 'Trabada' : 'Destrabada');

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LockScreen(device: d, service: service),
            ));
          },
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 28,
                    color: online ? accent : CceColors.neoTextSub,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: CceIcon(
                      locked ? CceIcons.lockLocked : CceIcons.lockUnlocked,
                      size: 26,
                      color: online ? accent : CceColors.neoTextSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName(d),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusDot(
                          online ? accent : CceColors.textTertiary,
                          // Destrabada pulsa: es el estado que pide atención.
                          pulse: online && !locked,
                          semanticLabel: sub,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CceText.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Sin acción rápida: destrabar es sensible y vive en su pantalla
              // (con hold-to-confirm).
              trailing ??
                  const Icon(Icons.chevron_right,
                      color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}

// ── Sensor destacado: movimiento / abertura / termómetro ──────────────────

class SensorHomeCard extends StatelessWidget {
  final DevicesService service;
  final Device device;
  final bool neo;

  const SensorHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = true,
    this.trailing,
  });

  /// Override del control derecho (editor de Destacados: − / +).
  final Widget? trailing;

  /// Estado legible + acento por tipo de sensor.
  ({String label, Color color, String glyph, bool alert}) _read(Device d) {
    final s = d.sensor;
    if (d.isMotionSensor) {
      final active = s?.motion ?? false;
      return (
        label: active ? 'Movimiento' : 'Sin movimiento',
        color: active ? CceColors.motion : CceColors.textSecondary,
        glyph: active ? CceIcons.personStanding : CceIcons.footprints,
        alert: active,
      );
    }
    if (d.isContactSensor) {
      final open = s?.contact ?? false;
      return (
        label: open ? 'Abierta' : 'Cerrada',
        color: open ? CceColors.contact : CceColors.textSecondary,
        glyph: open ? CceIcons.doorOpen : CceIcons.doorClosed,
        alert: open,
      );
    }
    // Termómetro / sensor genérico.
    final t = s?.temperature;
    final h = s?.humidity;
    final parts = [
      if (t != null) '${t.toStringAsFixed(1)}°',
      if (h != null) '${h.round()}%',
    ];
    return (
      label: parts.isEmpty ? 'Sin lectura' : parts.join(' · '),
      color: t != null ? CceColors.warm : CceColors.textSecondary,
      glyph: CceIcons.thermometer,
      alert: false,
    );
  }

  bool _isThermometer(Device d) =>
      !d.isMotionSensor &&
      !d.isContactSensor &&
      (d.sensor?.temperature != null || d.sensor?.humidity != null);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final online = d.state.reachable;
        final r = _read(d);
        final accent = online ? r.color : CceColors.textTertiary;

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _isThermometer(d)
                  ? ThermometerScreen(device: d, service: service)
                  : SensorDetailScreen(device: d, service: service),
            ));
          },
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 28,
                    color: online && r.alert ? accent : CceColors.neoTextSub,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: CceIcon(r.glyph,
                        size: 26,
                        color:
                            online && r.alert ? accent : CceColors.neoTextSub),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName(d),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusDot(
                          online ? accent : CceColors.textTertiary,
                          pulse: online && r.alert,
                          semanticLabel: r.label,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            online ? r.label : 'Fuera de línea',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CceText.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const Icon(Icons.chevron_right,
                      color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}

// ── Escena destacada (CCE o Hue): sparkles/swatch + botón aplicar ──────────

class SceneHomeCard extends StatefulWidget {
  final DevicesService service;

  /// Exactamente una de las dos.
  final CceScene? scene;
  final HueScene? hueScene;
  final bool neo;

  const SceneHomeCard({
    super.key,
    required this.service,
    this.scene,
    this.hueScene,
    this.neo = true,
    this.trailing,
  }) : assert((scene != null) ^ (hueScene != null),
            'SceneHomeCard: pasar scene O hueScene');

  /// Override del control derecho (editor de Destacados): reemplaza el ▶.
  final Widget? trailing;

  @override
  State<SceneHomeCard> createState() => _SceneHomeCardState();
}

class _SceneHomeCardState extends State<SceneHomeCard> {
  bool _busy = false;

  Future<void> _apply() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      if (widget.scene != null) {
        await widget.service.applyScene(widget.scene!);
      } else {
        await widget.service.recallHueScene(widget.hueScene!);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.scene?.name ?? widget.hueScene!.name;
    final sub = widget.scene != null
        ? '${widget.scene!.lights.length} luces'
        : 'Escena Hue${widget.hueScene!.roomName != null ? ' · ${widget.hueScene!.roomName}' : ''}';
    final accent = widget.hueScene?.swatch.isNotEmpty == true
        ? widget.hueScene!.swatch.first
        : CceColors.accent;

    return CceCard(
      onTap: _apply,
      radius: widget.neo ? CceRadii.hueCard : CceRadii.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: widget.neo ? CceColors.neoBase : null,
      neo: widget.neo,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: EmbossedGlyph(
                size: 28,
                color: accent,
                highlight: CceEmboss.highlight.color,
                shadow: CceEmboss.shadow.color,
                child: CceIcon(CceIcons.scenes, size: 26, color: accent),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.title.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Aplicar: mismo look que el ▶ compacto de automatizaciones.
          if (widget.trailing != null)
            widget.trailing!
          else
          SizedBox(
            width: 44,
            height: 44,
            child: _busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: CceColors.textSecondary),
                    ),
                  )
                : IconButton(
                    onPressed: _apply,
                    icon: CceIcon(CceIcons.play,
                        size: 20, color: CceColors.textSecondary),
                    tooltip: 'Aplicar escena',
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Automatización destacada: ícono de trigger + ejecutar ──────────────────

class AutomationHomeCard extends StatelessWidget {
  final AutomationsService service;
  final DevicesService devices;
  final Automation automation;
  final bool neo;

  const AutomationHomeCard({
    super.key,
    required this.service,
    required this.devices,
    required this.automation,
    this.neo = true,
    this.trailing,
  });

  /// Override del control derecho (editor de Destacados): reemplaza el ▶.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        // Reresolución por id: el objeto del padre puede quedar stale.
        final a = service.automations
                .where((x) => x.id == automation.id)
                .firstOrNull ??
            automation;
        final color = triggerColor(a);
        final String sub = switch (a.trigger.type) {
          'schedule' => 'Automatización · horario',
          'sensor' => 'Automatización · sensor',
          _ => 'Automatización manual',
        };

        return CceCard(
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 28,
                    color: a.enabled ? color : CceColors.neoTextSub,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: automationIcon(a.icon,
                        size: 26,
                        color: a.enabled ? color : CceColors.neoTextSub),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusDot(
                          a.enabled ? color : CceColors.textTertiary,
                          semanticLabel: a.enabled ? 'Activa' : 'Desactivada',
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            a.enabled ? sub : '$sub · desactivada',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CceText.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else
                RunAutomationButton(
                    automation: a, service: service, compact: true),
            ],
          ),
        );
      },
    );
  }
}
