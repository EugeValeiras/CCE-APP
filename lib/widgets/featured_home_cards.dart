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
import '../theme/components/featured_tile.dart';
import '../theme/components/status_dot.dart';
import '../utils/contact_words.dart';
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

/// Cards para la sección "Destacados" editable de la home. En la grilla de la
/// home (`tile: true`) todas se renderizan con el molde [FeaturedTile]; como
/// fila (`tile: false`, editor de Destacados) espejan la anatomía de
/// [ThermostatHomeCard]: CceCard neo > glyph 48 + título/estado + control.

/// Fila a todo el ancho compartida por las cards de este archivo.
Widget _row({
  required Widget glyph,
  required Color glyphColor,
  required String title,
  required Widget status,
  required Widget control,
  required VoidCallback? onTap,
  bool neo = true,
}) {
  return CceCard(
    onTap: onTap,
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
              color: glyphColor,
              highlight: CceEmboss.highlight.color,
              shadow: CceEmboss.shadow.color,
              child: glyph,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CceText.title.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 4),
              status,
            ],
          ),
        ),
        const SizedBox(width: 8),
        control,
      ],
    ),
  );
}

/// Línea de estado de la fila: dot opcional + texto.
Widget _status(String text, {Color? dot, bool pulse = false}) {
  return Row(
    children: [
      if (dot != null) ...[
        StatusDot(dot, pulse: pulse, semanticLabel: text),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CceText.caption,
        ),
      ),
    ],
  );
}

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
    this.tile = false,
  });

  /// Override del control derecho (editor de Destacados): reemplaza el switch.
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

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
        final glyphColor = online && on ? accent : CceColors.textTertiary;
        final dotColor = online && on ? accent : CceColors.textTertiary;

        Widget glyph(double size) => IconResolver.widget(
              d,
              configuredIcon: service.iconFor(d.id),
              customIcons: service.customIcons,
              displayName: service.displayName(d),
              size: size,
              color: glyphColor,
            );

        void open() {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LightColorScreen(device: d, service: service),
          ));
        }

        final Widget control = trailing ??
            (online
                ? CceSwitch(
                    value: on,
                    accent: CceColors.warm,
                    onChanged: (_) => service.toggleLight(d),
                  )
                : FeaturedTile.chevron());

        if (tile) {
          return FeaturedTile(
            glyph: glyph(24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: sub,
            dotColor: dotColor,
            control: control,
            onTap: open,
          );
        }
        return _row(
          glyph: glyph(26),
          glyphColor: glyphColor,
          title: service.displayName(d),
          status: _status(sub, dot: dotColor),
          control: control,
          onTap: open,
          neo: neo,
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
    this.tile = false,
  });

  /// Override del control derecho (editor de Destacados).
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

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
        final glyphColor =
            online ? CceColors.textSecondary : CceColors.textTertiary;

        Widget glyph(double size) => IconResolver.widget(
              d,
              configuredIcon: service.iconFor(d.id),
              customIcons: service.customIcons,
              displayName: service.displayName(d),
              size: size,
              color: glyphColor,
            );

        void open() {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _screenFor(d, service),
          ));
        }

        // Botón simple online → ▶ dispara el click configurado. Dial/
        // switch → chevron (elegir la tecla es de su pantalla).
        final canFire = online && pressButton && !d.isMultiButton;

        if (widget.tile) {
          return FeaturedTile(
            glyph: glyph(24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: sub,
            control: widget.trailing ??
                (canFire
                    ? FeaturedTileAction(
                        svg: CceIcons.play,
                        tooltip: 'Disparar click',
                        busy: _busy,
                        onTap: () => _simulateClick(d),
                      )
                    : FeaturedTile.chevron()),
            onTap: open,
          );
        }

        final Widget control;
        if (widget.trailing != null) {
          control = widget.trailing!;
        } else if (canFire) {
          control = SizedBox(
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
                    onPressed: () => _simulateClick(d),
                    icon: CceIcon(CceIcons.play,
                        size: 20, color: CceColors.textSecondary),
                    tooltip: 'Disparar click',
                  ),
          );
        } else {
          control = FeaturedTile.chevron();
        }

        return _row(
          glyph: glyph(26),
          glyphColor: glyphColor,
          title: service.displayName(d),
          status: _status(sub),
          control: control,
          onTap: open,
          neo: widget.neo,
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
    this.tile = false,
  });

  /// Override del control derecho (editor de Destacados: − / +).
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final online = d.state.reachable;
        // Convención del provider: state.on = trabada.
        final locked = d.state.on;
        // Destrabada = apertura: el semántico de "puerta abierta", no un
        // naranja propio.
        final accent = !online
            ? CceColors.textTertiary
            : (locked ? CceColors.ok : CceColors.contact);
        final sub = !online
            ? 'Fuera de línea'
            : (locked ? 'Trabada' : 'Destrabada');
        final glyphColor = online ? accent : CceColors.textTertiary;
        final svg = locked ? CceIcons.lockLocked : CceIcons.lockUnlocked;

        void open() {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LockScreen(device: d, service: service),
          ));
        }

        // Sin acción rápida: destrabar es sensible y vive en su pantalla
        // (con hold-to-confirm).
        final control = trailing ?? FeaturedTile.chevron();

        if (tile) {
          return FeaturedTile(
            glyph: CceIcon(svg, size: 24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: sub,
            dotColor: online ? accent : CceColors.textTertiary,
            // Destrabada pulsa: es el estado que pide atención.
            dotPulse: online && !locked,
            control: control,
            onTap: open,
          );
        }
        return _row(
          glyph: CceIcon(svg, size: 26),
          glyphColor: glyphColor,
          title: service.displayName(d),
          status: _status(sub,
              dot: online ? accent : CceColors.textTertiary,
              pulse: online && !locked),
          control: control,
          onTap: open,
          neo: neo,
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
    this.tile = false,
  });

  /// Override del control derecho (editor de Destacados: − / +).
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

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
        label: ContactWords.label(open),
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
        final glyphColor =
            online && r.alert ? accent : CceColors.textTertiary;
        final label = online ? r.label : 'Fuera de línea';

        void open() {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _isThermometer(d)
                ? ThermometerScreen(device: d, service: service)
                : SensorDetailScreen(device: d, service: service),
          ));
        }

        final control = trailing ?? FeaturedTile.chevron();

        if (tile) {
          return FeaturedTile(
            glyph: CceIcon(r.glyph, size: 24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: label,
            dotColor: online ? accent : CceColors.textTertiary,
            dotPulse: online && r.alert,
            control: control,
            onTap: open,
          );
        }
        return _row(
          glyph: CceIcon(r.glyph, size: 26),
          glyphColor: glyphColor,
          title: service.displayName(d),
          status: _status(label,
              dot: online ? accent : CceColors.textTertiary,
              pulse: online && r.alert),
          control: control,
          onTap: open,
          neo: neo,
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
    this.tile = false,
  }) : assert((scene != null) ^ (hueScene != null),
            'SceneHomeCard: pasar scene O hueScene');

  /// Override del control derecho (editor de Destacados): reemplaza el ▶.
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

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
        // Dispositivos, no luces: una escena heterogénea (Modo Cine) vive en
        // entries[] y con lights.length decía "0 luces" teniendo un device.
        ? widget.scene!.deviceCountLabel
        : 'Escena Hue${widget.hueScene!.roomName != null ? ' · ${widget.hueScene!.roomName}' : ''}';
    final accent = widget.hueScene?.swatch.isNotEmpty == true
        ? widget.hueScene!.swatch.first
        : CceColors.accent;

    if (widget.tile) {
      return FeaturedTile(
        glyph: const CceIcon(CceIcons.scenes, size: 24),
        glyphColor: accent,
        title: name,
        subtitle: sub,
        control: widget.trailing ??
            FeaturedTileAction(
              svg: CceIcons.play,
              tooltip: 'Aplicar escena',
              busy: _busy,
              onTap: _apply,
            ),
        onTap: _apply,
      );
    }

    // Aplicar: mismo look que el ▶ compacto de automatizaciones.
    final Widget control = widget.trailing ??
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
        );
    return _row(
      glyph: const CceIcon(CceIcons.scenes, size: 26),
      glyphColor: accent,
      title: name,
      status: _status(sub),
      control: control,
      onTap: _apply,
      neo: widget.neo,
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
    this.tile = false,
  });

  /// Override del control derecho (editor de Destacados): reemplaza el ▶.
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

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
        final label = a.enabled ? sub : '$sub · desactivada';
        final glyphColor = a.enabled ? color : CceColors.textTertiary;
        final dotColor = a.enabled ? color : CceColors.textTertiary;

        if (tile) {
          return FeaturedTile(
            glyph: automationIcon(a.icon, size: 24),
            glyphColor: glyphColor,
            title: a.name,
            subtitle: label,
            dotColor: dotColor,
            control: trailing ??
                RunAutomationButton(
                  automation: a,
                  service: service,
                  compact: true,
                  size: FeaturedTileAction.size,
                ),
          );
        }
        return _row(
          glyph: automationIcon(a.icon, size: 26),
          glyphColor: glyphColor,
          title: a.name,
          status: _status(label, dot: dotColor),
          control: trailing ??
              RunAutomationButton(
                  automation: a, service: service, compact: true),
          onTap: null,
          neo: neo,
        );
      },
    );
  }
}
