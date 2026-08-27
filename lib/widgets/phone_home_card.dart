import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/telephony_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/featured_tile.dart';
import '../theme/components/status_dot.dart';
import '../views/telephony/line_status_chip.dart';
import '../views/telephony_screen.dart';

/// Card del teléfono 4G para "Destacados". Espeja [VacuumHomeCard]: glyph
/// extruido + título + dot/estado a la izquierda, y a la derecha el contador de
/// perdidas no vistas (o un chevron). Al tocarla abre [TelephonyScreen].
///
/// Muestra dos cosas distintas según haya llamada o no:
///  - Con llamada viva: quién y en qué estado está (es lo urgente).
///  - Sin llamada: el estado de la LÍNEA, que no es lo mismo que el registro de
///    red — una línea sin habilitar se registra igual y reporta todo en verde.
///    Se dice con las mismas palabras, el mismo color y las mismas barritas que
///    el chip de la pantalla que abre (CCE#14): la card es la puerta, y del otro
///    lado tiene que estar lo mismo que promete.
///
/// La card no disca: abre [TelephonyScreen], que es donde está el teclado. Un
/// atajo para llamar en la pantalla de inicio sería lo más fácil de apretar sin
/// querer, y con la línea activa eso cuesta plata.
class PhoneHomeCard extends StatelessWidget {
  final DevicesService service;
  final TelephonyService telephony;
  final Device device;

  /// OPT-IN: relieve neumórfico (home teléfono / sidebar tablet).
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla.
  final VoidCallback? onOpen;

  /// Override del control derecho (editor de Destacados).
  final Widget? trailing;

  /// true ⇒ [FeaturedTile] (grilla 2 × 2 de la home); false ⇒ fila.
  final bool tile;

  const PhoneHomeCard({
    super.key,
    required this.service,
    required this.telephony,
    required this.device,
    this.neo = false,
    this.onOpen,
    this.trailing,
    this.tile = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([service, telephony]),
      builder: (context, _) {
        final d = service.byId(device.id) ?? device;
        final s = d.state;
        final online = s.reachable;
        final inCall = d.phoneInCall;
        final ringing = s.callState == 'ringing';
        final missed = telephony.unseenMissed;
        // Perdidas + SMS nuevos (CCE#23): las dos cosas se ven sin entrar. El
        // rojo es de la perdida; con sólo mensajes el badge va en acento.
        final pending = telephony.unseenTotal;

        // Una entrante sonando es lo más urgente que puede mostrar esta card.
        final Color accent;
        final String sub;
        // La señal sólo tiene sentido en reposo: con llamada, lo que importa es
        // quién; sin módem, no hay señal que mostrar.
        int? bars;
        if (!online) {
          accent = CceColors.textTertiary;
          sub = 'Módem no disponible';
        } else if (ringing) {
          accent = CceColors.ok;
          final who = s.peerName ?? s.peerNumber ?? 'Número desconocido';
          sub = 'Llamada entrante · $who';
        } else if (inCall) {
          accent = CceColors.accent;
          final who = s.peerName ?? s.peerNumber ?? 'Sin identificar';
          sub = '${_callStateLabel(s.callState)} · $who';
        } else {
          // Las mismas palabras —y las mismas fuentes— que el chip de la
          // pantalla: el estado en vivo del device manda, y lo que no traiga
          // se lee del seed de `/phone/status`. Ni "OK" ni "Todo bien":
          // mientras `lineActive` sea 'unknown' lo único que sabemos es que
          // está registrado, y eso NO garantiza que curse.
          final st = telephony.status;
          final (String lineText, Color lineColor) =
              switch (s.lineActive ?? st.lineActive) {
            'active' => ('Línea activa', CceColors.ok),
            'inactive' => ('Línea inactiva', CceColors.danger),
            _ => ('Línea sin verificar', CceColors.textTertiary),
          };
          accent = lineColor;
          final net = s.networkOperator ??
              st.operator ??
              s.networkTech ??
              st.tech ??
              'Registrado';
          sub = '$lineText · $net';
          bars = s.signalBars ?? st.signalBars;
        }

        // El glifo va con el color del estado sólo cuando hay algo que atender
        // (entrante, llamada): un glifo verde permanente en la home sería
        // decoración.
        final glyphColor = neo || tile
            ? (online && (ringing || inCall) ? accent : CceColors.textTertiary)
            : (ringing || inCall ? accent : CceColors.textSecondary);
        final String glyphSvg = ringing
            ? CceIcons.phoneIncoming
            : missed > 0
                ? CceIcons.phoneMissed
                : pending > 0
                    ? CceIcons.sms
                    : CceIcons.phone;

        void open() {
          HapticFeedback.selectionClick();
          if (onOpen != null) {
            onOpen!();
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TelephonyScreen(
                  device: d, service: service, telephony: telephony),
            ));
          }
        }

        final Widget control = trailing ??
            (pending > 0
                ? _MissedBadge(
                    count: pending,
                    color: missed > 0 ? CceColors.danger : CceColors.accent,
                  )
                : FeaturedTile.chevron());

        if (tile) {
          return FeaturedTile(
            glyph: CceIcon(glyphSvg, size: 24),
            glyphColor: glyphColor,
            title: service.displayName(d),
            subtitle: sub,
            dotColor: online ? accent : CceColors.textTertiary,
            // El pulso es para la entrante: es lo que hay que atender ahora.
            dotPulse: online && ringing,
            control: control,
            onTap: open,
          );
        }

        return CceCard(
          onTap: open,
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
                    color: glyphColor,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: CceIcon(glyphSvg, size: 28),
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
                    Row(
                      children: [
                        if (neo) ...[
                          StatusDot(
                            online ? accent : CceColors.textTertiary,
                            // El pulso es para la entrante: es lo que hay que
                            // atender ahora, no un estado más.
                            pulse: online && ringing,
                            semanticLabel: sub,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            sub,
                            maxLines: 1,
                            softWrap: false,
                            // El estado va primero y entra siempre; lo que se
                            // desvanece si falta lugar es el operador.
                            overflow: TextOverflow.fade,
                            style: neo
                                ? CceText.caption
                                : CceText.caption.copyWith(color: accent),
                          ),
                        ),
                        if (bars != null) ...[
                          const SizedBox(width: 8),
                          SignalBars(bars, height: 10),
                        ],
                      ],
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

  static String _callStateLabel(String? state) {
    switch (state) {
      case 'dialing':
        return 'Marcando';
      case 'ringing':
        return 'Llamando';
      case 'active':
        return 'En curso';
      default:
        return 'Llamada';
    }
  }
}

/// Contador de perdidas y SMS no vistos. Va en la card y no sólo en la
/// pantalla: una llamada perdida es el aviso de último recurso de la casa y
/// un SMS suele ser un código que hay que leer ya; los dos tienen que verse
/// sin entrar a ningún lado.
class _MissedBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _MissedBadge({required this.count, this.color = CceColors.danger});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: CceColors.textPrimary,
        ),
      ),
    );
  }
}
