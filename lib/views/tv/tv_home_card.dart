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

  /// Override del control derecho (modo edición del editor de Destacados):
  /// reemplaza el switch/acción por el widget dado (p.ej. un + o un −).
  final Widget? trailing;

  /// Se REENVÍA a la pantalla pusheada para su header de clima (esta card
  /// solo escucha a su TvService). null ⇒ la pantalla sin header.
  const TvHomeCard({
    super.key,
    required this.service,
    this.neo = false,
    this.onOpen,
    this.trailing,
  });

  @override
  State<TvHomeCard> createState() => _TvHomeCardState();
}

class _TvHomeCardState extends State<TvHomeCard> {
  // Acento del sistema, no el azul de la marca. En la home lo que se comunica
  // es "encendido", y eso tiene que verse igual en todos los dispositivos: un
  // color por marca convertía la lista en un semáforo donde nada destaca.
  // La identidad de Samsung vive en el detalle del TV.
  static const Color _tvAccent = CceColors.accent;

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
            : (on ? 'Encendido' : 'En espera');
        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor = !online
            ? CceColors.textTertiary
            : (on ? _tvAccent : CceColors.textTertiary);
        final card = CceCard(
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
          // En neo iguala el radio de las RoomCard (hueCard 24); en plano el
          // default histórico (28).
          radius: neo ? CceRadii.hueCard : CceRadii.card,
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
                    // Tile destacado compacto (fila TV|JBL): glyph 28 para
                    // homogeneizar con la jerarquía del header (vs 32 full).
                    size: neo ? 28 : 32,
                    // Color del glyph: accent ON / neoTextSub en espera-offline
                    // (neo); accent histórico en plano.
                    color: neo
                        ? (online && on ? _tvAccent : CceColors.textTertiary)
                        : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    // Ícono del sistema, no el logotipo de Samsung: en una
                    // lista, un logo de marca compite con el contenido y rompe
                    // la familia visual de los demás glyphs.
                    child: const CceIcon(CceIcons.tv, size: 30),
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
              if (widget.trailing != null)
                widget.trailing!
              else if (online)
                // Mandamos el estado EXPLÍCITO del switch (PUT /tv/power {on:v}):
                // desde la home el isOn cacheado puede estar stale/"unknown",
                // así que setPower garantiza la dirección correcta.
                CceSwitch(
                  value: on,
                  // El switch ON prende con el azul del TV (mismo acento que el
                  // ícono y el dot del Samsung), en vez del blanco neutro.
                  accent: _tvAccent,
                  onChanged: (v) => tv.setPower(v),
                )
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
            ],
          ),
        );

        // Sin glow que se derrame: el relieve lo da CceCard (cardFloat) y el
        // estado ON lo marca el switch + el ícono. No se suma halo detrás.
        return card;
      },
    );
  }
}
