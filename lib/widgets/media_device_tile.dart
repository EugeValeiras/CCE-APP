import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../services/ui_settings_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/status_dot.dart';
import '../views/soundbar/soundbar_screen.dart';
import '../views/tv/tv_screen.dart';

/// Tiles de los dispositivos dedicados (Samsung TV / JBL soundbar) para la
/// sección "Devices" de una habitación. Mismo lenguaje visual que SensorTile
/// (glyph extruido + nombre + franja inferior con StatusDot + estado), pero
/// escuchan a SU service con polling (TvService / JblService) vía
/// AnimatedBuilder — NO a DevicesService: TV y JBL no viven ahí.
///
/// Tap: [onOpen] si se provee (tablet → control inline en el panel derecho);
/// si no, push de la pantalla dedicada (phone) — mismo dual que TvHomeCard /
/// SoundbarHomeCard.
class TvDeviceTile extends StatelessWidget {
  final TvService service;
  final TileSize size;
  final bool neo;
  final VoidCallback? onOpen;

  const TvDeviceTile({
    super.key,
    required this.service,
    this.size = TileSize.medium,
    this.neo = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final tv = service;
        final active = tv.online && tv.isOn;
        // Sin primera respuesta del service → '—' (mismo placeholder que los
        // sensores sin lectura); luego el patrón de TvHomeCard.
        final label = tv.status == null
            ? '—'
            : (!tv.online
                ? 'Fuera de línea'
                : (tv.isOn ? 'Encendido' : 'En espera'));
        return _MediaTile(
          name: tv.displayName,
          label: label,
          dotColor: active ? CceColors.info : CceColors.textTertiary,
          glyphColor: active ? CceColors.info : CceColors.textSecondary,
          svg: CceIcons.samsung,
          size: size,
          neo: neo,
          onTap: () {
            HapticFeedback.selectionClick();
            if (onOpen != null) {
              onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TvScreen(service: tv),
              ));
            }
          },
        );
      },
    );
  }
}

class JblDeviceTile extends StatelessWidget {
  final JblService service;
  final TileSize size;
  final bool neo;
  final VoidCallback? onOpen;

  const JblDeviceTile({
    super.key,
    required this.service,
    this.size = TileSize.medium,
    this.neo = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final jbl = service;
        final active = jbl.online && jbl.isOn;
        // Encendido: fuente y volumen SOLO si están disponibles (source es
        // nullable y hasVolume puede ser false según el transporte UPnP).
        final parts = <String>[
          if (jbl.source != null) jbl.source!,
          if (jbl.hasVolume) 'volumen ${jbl.volume}',
        ];
        final label = jbl.status == null
            ? '—'
            : (!jbl.online
                ? 'Fuera de línea'
                : (!jbl.isOn
                    ? 'En espera'
                    : (parts.isEmpty ? 'Encendido' : parts.join(' · '))));
        return _MediaTile(
          name: jbl.displayName,
          label: label,
          dotColor: active ? CceColors.jblOrange : CceColors.textTertiary,
          glyphColor: active ? CceColors.jblOrange : CceColors.textSecondary,
          svg: CceIcons.jbl,
          size: size,
          neo: neo,
          onTap: () {
            HapticFeedback.selectionClick();
            if (onOpen != null) {
              onOpen!();
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SoundbarScreen(service: jbl),
              ));
            }
          },
        );
      },
    );
  }
}

/// Frame compartido: clon de la rama NO-alert de SensorTile (superficie
/// cardSurface + glyph extruido con el par FIJO de CceEmboss + franja inferior
/// de 46px con StatusDot + label).
class _MediaTile extends StatelessWidget {
  final String name;
  final String label;
  final Color dotColor;
  final Color glyphColor;
  final String svg;
  final TileSize size;
  final bool neo;
  final VoidCallback onTap;

  const _MediaTile({
    required this.name,
    required this.label,
    required this.dotColor,
    required this.glyphColor,
    required this.svg,
    required this.size,
    required this.neo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double glyphSize = size.iconSize + 8; // 30 / 34 / 38, como SensorTile
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: size.sensorTileHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: CceGradients.cardSurface(
              neo ? CceColors.neoBase : CceColors.cardOff),
          borderRadius: BorderRadius.circular(CceRadii.hueCard),
          border: Border.all(color: CceColors.cardBevel),
          boxShadow: neo ? CceShadows.cardFloat() : null,
        ),
        child: Column(
          children: [
            // Zona superior centrada: ícono extruido + nombre (el estado vive
            // en la franja inferior) — misma estructura que SensorTile.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: EmbossedGlyph(
                          size: glyphSize,
                          color: glyphColor,
                          highlight: CceEmboss.highlight.color,
                          shadow: CceEmboss.shadow.color,
                          child: CceIcon(svg, size: 24, color: glyphColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CceColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Franja inferior con borde superior; estado centrado (dot + label).
            Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: neo
                        ? Colors.black.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(dotColor, semanticLabel: label),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CceColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
