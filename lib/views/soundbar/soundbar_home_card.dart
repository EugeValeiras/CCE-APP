import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  const SoundbarHomeCard({super.key, required this.service, this.neo = false});

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
                ? (neo ? CceColors.accent : CceColors.warm)
                : CceColors.textSecondary);
        final sub = !online
            ? 'Fuera de línea'
            : (on ? 'Encendido · volumen ${jbl.volume}' : 'En espera');
        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor =
            !online ? CceColors.textTertiary : (on ? CceColors.accent : CceColors.textTertiary);
        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SoundbarScreen(service: jbl),
            ));
          },
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              // Avatar del speaker: WELL hundido en neo (neoSunken + neoInset),
              // fill tintado warm/surface en plano.
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: neo
                      ? CceColors.neoSunken
                      : (on
                          ? CceColors.warm.withValues(alpha: 0.18)
                          : CceColors.surfaceHigh),
                  boxShadow:
                      neo ? CceShadows.neoInset(blur: 8, offset: 3) : null,
                ),
                alignment: Alignment.center,
                child: CceIcon(
                  CceIcons.speaker,
                  size: 24,
                  // En neo el icono toma accent cuando ON (estado "vivo"), gris
                  // neo en espera/offline; en plano usa el accent histórico.
                  color: neo
                      ? (online && on
                          ? CceColors.accent
                          : CceColors.neoTextSub)
                      : accent,
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
                CceSwitch(value: on, onChanged: (_) => jbl.togglePower())
              else
                const Icon(Icons.chevron_right, color: CceColors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}
