import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../services/telephony_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/status_dot.dart';
import '../views/telephony_screen.dart';

/// Card del teléfono 4G para "Destacados". Espeja [VacuumHomeCard]: glyph
/// extruido + título + dot/estado a la izquierda, y a la derecha el contador de
/// perdidas no vistas (o un chevron). Al tocarla abre [TelephonyScreen].
///
/// Muestra dos cosas distintas según haya llamada o no:
///  - Con llamada viva: quién y en qué estado está (es lo urgente).
///  - Sin llamada: el estado de la LÍNEA, que no es lo mismo que el registro de
///    red — una línea sin habilitar se registra igual y reporta todo en verde.
///
/// La app NO disca (decisión de producto: el dial pad vive sólo en el
/// dashboard), así que la card no tiene acción rápida de llamar.
class PhoneHomeCard extends StatelessWidget {
  final DevicesService service;
  final TelephonyService telephony;
  final Device device;

  /// OPT-IN: relieve neumórfico (home teléfono / sidebar tablet).
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla.
  final VoidCallback? onOpen;

  /// Override del control derecho (modo edición del editor de Destacados).
  final Widget? trailing;

  const PhoneHomeCard({
    super.key,
    required this.service,
    required this.telephony,
    required this.device,
    this.neo = false,
    this.onOpen,
    this.trailing,
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

        // Una entrante sonando es lo más urgente que puede mostrar esta card.
        final Color accent;
        if (!online) {
          accent = CceColors.textTertiary;
        } else if (ringing) {
          accent = CceColors.ok;
        } else if (inCall) {
          accent = CceColors.accent;
        } else if (s.lineActive == 'inactive') {
          accent = CceColors.danger;
        } else {
          accent = CceColors.textSecondary;
        }

        final String sub;
        if (!online) {
          sub = 'Módem no disponible';
        } else if (inCall) {
          final who = s.peerName ?? s.peerNumber ?? 'Sin identificar';
          sub = '${_callStateLabel(s.callState)} · $who';
        } else if (s.lineActive == 'inactive') {
          sub = 'Línea inactiva';
        } else {
          // Ni "OK" ni "Todo bien": mientras `lineActive` sea 'unknown' lo único
          // que sabemos es que está registrado, y eso NO garantiza que curse.
          final bars = s.signalBars ?? 0;
          final net = s.networkOperator ?? s.networkTech ?? 'Registrado';
          sub = '$net · $bars/5';
        }

        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            if (onOpen != null) {
              onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    TelephonyScreen(device: d, service: service, telephony: telephony),
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
                        ? (online && inCall ? accent : CceColors.neoTextSub)
                        : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: CceIcon(
                      ringing
                          ? CceIcons.phoneIncoming
                          : (missed > 0 ? CceIcons.phoneMissed : CceIcons.phone),
                      size: 28,
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
                            online ? accent : CceColors.textTertiary,
                            // El pulso es para la entrante: es lo que hay que
                            // atender ahora, no un estado más.
                            pulse: online && ringing,
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
              if (trailing != null)
                trailing!
              else if (missed > 0)
                _MissedBadge(count: missed)
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
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

/// Contador de perdidas no vistas. Va en la card y no sólo en la pantalla: una
/// llamada perdida es el aviso de último recurso de la casa y tiene que verse
/// sin entrar a ningún lado.
class _MissedBadge extends StatelessWidget {
  final int count;
  const _MissedBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: CceColors.danger,
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
