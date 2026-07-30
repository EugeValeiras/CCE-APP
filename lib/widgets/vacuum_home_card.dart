import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_neo_button.dart';
import '../theme/components/status_dot.dart';
import '../utils/vacuum_state.dart';
import '../views/vacuum_screen.dart';
import 'vacuum_tile.dart';

/// Card del robot aspiradora para la sección "Destacados" de la home (cuarto
/// dispositivo dedicado, debajo de TV/JBL/Termostato). Espeja
/// [ThermostatHomeCard]: glyph extruido + título + dot/estado a la izquierda y
/// una acción rápida contextual a la derecha (Limpiar cuando está quieta,
/// Pausar cuando limpia; chevron fuera de línea). Al tocarla abre el control
/// completo ([VacuumScreen]).
///
/// Como el termostato, el robot es un [Device] dentro de [DevicesService]: la
/// card escucha al service y reresuelve el device por id en cada build.
class VacuumHomeCard extends StatelessWidget {
  final DevicesService service;
  final Device device;

  /// OPT-IN: relieve neumórfico (home teléfono / sidebar tablet).
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla.
  final VoidCallback? onOpen;

  /// Override del control derecho (modo edición del editor de Destacados):
  /// reemplaza el switch/acción por el widget dado (p.ej. un + o un −).
  final Widget? trailing;

  const VacuumHomeCard({
    super.key,
    required this.service,
    required this.device,
    this.neo = false,
    this.onOpen,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final s = d.state;
        final online = s.reachable;
        // El texto/color/pulse salen de la actividad detallada del sidecar
        // (mismo etiquetador que el plano y el Dashboard); la acción rápida
        // sigue keyed al vacuumState de Matter, que es por donde viajan los
        // comandos.
        final vacState = s.vacuumState;
        final busy = vacState == 'cleaning' || vacState == 'returning';
        final active = VacuumTile.statePulse(d);

        final accent =
            online ? VacuumTile.stateColor(d) : CceColors.textTertiary;

        final String sub;
        if (!online) {
          sub = 'Fuera de línea';
        } else {
          final battery = s.battery != null ? ' · ${s.battery}%' : '';
          sub = (vacuumStateLabel(d) ?? 'Sin estado') + battery;
        }

        final dotColor = online ? accent : CceColors.textTertiary;

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            if (onOpen != null) {
              onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VacuumScreen(device: d, service: service),
              ));
            }
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
                    size: neo ? 28 : 32,
                    color: neo
                        ? (online && active ? accent : CceColors.neoTextSub)
                        : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: const CceIcon(CceIcons.robotVacuum, size: 28),
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
                          ? CceText.title.copyWith(fontSize: 15)
                          : const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: CceColors.textPrimary,
                            ),
                    ),
                    SizedBox(height: neo ? 4 : 2),
                    if (neo)
                      Row(
                        children: [
                          StatusDot(
                            dotColor,
                            pulse: online && active,
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
              // Acción rápida contextual: pausar cuando limpia, REANUDAR cuando
              // está pausada (no 'clean': arrancaría una limpieza nueva pisando
              // p.ej. un cleanRooms en curso), limpiar cuando está quieta.
              // Fuera de línea → chevron.
              if (trailing != null)
                trailing!
              else if (online)
                CceNeoSvgIconButton(
                  svg: busy
                      ? CceIcons.pause
                      : (vacState == 'paused'
                          ? CceIcons.stepForward
                          : CceIcons.play),
                  size: 40,
                  tooltip: busy
                      ? 'Pausar'
                      : (vacState == 'paused' ? 'Reanudar' : 'Limpiar'),
                  onPressed: () => service.vacuumCommand(
                      d,
                      busy
                          ? 'pause'
                          : (vacState == 'paused' ? 'resume' : 'clean')),
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
