import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/tv_status.dart';
import '../../services/tv_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';

/// Pantalla completa del Samsung TV: SIMULA EL CONTROL REMOTO real del usuario
/// (Samsung One Remote / SolarCell), fiel a la foto de su control. El cuerpo es
/// un control vertical negro mate redondeado, estilo neumórfico oscuro coherente
/// con el tema (CceColors.neoBase / EmbossedGlyph), con el wordmark SAMSUNG
/// abajo.
///
/// Disposición (de arriba abajo, espejo del control físico):
///  - Fila superior: Power (acento rojo, izq) y Voz/Mic (der, visual/no-op).
///  - D-PAD circular GRANDE con OK central (elemento dominante).
///  - Anillo de utilidades alrededor: Guía/Playback, Home, Return/Back, Mute,
///    123 (teclado numérico).
///  - Dos ROCKERS píldora: Volumen (+/−, mute al centro) y Canal (∧/∨).
///  - Accesos directos de apps: Netflix, Prime Video, YouTube, www.
///  - (Sheet opcional) selector de Input/HDMI + transport play/pause/stop.
///
/// El shell (tablet/phone) crea y dispone el [TvService] y posee el ciclo de
/// polling; esta pantalla NO dispone el service ni arranca polling: solo hace un
/// refresh de cortesía one-shot en initState (mismo patrón que SoundbarScreen).
class TvScreen extends StatefulWidget {
  const TvScreen({super.key, required this.service});

