import 'package:flutter/material.dart';

import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Bloque de ESTADO GRANDE (canon de LockScreen / SensorDetailScreen): disco
/// cóncavo con glow del acento + label grande + subtítulo.
///
/// [child] permite reemplazar el glyph por un control propio (p.ej. el dial de
/// 4 cuadrantes o el botón redondo), manteniendo el mismo marco.
class DeviceStatePanel extends StatelessWidget {
  final String label;
  final String? sublabel;
  final Color accent;

  /// Glyph SVG centrado en el disco. Ignorado si se pasa [child].
  final String? glyph;

  /// Control custom en lugar del disco (botones clickeables).
  final Widget? child;

  /// El acento "prende": glow del disco y del label.
  final bool glowing;

  const DeviceStatePanel({
    super.key,
    required this.label,
    required this.accent,
    this.sublabel,
    this.glyph,
    this.child,
    this.glowing = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(28),
        boxShadow: CceShadows.neo(blur: 16, offset: 6),
      ),
      child: Column(
        children: [
          child ??
              Container(
                width: 132,
                height: 132,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: CceGradients.concave(CceColors.neoBase),
                  // Glow SOLO por BoxShadow (Impeller: nunca ImageFiltered).
                  boxShadow: [
                    ...CceShadows.plato(blur: 15, offset: 6),
                    if (glowing) ...CceShadows.glowDot(accent),
                  ],
                ),
                child: SizedBox.square(
                  dimension: 56,
                  child: CceIcon(
                    glyph ?? CceIcons.sensors,
                    size: 56,
                    color: accent,
                    emboss: false,
                  ),
                ),
              ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: accent,
                shadows: glowing
                    ? [
                        Shadow(
                          color: accent.withValues(alpha: 0.65),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 6),
            Text(
              sublabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: CceText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila de wells hundidos con las métricas del device (batería, último evento,
/// conexión…). Sin CrossAxisAlignment.stretch: es un Row dentro de scroll de
/// altura ilimitada.
class DeviceMetricsRow extends StatelessWidget {
  final List<DeviceMetric> metrics;

  const DeviceMetricsRow({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = c.maxWidth < 360 ? 8.0 : 12.0;
        final children = <Widget>[];
        for (var i = 0; i < metrics.length; i++) {
          if (i > 0) children.add(SizedBox(width: gap));
          children.add(Expanded(child: metrics[i]));
        }
        return Row(children: children);
      },
    );
  }
}

class DeviceMetric extends StatelessWidget {
  final String svg;
  final Color iconColor;
  final String value;
  final String label;

  /// Si se provee, el recuadro deja de ser un dato y pasa a ser un BOTÓN.
  final VoidCallback? onTap;

  const DeviceMetric({
    super.key,
    required this.svg,
    required this.iconColor,
    required this.value,
    required this.label,
    this.onTap,
  });

  /// Color de batería por nivel (verde / ámbar / rojo).
  static Color batteryColor(String? raw) {
    final pct = int.tryParse(raw ?? '');
    if (pct == null) return CceColors.textSecondary;
    if (pct <= 15) return CceColors.danger;
    if (pct <= 35) return CceColors.warm;
    return CceColors.ok;
  }

  @override
  Widget build(BuildContext context) {
    final card = _card();
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(16),
        boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 22,
            child: CceIcon(svg, size: 22, color: iconColor, emboss: false),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CceColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: CceColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wordmark de pie (grabado en la goma).
class DeviceWordmark extends StatelessWidget {
  final String text;
  const DeviceWordmark(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: CceColors.textTertiary,
          shadows: [
            Shadow(
              color: Color(0x80FFFFFF),
              offset: Offset(-1, -1.2),
              blurRadius: 1.5,
            ),
            Shadow(
              color: Color(0xD907080C),
              offset: Offset(1.4, 2),
              blurRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}
