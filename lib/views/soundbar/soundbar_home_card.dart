import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/jbl_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
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
        final accent = !online
            ? CceColors.textTertiary
            : (on ? CceColors.warm : CceColors.textSecondary);
        final sub = !online
            ? 'Fuera de línea'
            : (on ? 'Encendido · ${jbl.volume}% volumen' : 'En espera');
        return CceCard(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SoundbarScreen(service: jbl),
            ));
          },
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: widget.neo ? CceColors.neoBase : null,
          neo: widget.neo,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.neo
                      ? CceColors.neoSunken
                      : (on
                          ? CceColors.warm.withValues(alpha: 0.18)
                          : CceColors.surfaceHigh),
                  boxShadow: widget.neo ? CceShadows.neoInset() : null,
                ),
                alignment: Alignment.center,
                child: CceIcon(
                  CceIcons.speaker,
                  size: 24,
                  color: widget.neo ? CceColors.neoText : accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jbl.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: CceColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                Switch.adaptive(
                  value: on,
                  onChanged: (_) => jbl.togglePower(),
                  activeTrackColor: Colors.white.withValues(alpha: 0.45),
                      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
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