  /// El shell lo crea/dispone; la screen NO lo dispone.
  final TvService service;

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh defensivo de cortesía (one-shot). El polling lo posee el shell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.service.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      backgroundColor: CceColors.neoBase,
      // Sin AppBar: control full-screen. Se vuelve con el swipe iOS.
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) => _buildBody(context, service),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TvService service) {
    // Fallo real de red/servidor (sin estado conocido): cartel + reintentar.
    if (service.error != null && service.status == null) {
      return _ServerError(onRetry: service.refresh);
    }

    // Primera carga, todavía sin estado.
    if (service.status == null && service.loading) {
      return const Center(
        child: CircularProgressIndicator(color: CceColors.textTertiary),
      );
    }

    // El cuerpo del control SIEMPRE se monta (varias teclas despiertan el TV
    // desde standby: sendKey/launchApp no gatean por online). Cuando !online,
    // el cuerpo se atenúa y aparece el cartel "Sin conexión" arriba.
    final online = service.online;
    // El control entra en UNA pantalla: el cuerpo se escala al alto disponible
    // con FittedBox(scaleDown) — a tamaño natural si entra, achicándose solo si
    // la pantalla es chica. Así no hay scroll y se ve completo en cualquier
    // teléfono (no podemos medir con Flutter local, esto lo garantiza).
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      child: Column(
        children: [
          if (!online) ...[
            const _OfflineBanner(),
            const SizedBox(height: 8),
          ],
          Expanded(
            // Igual que el control del JBL: CENTRADO (ambos ejes) y capeado a
            // ancho de celular (480). BoxFit.contain escala el control para usar
            // el ALTO completo disponible (en iPad crece y queda centrado; en
            // teléfono se achica para entrar en una sola pantalla).
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 420,
                    child: _RemoteBody(service: service, online: online),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CUERPO DEL CONTROL
// ════════════════════════════════════════════════════════════════════════════

/// Cuerpo del control remoto: la "carcasa" negra mate redondeada con todos los
/// botones. Replica la disposición del Samsung One Remote físico.
class _RemoteBody extends StatelessWidget {
  const _RemoteBody({required this.service, required this.online});

  final TvService service;
  final bool online;

  @override
  Widget build(BuildContext context) {
    // ANCHO COMPLETO: la carcasa ocupa todo el ancho dado por el SizedBox del
    // _buildBody (el FittedBox cuida el alto). Ya no se limita a 340 px.
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            // Carcasa negra mate: gradiente sutil + relieve flotante de card.
            gradient: CceGradients.cardSurface(CceColors.neoBase),
            borderRadius: BorderRadius.circular(54),
            border: Border.all(color: CceColors.cardBevel, width: 1),
            boxShadow: CceShadows.cardFloat(),
          ),
          child: Column(
            children: [
              // ── Fila superior: Power (rojo) + Mic ─────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Power: NO gatea por online (despierta el TV desde standby).
                  _RoundKey(
                    svg: CceIcons.power,
                    accent: CceColors.danger,
                    semantic: 'Encender / Apagar',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      service.togglePower();
                    },
                  ),
                  // Mic/Voz: visual / no-op (no hay backend de voz).
                  _RoundKey(
                    icon: Icons.mic_none_rounded,
                    semantic: 'Voz (no disponible)',
                    onTap: () => HapticFeedback.selectionClick(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── D-PAD GRANDE + OK central (elemento dominante) ────────────
              _DPad(
                enabled: online,
                onUp: () => _key(service, TvRemoteKeys.up),
                onDown: () => _key(service, TvRemoteKeys.down),
                onLeft: () => _key(service, TvRemoteKeys.left),
                onRight: () => _key(service, TvRemoteKeys.right),
                onOk: () => _key(service, TvRemoteKeys.ok),
              ),
              const SizedBox(height: 22),

              // ── Fila de utilidades (4 en una línea): Guía · Home · Back ·
              //    123. El mute NO va acá (vive al centro del rocker VOL) para
              //    no duplicarlo en la misma pantalla.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Guía / Playback → abre sheet de fuentes + transport.
                  _RoundKey(
                    icon: Icons.subscriptions_outlined,
                    semantic: 'Guía / Fuentes',
                    onTap: () => _openSourcesSheet(context, service),
                  ),
                  // Home: NO gatea por online (despierta el TV).
                  _RoundKey(
                    icon: Icons.home_rounded,
                    semantic: 'Home',
                    onTap: () => _key(service, TvRemoteKeys.home, gate: false),
                  ),
                  // Return / Back.
                  _RoundKey(
                    icon: Icons.keyboard_return_rounded,
                    semantic: 'Volver',
                    enabled: online,
                    onTap: () => _key(service, TvRemoteKeys.back),
                  ),
                  // 123 → teclado numérico.
                  _RoundKey(
                    label: '123',
                    semantic: 'Teclado numérico',
                    onTap: () => _openNumPad(context, service),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Rockers píldora: VOLUMEN (con mute al centro) · CANAL ──────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Píldora fina centrada en la columna izquierda (VOL).
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 86),
                        child: _Rocker(
                          label: 'VOL',
                          topIcon: Icons.add_rounded,
                          bottomIcon: Icons.remove_rounded,
                          // Centro: mute (igual que el control físico).
                          centerSvg: service.muted
                              ? CceIcons.volumeX
                              : CceIcons.volume2,
                          centerActive: service.muted,
                          enabled: online,
                          onTop: () {
                            HapticFeedback.selectionClick();
                            service.volumeUp();
                          },
                          onBottom: () {
                            HapticFeedback.selectionClick();
                            service.volumeDown();
                          },
                          onCenter: () {
                            HapticFeedback.selectionClick();
                            service.toggleMute();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  // Píldora fina centrada en la columna derecha (CH).
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 86),
                        child: _Rocker(
                          label: 'CH',
                          topIcon: Icons.keyboard_arrow_up_rounded,
                          bottomIcon: Icons.keyboard_arrow_down_rounded,
                          // Centro: lista de canales (visual → 123 / guía).
                          centerIcon: Icons.menu_rounded,
                          enabled: online,
                          onTop: () {
                            HapticFeedback.selectionClick();
                            service.channelUp();
                          },
                          onBottom: () {
                            HapticFeedback.selectionClick();
                            service.channelDown();
                          },
                          onCenter: () => _openNumPad(context, service),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Accesos directos de apps (con color de marca) ─────────────
              _AppShortcuts(service: service),
              const SizedBox(height: 14),

              // ── Wordmark SAMSUNG ──────────────────────────────────────────
              Text(
                'SAMSUNG',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.2,
                  color: CceColors.textTertiary,
                  shadows: const [
                    Shadow(
                      color: Color(0x66FFFFFF),
                      offset: Offset(-0.6, -0.8),
                      blurRadius: 0.6,
                    ),
                    Shadow(
                      color: Color(0xCC05060A),
                      offset: Offset(0.8, 1.2),
                      blurRadius: 1.4,
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  /// Envía una tecla del remote con háptico. `gate`=true atenúa la acción si el
  /// TV está offline (las teclas de navegación no tienen sentido en standby);
  /// `gate`=false la permite igual (power/home despiertan el TV).
  void _key(TvService service, String id, {bool gate = true}) {
    if (gate && !online) return;
    HapticFeedback.selectionClick();
    service.sendKey(id);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  D-PAD
// ════════════════════════════════════════════════════════════════════════════

/// D-pad circular grande, neumórfico: anillo hundido con 4 flechas y un OK
/// central extruido. Es el elemento dominante del control.
class _DPad extends StatelessWidget {
  const _DPad({
    required this.enabled,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
  });

  final bool enabled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    const double diameter = 212;
    const double okSize = 90;
    final Color glyph =
        enabled ? CceColors.neoText : CceColors.neoTextSub;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillo hundido (pista del dpad).
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              boxShadow: CceShadows.neoInset(blur: 14, offset: 5),
            ),
          ),
          // Flechas direccionales (zonas táctiles a los 4 lados).
          Positioned(
            top: 12,
            child: _DPadArrow(
              icon: Icons.keyboard_arrow_up_rounded,
              color: glyph,
              onTap: enabled ? onUp : null,
              semantic: 'Arriba',
            ),
          ),
          Positioned(
            bottom: 12,
            child: _DPadArrow(
              icon: Icons.keyboard_arrow_down_rounded,
              color: glyph,
              onTap: enabled ? onDown : null,
              semantic: 'Abajo',
            ),
          ),
          Positioned(
            left: 12,
            child: _DPadArrow(
              icon: Icons.keyboard_arrow_left_rounded,
              color: glyph,
              onTap: enabled ? onLeft : null,
              semantic: 'Izquierda',
            ),
          ),
          Positioned(
            right: 12,
            child: _DPadArrow(
              icon: Icons.keyboard_arrow_right_rounded,
              color: glyph,
              onTap: enabled ? onRight : null,
              semantic: 'Derecha',
            ),
          ),
          // OK central extruido.
          _PressFx(
            onTap: enabled ? onOk : null,
            builder: (t) => Container(
              width: okSize,
              height: okSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: CceGradients.cardSurface(CceColors.neoBase),
                boxShadow: enabled
                    ? _lerp(
                        CceShadows.neo(blur: 12, offset: 5),
                        CceShadows.neoInset(blur: 8, offset: 3),
                        t,
                      )
                    : const [],
              ),
              child: Text(
                'OK',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: glyph,
                  shadows: enabled ? CceText.embossShadows : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zona táctil de una flecha del d-pad (sin relieve propio: la pista hundida ya
/// da el volumen; sólo el glyph + háptico al tocar).
class _DPadArrow extends StatelessWidget {
  const _DPadArrow({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.semantic,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return _PressFx(
      onTap: onTap,
      builder: (t) => Semantics(
        button: true,
        label: semantic,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(icon, size: 34, color: color),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ROCKERS (píldoras VOL / CH)
// ════════════════════════════════════════════════════════════════════════════

/// Rocker alargado tipo píldora con tres zonas: superior (+/∧), centro
/// (mute/lista) e inferior (−/∨). Carcasa hundida con label abajo.
class _Rocker extends StatelessWidget {
  const _Rocker({
    required this.label,
    required this.topIcon,
    required this.bottomIcon,
    required this.enabled,
    required this.onTop,
    required this.onBottom,
    this.onCenter,
    this.centerIcon,
    this.centerSvg,
    this.centerActive = false,
  });

  final String label;
  final IconData topIcon;
  final IconData bottomIcon;
  final bool enabled;
  final VoidCallback onTop;
  final VoidCallback onBottom;
  final VoidCallback? onCenter;
  final IconData? centerIcon;
  final String? centerSvg;
  final bool centerActive;

  @override
  Widget build(BuildContext context) {
    final Color glyph =
        enabled ? CceColors.neoText : CceColors.neoTextSub;
    final Color centerColor =
        centerActive ? CceColors.info : CceColors.neoTextSub;

    // Separador fino entre zonas (da el look "rocker segmentado").
    Widget divider() => Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 22),
          color: CceColors.cardBevel,
        );

    // Botón central en RELIEVE (mute en VOL / lista en CH): destaca sobre la
    // píldora hundida; se tiñe de info cuando está activo (muteado).
    final Widget center = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: CceGradients.cardSurface(
          centerActive ? CceColors.info.withValues(alpha: 0.18) : CceColors.neoBase,
        ),
        boxShadow: CceShadows.neo(blur: 8, offset: 3),
      ),
      child: Center(
        child: centerSvg != null
            ? CceIcon(centerSvg!, size: 20, color: centerColor)
            : Icon(centerIcon ?? Icons.circle_outlined,
                size: 20, color: centerColor),
      ),
    );

    return Column(
      children: [
        Container(
          // Píldora hundida con gradiente sutil + bisel: más profundidad.
          decoration: BoxDecoration(
            gradient: CceGradients.cardSurface(CceColors.neoBase),
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: CceShadows.neoInset(blur: 12, offset: 5),
            border: Border.all(color: CceColors.cardBevel, width: 1),
          ),
          child: Column(
            children: [
              _RockerZone(
                height: 52,
                onTap: enabled ? onTop : null,
                child: Icon(topIcon, size: 28, color: glyph),
              ),
              divider(),
              _RockerZone(
                height: 54,
                onTap: onCenter,
                child: center,
              ),
              divider(),
              _RockerZone(
                height: 52,
                onTap: enabled ? onBottom : null,
                child: Icon(bottomIcon, size: 28, color: glyph),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: CceColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Una zona táctil de un rocker (sin relieve propio: la píldora hundida da el
/// volumen). Escala/háptico al tocar vía [_PressFx].
class _RockerZone extends StatelessWidget {
  const _RockerZone({required this.child, required this.onTap, this.height = 56});

  final Widget child;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _PressFx(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Center(child: child),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ACCESOS DE APPS
// ════════════════════════════════════════════════════════════════════════════

/// Fila de 4 accesos directos de apps con color de marca, espejo del control
/// real (Netflix, Prime Video, YouTube, www). Cada tap → launchApp con el appId
/// canónico; www queda visual (no hay appId de browser). launchApp NO gatea por
/// online (lanzar una app despierta el TV).
class _AppShortcuts extends StatelessWidget {
  const _AppShortcuts({required this.service});

  final TvService service;

  @override
  Widget build(BuildContext context) {
    final active = service.app; // appId de la app en foco (resalta el botón).
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _AppKey(
          label: 'NETFLIX',
          brand: const Color(0xFFE50914),
          highlighted: active == TvApps.netflix,
          onTap: () {
            HapticFeedback.selectionClick();
            service.launchApp(TvApps.netflix);
          },
        ),
        _AppKey(
          label: 'prime',
          brand: const Color(0xFF00A8E1),
          highlighted: active == TvApps.prime,
          onTap: () {
            HapticFeedback.selectionClick();
            service.launchApp(TvApps.prime);
          },
        ),
        _AppKey(
          label: 'YouTube',
          brand: const Color(0xFFFF0000),
          highlighted: active == TvApps.youtube,
          onTap: () {
            HapticFeedback.selectionClick();
            service.launchApp(TvApps.youtube);
          },
        ),
        // www: visual (no hay appId de browser). Sólo háptico.
        _AppKey(
          label: 'www',
          brand: CceColors.textSecondary,
          highlighted: false,
          onTap: () => HapticFeedback.selectionClick(),
        ),
      ],
    );
  }
}

/// Botón de app: pastilla neumórfica raised con el wordmark de la marca en su
/// color. Se hunde y resalta con un borde de marca si está en foco.
class _AppKey extends StatelessWidget {
  const _AppKey({
    required this.label,
    required this.brand,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final Color brand;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    return _PressFx(
      onTap: onTap,
      builder: (t) => Container(
        width: 66,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(12),
          border: highlighted
              ? Border.all(color: brand.withValues(alpha: 0.9), width: 1.5)
              : Border.all(color: CceColors.cardBevel, width: 1),
          boxShadow: _lerp(raised, inset, t),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: brand,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BOTONES REDONDOS / UTILIDADES
// ════════════════════════════════════════════════════════════════════════════

/// Botón circular neumórfico raised genérico del anillo de utilidades. Acepta un
/// SVG de [CceIcons], un [IconData] de Material, o un [label] de texto (123).
/// `enabled`=false ⇒ plano, glyph atenuado. `active`=true ⇒ glyph en acento info
/// (p.ej. mute encendido). `accent` tiñe el glyph (p.ej. power en rojo).
class _RoundKey extends StatelessWidget {
  const _RoundKey({
    this.svg,
    this.icon,
    this.label,
    required this.semantic,
    required this.onTap,
    this.enabled = true,
    this.active = false,
    this.accent,
    this.size = 52,
  });

  final String? svg;
  final IconData? icon;
  final String? label;
  final String semantic;
  final VoidCallback? onTap;
  final bool enabled;
  final bool active;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    final Color glyph = !enabled
        ? CceColors.neoTextSub
        : (accent ?? (active ? CceColors.info : CceColors.neoText));

    Widget content;
    if (label != null) {
      content = Text(
        label!,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: glyph,
        ),
      );
    } else if (svg != null) {
      content = CceIcon(svg!, size: size * 0.42, color: glyph);
    } else {
      content = Icon(icon, size: size * 0.46, color: glyph);
    }

    return _PressFx(
      onTap: enabled ? onTap : null,
      builder: (t) => Semantics(
        button: true,
        label: semantic,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CceColors.neoBase,
            boxShadow: enabled ? _lerp(raised, inset, t) : const [],
          ),
          child: content,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BANNERS / ERRORES
// ════════════════════════════════════════════════════════════════════════════

/// Cartel "Sin conexión": el TV respondió pero está apagado/inalcanzable. El
/// control igual se monta (atenuado) porque varias teclas lo despiertan.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CceColors.neoBase,
        borderRadius: BorderRadius.circular(CceRadii.control),
        boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
      ),
      child: Row(
        children: [
          const StatusDotFallback(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Sin conexión',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CceColors.textSecondary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'El TV está en espera o inalcanzable. Power, Home y las apps '
                  'igual pueden despertarlo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: CceColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dot estático gris (sin import extra de StatusDot animado para un cartel).
class StatusDotFallback extends StatelessWidget {
  const StatusDotFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: CceColors.textTertiary,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Pantalla de error de servidor (sin estado conocido): no se pudo hablar con la
/// API CCE. Cartel + reintentar.
class _ServerError extends StatelessWidget {
  const _ServerError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CceIcon(CceIcons.tv,
                size: 48, color: CceColors.textTertiary),
            const SizedBox(height: 16),
            const Text(
              'No se pudo conectar al servidor',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: CceColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisá la conexión con la API CCE.',
              textAlign: TextAlign.center,
              style: CceText.caption,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: CceColors.info),
              label: const Text('Reintentar',
                  style: TextStyle(color: CceColors.info)),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TECLADO NUMÉRICO (sheet)
// ════════════════════════════════════════════════════════════════════════════

/// Abre el teclado numérico (digit0-9 + enter) como bottom-sheet. Cada dígito →
/// sendKey(digit(n)); ✓ → sendKey('ok') (enter/confirmar canal).
void _openNumPad(BuildContext context, TvService service) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: CceColors.neoBase,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (_) => _NumPadSheet(service: service),
  );
}

class _NumPadSheet extends StatelessWidget {
  const _NumPadSheet({required this.service});

  final TvService service;

  void _digit(int n) {
    HapticFeedback.selectionClick();
    service.sendKey(TvRemoteKeys.digit(n));
  }

  @override
  Widget build(BuildContext context) {
    // 1..9, luego (vacío, 0, ✓).
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Teclado', style: CceText.title),
            const SizedBox(height: 20),
            for (var row = 0; row < 3; row++) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var col = 1; col <= 3; col++)
                    _NumKey(
                      label: '${row * 3 + col}',
                      onTap: () => _digit(row * 3 + col),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Fila final: back · 0 · enter(ok).
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NumKey(
                  icon: Icons.backspace_outlined,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    service.sendKey(TvRemoteKeys.back);
                  },
                ),
                _NumKey(label: '0', onTap: () => _digit(0)),
                _NumKey(
                  icon: Icons.check_rounded,
                  accent: CceColors.info,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    service.sendKey(TvRemoteKeys.ok);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tecla del teclado numérico: pastilla redonda neumórfica raised.
class _NumKey extends StatelessWidget {
  const _NumKey({this.label, this.icon, this.accent, required this.onTap});

  final String? label;
  final IconData? icon;
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    final color = accent ?? CceColors.neoText;
    return _PressFx(
      onTap: onTap,
      builder: (t) => Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase,
          boxShadow: _lerp(raised, inset, t),
        ),
        child: label != null
            ? Text(
                label!,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              )
            : Icon(icon, size: 26, color: color),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHEET DE FUENTES / TRANSPORT (Guía)
// ════════════════════════════════════════════════════════════════════════════

/// Abre el sheet de fuentes (inputs/HDMI, incluye "JBL Bar1000M2") + transport
/// (play/pause/stop). Las fuentes salen del status (`service.inputs`); si está
/// vacío, cae a getTvInputs() directo.
void _openSourcesSheet(BuildContext context, TvService service) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: CceColors.neoBase,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (_) => _SourcesSheet(service: service),
  );
}

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.service});

  final TvService service;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final inputs = service.inputs;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Text('Fuentes y reproducción',
                        style: CceText.title)),
                const SizedBox(height: 20),
                const _SheetLabel('FUENTES'),
                const SizedBox(height: 12),
                if (inputs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Sin fuentes disponibles',
                        style: CceText.caption),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final input in inputs)
                        _SourceChip(
                          input: input,
                          selected: service.input == input.id,
                          enabled: service.canCommand,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            service.setInput(input.id);
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                const _SheetLabel('REPRODUCCIÓN'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundKey(
                      icon: Icons.skip_previous_rounded,
                      semantic: 'Anterior',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        service.trackPrev();
                      },
                    ),
                    _RoundKey(
                      icon: Icons.play_arrow_rounded,
                      semantic: 'Reproducir',
                      active: service.playback == 'play',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        service.setPlayback('play');
                      },
                    ),
                    _RoundKey(
                      icon: Icons.pause_rounded,
                      semantic: 'Pausa',
                      active: service.playback == 'pause',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        service.setPlayback('pause');
                      },
                    ),
                    _RoundKey(
                      icon: Icons.stop_rounded,
                      semantic: 'Detener',
                      active: service.playback == 'stop',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        service.setPlayback('stop');
                      },
                    ),
                    _RoundKey(
                      icon: Icons.skip_next_rounded,
                      semantic: 'Siguiente',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        service.trackNext();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Chip de fuente/HDMI: seleccionado ⇒ borde + glyph en acento info.
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.input,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TvInput input;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = !enabled
        ? CceColors.neoTextSub
        : (selected ? CceColors.info : CceColors.neoText);
    return _PressFx(
      onTap: enabled ? onTap : null,
      builder: (t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: selected
              ? Border.all(color: CceColors.info.withValues(alpha: 0.8), width: 1.5)
              : Border.all(color: CceColors.cardBevel, width: 1),
          boxShadow: selected
              ? CceShadows.neoInset(blur: 6, offset: 2)
              : _lerp(
                  CceShadows.neo(blur: 8, offset: 3),
                  CceShadows.neoInset(blur: 6, offset: 2),
                  t,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CceIcon(CceIcons.hdmi, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              input.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de sección dentro de un sheet (mismo estilo que CceText.section).
class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: CceText.section);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HELPERS COMPARTIDOS
// ════════════════════════════════════════════════════════════════════════════

/// Interpola dos pares de sombra (raised ↔ inset) por `t` (0..1) — gemelo del
/// helper privado de cce_neo_button, replicado acá para el hundido animado de
/// los botones de este archivo.
List<BoxShadow> _lerp(List<BoxShadow> a, List<BoxShadow> b, double t) {
  final n = math.min(a.length, b.length);
  return [for (var i = 0; i < n; i++) BoxShadow.lerp(a[i], b[i], t)!];
}

/// Gesto neumórfico ligero (escala + háptico + reacción de relieve vía builder).
/// Equivalente reducido de CceNeoPress, pero acá lo replicamos para tener tanto
/// la variante `child` (sólo escala) como `builder(t)` (relieve raised→inset)
/// sin acoplar este archivo a detalles internos del componente compartido.
/// `onTap == null` ⇒ deshabilitado (sin gesto, sin escala).
class _PressFx extends StatefulWidget {
  const _PressFx({this.child, this.builder, required this.onTap})
      : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(double t)? builder;
  final VoidCallback? onTap;

  @override
  State<_PressFx> createState() => _PressFxState();
}

class _PressFxState extends State<_PressFx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 0,
  );

  bool get _enabled => widget.onTap != null;

  void _press() => _c.animateTo(1,
      duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
  void _release() => _c.animateBack(0,
      duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final t = _c.value;
        final w = widget.builder != null ? widget.builder!(t) : widget.child!;
        final s = 1 - 0.06 * t; // hundido sutil (0.94 a fondo).
        return Transform.scale(scale: s, child: w);
      },
    );

    if (!_enabled) {
      // Deshabilitado: atenúa al 45% para leerse "apagado" sin desmontar.
      return Opacity(opacity: 0.45, child: core);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.onTap,
      child: core,
    );
  }
}
