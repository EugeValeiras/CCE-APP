import 'package:flutter/material.dart';

import '../cce_tokens.dart';
import 'brightness_slider.dart';
import 'cce_card.dart';

/// Card de habitacion (sidebar tablet y lista phone), estilo Hue:
/// gradiente calido si hay luces encendidas, switch a la derecha y slider
/// de brillo embebido (solo tablet, cuando [brightness] != null).
///
/// Layout congelado (anti-overflow):
///  - compact == true (phone): altura FIJA 96, NUNCA renderiza slider.
///  - compact == false (tablet): 116 sin slider; 156 con slider (height 36).
class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.title,
    required this.icon,
    required this.lightsOn,
    required this.lightsTotal,
    required this.anyOn,
    this.tint,
    this.brightness,
    this.selected = false,
    this.compact = false,
    this.statusChips = const <Widget>[],
    required this.onTap,
    required this.onToggle,
    this.onBrightnessChanged,
    this.onBrightnessCommitted,
  });

  final String title;
  final Widget icon; // Icon(MdiIcons...) o CceIcon
  final int lightsOn;
  final int lightsTotal;
  final bool anyOn;
  final Color? tint; // RoomStats.tint
  final double? brightness; // 0..1; null = sin slider
  final bool selected; // resaltado en sidebar tablet
  final bool compact; // phone vs tablet
  final List<Widget> statusChips; // StatusPill: "Abierta", "Movimiento"
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle; // switch a la derecha
  final ValueChanged<double>? onBrightnessChanged; // drag en vivo, 0..1
  final ValueChanged<double>? onBrightnessCommitted; // commit al soltar, 0..1

  // Texto oscuro sobre el gradiente calido (estilo Hue), claro sobre apagado.
  static const _fgOn = Color(0xFF2B1A0A);
  static const _fgOnSub = Color(0xB32B1A0A);

  @override
  Widget build(BuildContext context) {
    final showSlider = !compact && brightness != null;
    final height = compact ? 96.0 : (showSlider ? 156.0 : 116.0);
    final fg = anyOn ? _fgOn : CceColors.textPrimary;
    final fgSub = anyOn ? _fgOnSub : CceColors.textSecondary;

    final subtitle = lightsTotal == 0
        ? 'Sin luces'
        : lightsOn == 0
            ? '$lightsTotal ${lightsTotal == 1 ? 'luz' : 'luces'}'
            : '$lightsOn de $lightsTotal encendidas';

    final headerRow = Row(
      children: [
        Container(
          width: compact ? 42 : 48,
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            color: anyOn
                ? Colors.white.withValues(alpha: 0.28)
                : CceColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: IconTheme.merge(
            data: IconThemeData(color: fg, size: compact ? 22 : 24),
            child: icon,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 17 : 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: fg,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption.copyWith(color: fgSub),
                    ),
                  ),
                  for (final chip in statusChips) ...[
                    const SizedBox(width: 6),
                    chip,
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: anyOn,
          onChanged: lightsTotal == 0 ? null : onToggle,
          activeTrackColor: anyOn ? Colors.white.withValues(alpha: 0.45) : null,
          thumbColor: anyOn ? const WidgetStatePropertyAll(_fgOn) : null,
        ),
      ],
    );

    final card = CceCard(
      gradient: anyOn ? CceGradients.roomOn(tint) : CceGradients.roomOff,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
      onTap: onTap,
      child: showSlider
          ? Column(
              children: [
                Expanded(child: headerRow),
                CceBrightnessSlider(
                  height: 36,
                  value: brightness!.clamp(0.0, 1.0).toDouble(),
                  activeColor: anyOn
                      ? Colors.white.withValues(alpha: 0.85)
                      : CceColors.warm,
                  onChanged: onBrightnessChanged ?? (_) {},
                  onChangeEnd: onBrightnessCommitted,
                ),
              ],
            )
          : Center(child: headerRow),
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          card,
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CceRadii.card),
                    border: Border.all(color: CceColors.accent, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
