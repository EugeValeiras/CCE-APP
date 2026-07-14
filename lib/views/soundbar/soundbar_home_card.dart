import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/devices_service.dart';
import '../../services/jbl_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
import '../../theme/components/status_dot.dart';
import 'soundbar_screen.dart';

/// Card del JBL Soundbar para la home (lo "expone como dispositivo"): muestra
/// estado + power rápido y abre la pantalla completa al tocarla.
class SoundbarHomeCard extends StatefulWidget {
  final JblService service;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ render
  /// idéntico al actual.
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla
  /// (en tablet el control se muestra inline en el panel derecho).
  final VoidCallback? onOpen;

  /// Se REENVÍA a la pantalla pusheada para su header de clima (esta card
  /// solo escucha a su JblService). null ⇒ la pantalla sin header.
  final DevicesService? devices;
  const SoundbarHomeCard({
    super.key,
    required this.service,
    this.neo = false,
    this.onOpen,
    this.devices,
  });

  @override
  State<SoundbarHomeCard> createState() => _SoundbarHomeCardState();
}

class _SoundbarHomeCardState extends State<SoundbarHomeCard> {
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
        final jbl = widget.service;
        final online = jbl.online;
        final on = jbl.isOn;
        final neo = widget.neo;
        // Color de acento del estado. En neo, el "vivo" es accent (ON) y el
        // resto cae a los grises neo; en plano se conserva el warm histórico.
        final accent = !online
            ? CceColors.textTertiary
            : (on
                ? (neo ? CceColors.jblOrange : CceColors.warm)
                : CceColors.textSecondary);
        final sub = !online
            ? 'Fuera de línea'
            : (on ? 'Encendido · volumen ${jbl.volume}' : 'En espera');
        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor =
            !online ? CceColors.textTertiary : (on ? CceColors.jblOrange : CceColors.textTertiary);
        final card = CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            if (widget.onOpen != null) {
              widget.onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    SoundbarScreen(service: jbl, devices: widget.devices),
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
              // Speaker GRANDE extruido, SIN círculo (coherente con el ícono de
              // las RoomCard). El fondo de esta card es siempre oscuro (neoBase
              // en neo / surface en plano): no hay fill pastel saturado, así que
              // el relieve usa el par FIJO de CceEmboss (calibrado para oscuro),
              // NO el emboss-de-color de la RoomCard ON. Reservamos el mismo
              // ancho (48) con Center para no mover título/switch.
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    // Tile destacado compacto (fila TV|JBL): glyph 28 para
                    // homogeneizar con la jerarquía del header (vs 32 full).
                    size: neo ? 28 : 32,
                    // Color del glyph preservado: accent ON / neoTextSub en
                    // espera-offline (neo); accent histórico en plano.
                    color: neo
                        ? (online && on
                            ? CceColors.jblOrange
                            : CceColors.neoTextSub)
                        : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    child: const CceIcon(CceIcons.jbl, size: 32),
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
                      jbl.displayName,
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
              if (online)
                CceSwitch(
                  value: on,
                  accent: CceColors.jblOrange,
                  onChanged: (_) => jbl.togglePower(),
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
