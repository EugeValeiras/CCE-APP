import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_switch.dart';
import '../theme/components/featured_tile.dart';
import '../theme/components/status_dot.dart';
import '../views/thermostat_screen.dart';

/// Card del Termostato (Tuya cat 'wk') para la sección "Destacados" de la home:
/// el TERCER dispositivo dedicado, debajo del TV y del JBL. Espeja
/// [TvHomeCard]/[SoundbarHomeCard]: glyph extruido + título + dot/estado a la
/// izquierda y un switch de power rápido (o chevron si está fuera de línea) a la
/// derecha; al tocarla abre el control completo ([ThermostatScreen]).
///
/// A diferencia del TV/JBL (que tienen un service dedicado), el termostato es un
/// [Device] dentro de [DevicesService]: la card escucha al service
/// (AnimatedBuilder) y reresuelve el device por id en cada build para no quedar
/// stale. La semántica de acento (calor = cálido, frío = info) espeja a
/// [ThermostatTile]. Ícono: termómetro estable (identidad de "clima"); el color
/// comunica el estado. Todos los íconos salen de icons0.dev ([CceIcons]).
class ThermostatHomeCard extends StatelessWidget {
  final DevicesService service;
  final Device device;

  /// OPT-IN: relieve neumórfico (home teléfono / sidebar tablet). Default false
  /// ⇒ render plano.
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla
  /// (en tablet el control se muestra inline en el panel derecho — la tablet no
  /// tiene swipe-back para volver).
  final VoidCallback? onOpen;

  /// Override del control derecho (modo edición del editor de Destacados):
  /// reemplaza el switch/acción por el widget dado (p.ej. un + o un −).
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

  const ThermostatHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = false,
    this.onOpen,
    this.trailing,
    this.tile = false,
  });

  /// Formatea temperaturas: 0.5 con decimal, enteros sin decimal (igual que
  /// [ThermostatScreen]).
  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        // Reresolución defensiva: el device del padre puede quedar stale tras un
        // refresh / evento WS; tomamos el del service por id.
        final d = service.byId(device.id) ?? device;
        final s = d.state;
        final online = s.reachable;
        final on = s.on;

        // Acento del sistema. El modo frío/calor es información real, pero se
        // lee en el texto (objetivo vs. actual) y en el detalle: en la home,
        // un azul entre ámbares rompía la familia de la lista.
        final accent = !online
            ? CceColors.textTertiary
            : (on
                ? CceColors.accent
                : CceColors.textSecondary);

        final target = s.targetTemp;
        final current = s.currentTemp;
        // CCE#101 — la actividad del relé (state.heating) delante de las
        // temperaturas: «Calentando · 18.3° → 19.5°». null si la API no la
        // manda: entonces, lo de siempre.
        final String? activity = s.heating == null
            ? null
            : (s.heating == true ? 'Calentando' : 'En temperatura');
        final String sub;
        if (!online) {
          sub = 'Fuera de línea';
        } else if (!on) {
          sub = 'Apagado';
        } else if (target != null) {
          // En el tile: "20.7° → 20°" (actual → objetivo) entra en una línea
          // de 179 px; "Objetivo 20° · actual 20.7°" no.
          final temps = tile
              ? (current != null
                  ? '${_fmt(current)}° → ${_fmt(target)}°'
                  : 'Objetivo ${_fmt(target)}°')
              : 'Objetivo ${_fmt(target)}°'
                  '${current != null ? ' · actual ${_fmt(current)}°' : ''}';
          sub = activity != null ? '$activity · $temps' : temps;
        } else {
          sub = activity ?? 'Encendido';
        }

        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor = !online
            ? CceColors.textTertiary
            : (on ? accent : CceColors.textTertiary);
        final glyphColor = online && on ? accent : CceColors.textTertiary;

        void open() {
          HapticFeedback.selectionClick();
          if (onOpen != null) {
            onOpen!();
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ThermostatScreen(device: d, service: service),
            ));
          }
        }

        // Power rápido: mandamos el estado EXPLÍCITO (setThermostatPower)
        // con revert optimista en el service. Fuera de línea → chevron.
        final Widget control = trailing ??
            (online
                ? CceSwitch(
                    value: on,
                    accent: CceColors.accent,
                    onChanged: (v) => service.setThermostatPower(d, v),
                  )
                : FeaturedTile.chevron());

        if (tile) {
          return FeaturedTile(
            glyph: const CceIcon(CceIcons.thermometer, size: 24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: sub,
            dotColor: dotColor,
            dotPulse: online && on,
            control: control,
            onTap: open,
          );
        }

        return CceCard(
          onTap: open,
          // En neo iguala el radio de las RoomCard (hueCard 24); en plano el
          // default histórico (28).
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              // Termómetro GRANDE extruido, SIN círculo (coherente con la card
              // del TV/JBL). Reservamos el mismo ancho (48) con Center para no
              // mover título/switch.
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    // Tile destacado compacto: glyph 28 en neo (vs 32 plano),
                    // homogéneo con la fila TV|JBL.
                    size: neo ? 28 : 32,
                    color: neo ? glyphColor : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: const CceIcon(CceIcons.thermometer, size: 28),
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
                      style: neo
                          // Tile compacto de la fila destacada: 15 (vs 17 full).
                          ? CceText.title.copyWith(fontSize: 15)
                          : const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: CceColors.textPrimary,
                            ),
                    ),
                    SizedBox(height: neo ? 4 : 2),
                    // Estado: en neo, StatusDot (accent pulsante ON) + label; en
                    // plano, el subtítulo tintado de siempre.
                    if (neo)
                      Row(
                        children: [
                          StatusDot(
                            dotColor,
                            pulse: online && on,
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
                      )
                    else
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CceText.caption.copyWith(color: accent),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              control,
            ],
          ),
        );
      },
    );
  }
}
