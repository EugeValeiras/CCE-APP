import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tv_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
import '../../theme/components/status_dot.dart';
import 'tv_screen.dart';

/// Card del Samsung TV para la home (lo "expone como dispositivo"): muestra
/// estado + power rápido y abre la pantalla completa al tocarla. Clon directo
/// de [SoundbarHomeCard] adaptado al TV (ícono de TV, acento azul "vivo").
class TvHomeCard extends StatefulWidget {
  final TvService service;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ render
  /// idéntico al plano.
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla
  /// (en tablet el control se muestra inline en el panel derecho, no full-screen
  /// — la tablet no tiene swipe-back para volver).
  final VoidCallback? onOpen;
  const TvHomeCard({
    super.key,
    required this.service,
    this.neo = false,
    this.onOpen,
  });

  @override
  State<TvHomeCard> createState() => _TvHomeCardState();
}

class _TvHomeCardState extends State<TvHomeCard> {
  // Acento "vivo" del TV (ON): azul info de la marca/UI, espejo del jblOrange
  // de la card del soundbar.
  static const Color _tvAccent = CceColors.info;

  @override
  void initState() {
    super.initState();
    // Refresco de cortesía al aparecer (el shell maneja el polling continuo).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.service.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final tv = widget.service;
        final online = tv.online;
        final on = tv.isOn;
        final neo = widget.neo;
        // Color de acento del estado. En neo, el "vivo" es accent (ON) y el
        // resto cae a los grises neo; en plano se conserva el warm histórico.
        final accent = !online
            ? CceColors.textTertiary
            : (on
                ? (neo ? _tvAccent : CceColors.warm)
                : CceColors.textSecondary);
        final sub = !online
            ? 'Fuera de línea'
            : (on
                ? (tv.hasVolume
                    ? 'Encendido · volumen ${tv.volume}'
                    : 'Encendido')
                : 'En espera');
        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor = !online
            ? CceColors.textTertiary
            : (on ? _tvAccent : CceColors.textTertiary);
        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            if (widget.onOpen != null) {
              widget.onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TvScreen(service: tv),
              ));
            }
          },
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              // TV GRANDE extruido, SIN círculo (coherente con el ícono de las
              // RoomCard y la card del soundbar). El fondo de la card es siempre
              // oscuro (neoBase en neo / surface en plano): el relieve usa el par
              // FIJO de CceEmboss. Reservamos el mismo ancho (48) con Center para
              // no mover título/switch.
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: 32,
                    // Color del glyph: accent ON / neoTextSub en espera-offline
                    // (neo); accent histórico en plano.
                    color: neo
                        ? (online && on ? _tvAccent : CceColors.neoTextSub)
                        : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: const CceIcon(CceIcons.samsung, size: 34),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título: en neo usa CceText.title (titleInk + emboss) para
                    // grabarse en la goma; en plano conserva el estilo histórico.
                    Text(
                      tv.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: neo
                          ? CceText.title.copyWith(fontSize: 17)
                          : const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: CceColors.textPrimary,
                            ),
                    ),
                    SizedBox(height: neo ? 4 : 2),
                    // Estado: en neo, StatusDot (accent pulsante ON) + label;
                    // en plano, el subtítulo tintado de siempre.
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
              if (online)
                // Mandamos el estado EXPLÍCITO del switch (PUT /tv/power {on:v}):
                // desde la home el isOn cacheado puede estar stale/"unknown",
                // así que setPower garantiza la dirección correcta.
                CceSwitch(value: on, onChanged: (v) => tv.setPower(v))
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}
