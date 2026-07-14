import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/room_ref.dart';
import '../../models/tv_status.dart';
import '../../services/devices_service.dart';
import '../../services/tv_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../widgets/room_temperature_header.dart';
import 'tv_app_logos.dart';

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
  const TvScreen({
    super.key,
    required this.service,
    this.devices,
    this.headerPadding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  /// El shell lo crea/dispone; la screen NO lo dispone.
  final TvService service;

  /// OPCIONAL: habilita el header de clima de la room del TV (resuelta por
  /// config: samsungTvPositions → plano → RoomRef; misma persistencia por
  /// room que la pantalla de la room). null (call-site sin DevicesService a
  /// mano) ⇒ sin header, degradación segura.
  final DevicesService? devices;

  /// Padding del header de clima. Default = ritmo phone/room_detail
  /// (16/8/16/4); el call-site INLINE del panel derecho de tablet pasa
  /// 24/4/24/4 para no saltar respecto del header de RoomPanel.
  final EdgeInsets headerPadding;

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
      // Fondo de la app (#101014), MÁS oscuro que la carcasa (neoBase) para que
      // el control FLOTE con claridad (igual que la home; #16181D quedaba casi
      // idéntico a neoBase en el OLED y no se notaba la diferencia).
      backgroundColor: CceColors.bg,
      // Sin AppBar: control full-screen. Se vuelve con el swipe iOS.
      body: SafeArea(
        child: Column(
          children: [
            // Header de clima de la room del TV (config-driven, sin room ⇒ no
            // aparece). Escucha a DevicesService con su PROPIO ListenableBuilder:
            // esta pantalla solo escucha a TvService y sin esto la temperatura
            // quedaría congelada. El FittedBox del remote absorbe el alto que
            // el header le resta al cuerpo.
            if (widget.devices != null)
              ListenableBuilder(
                listenable: widget.devices!,
                builder: (context, _) {
                  final devices = widget.devices!;
                  final room = _resolveRoom(devices);
                  if (room == null) return const SizedBox.shrink();
                  return Padding(
                    // Ritmo del call-site (default 16/8/16/4 como las rooms
                    // phone; inline en tablet el shell pasa 24/4/24/4); el
                    // body del remote conserva su padding angosto propio.
                    padding: widget.headerPadding,
                    child: RoomTemperatureHeader(
                      service: devices,
                      room: room,
                      compact: true,
                      neo: true,
                    ),
                  );
                },
              ),
            Expanded(
              child: AnimatedBuilder(
                animation: service,
                builder: (context, _) => _buildBody(context, service),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Room del TV derivada de la config (dirección device→room, inversa del
  /// lookup de room_detail_screen): primera room de plano cuyo planId tiene
  /// posicionado el TV en floorPlans.tvPositions. Se resuelve EN CADA build
  /// (service.rooms regenera los RoomRef en cada notify — no cachear). null si
  /// la config no lo posiciona o el plano no genera room visible ⇒ sin header.
  static RoomRef? _resolveRoom(DevicesService devices) {
    final fp = devices.floorPlans;
    if (fp == null || fp.tvPositions.isEmpty) return null;
    for (final room in devices.rooms) {
      final planId = room.planId;
      if (planId != null && fp.tvPositions.containsKey(planId)) return room;
    }
    return null;
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
            // CENTRADO (ambos ejes) y capeado a ~340 (como el .remote del
            // dashboard, max-width 320): en el teléfono queda angosto con aire
            // a los costados, no a ancho completo. BoxFit.contain escala para
            // usar el alto disponible (en tablet crece y queda centrado).
            child: LayoutBuilder(
              builder: (ctx, c) {
                // El control se ALARGA al alto disponible (llena la pantalla en
                // el teléfono), capeado a maxH=780 (en tablet estira un poco).
                // Piso minH para no comprimir; si la pantalla es más baja,
                // FittedBox(scaleDown) lo achica para que no desborde.
                const double w = 360, minH = 600, maxH = 780;
                final double target = c.maxHeight.clamp(minH, maxH);
                return Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: w,
                      height: target,
                      child: _RemoteBody(service: service, online: online),
                    ),
                  ),
                );
              },
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
          // CARCASA (manual dashboard): radius 40, bg neoBase PLANO, padding 22,
          // gap 22, sombra externa EXAGERADA (10/10/28 negra abajo-der + -6/-6/20
          // luz arriba-izq) para que el cuerpo flote sobre el fondo del drawer.
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [
              // 10px 10px 28px rgba(0,0,0,0.45) — caída abajo-derecha.
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 28,
                offset: Offset(10, 10),
              ),
              // -6px -6px 20px rgba(42,45,55,0.25) — luz arriba-izquierda.
              BoxShadow(
                color: Color(0x402A2D37),
                blurRadius: 20,
                offset: Offset(-6, -6),
              ),
            ],
          ),
          child: Column(
            // Distribuye las secciones para LLENAR la altura de la carcasa
            // (el control "alargado"): gaps iguales entre secciones.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

              // ── D-PAD GRANDE + OK central (elemento dominante) ────────────
              _DPad(
                enabled: online,
                onUp: () => _key(service, TvRemoteKeys.up),
                onDown: () => _key(service, TvRemoteKeys.down),
                onLeft: () => _key(service, TvRemoteKeys.left),
                onRight: () => _key(service, TvRemoteKeys.right),
                onOk: () => _key(service, TvRemoteKeys.ok),
              ),

              // ── Fila de utilidades (4 en una línea): Guía · Home · Back ·
              //    Ajustes. El mute NO va acá (vive al centro del rocker VOL);
              //    el teclado 123 se abre desde el centro del rocker CH. Apps
              //    salió de este anillo y ahora es el botón ancho de abajo.
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
                  // Return / Back: flecha que da la vuelta (como el control físico).
                  _RoundKey(
                    svg: CceIcons.returnArrow,
                    semantic: 'Volver',
                    enabled: online,
                    onTap: () => _key(service, TvRemoteKeys.back),
                  ),
                  // Ajustes (KEY_MENU del Samsung).
                  _RoundKey(
                    svg: CceIcons.settings,
                    semantic: 'Ajustes',
                    enabled: online,
                    onTap: () => _key(service, TvRemoteKeys.menu),
                  ),
                ],
              ),

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
                          // Centro: mute SIN ESTADO (solo dispara el toggle; el
                          // backend no reporta muteado). Ícono fijo, nunca activo.
                          centerSvg: CceIcons.volume2,
                          centerActive: false,
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

              // ── Botón ANCHO de aplicaciones (estilo dashboard) ────────────
              //    Reemplaza al viejo botón redondo del anillo de utilidades.
              //    NO gatea por online: lanzar una app despierta el TV desde
              //    standby (mismo comportamiento que tenía el redondo).
              _AppsWideButton(
                onTap: () => _openAppsSheet(context, service),
              ),

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
          // PLATO cóncavo del d-pad (manual dashboard): la pista SOBRESALE del
          // fondo (relieve externo) pero la cara está HUNDIDA (inset suave),
          // sobre un gradiente cóncavo 145° oscuro→claro. Antes era solo inset
          // (puro hundido); ahora es plato = neo + neoInset, como en la web.
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CceGradients.concave(CceColors.neoBase),
              boxShadow: CceShadows.plato(blur: 18, offset: 7),
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
              // OK central CONVEXO (manual dashboard): sobresale (gradiente
              // convexo claro→oscuro + SOLO sombras externas); al presionar
              // pasa a inset. Antes usaba cardSurface; ahora convex puro.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: CceGradients.convex(CceColors.neoBase),
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

    // Glyph central PLANO (mute en VOL / lista en CH): mismo tratamiento que
    // las flechas (sin disco en relieve), al ras de la píldora; se tiñe de info
    // cuando está activo (muteado).
    final Widget center = centerSvg != null
        ? CceIcon(centerSvg!, size: 28, color: centerColor)
        : Icon(centerIcon ?? Icons.circle_outlined,
            size: 28, color: centerColor);

    return Column(
      children: [
        Container(
          // Píldora CONVEXA RAISED (manual dashboard): el rocker SOBRESALE
          // (gradiente convexo + sombra externa estándar), no hundida. Réplica
          // del `.rocker` de la web (neoBase + 3/3/8 + -3/-3/8).
          decoration: BoxDecoration(
            gradient: CceGradients.convex(CceColors.neoBase),
            borderRadius: BorderRadius.circular(CceRadii.pill),
            boxShadow: CceShadows.neo(blur: 8, offset: 3),
          ),
          child: Column(
            children: [
              _RockerZone(
                height: 52,
                onTap: enabled ? onTop : null,
                child: Icon(topIcon, size: 28, color: glyph),
              ),
              _RockerZone(
                height: 54,
                onTap: onCenter,
                child: center,
              ),
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
//  BOTONES REDONDOS / UTILIDADES
// ════════════════════════════════════════════════════════════════════════════

/// Botón circular neumórfico raised genérico del anillo de utilidades. Acepta un
/// SVG de [CceIcons] o un [IconData] de Material.
/// `enabled`=false ⇒ plano, glyph atenuado. `active`=true ⇒ glyph en acento info
/// (p.ej. mute encendido). `accent` tiñe el glyph (p.ej. power en rojo).
class _RoundKey extends StatelessWidget {
  const _RoundKey({
    this.svg,
    this.icon,
    required this.semantic,
    required this.onTap,
    this.enabled = true,
    this.active = false,
    this.accent,
  });

  final String? svg;
  final IconData? icon;
  final String semantic;
  final VoidCallback? onTap;
  final bool enabled;
  final bool active;
  final Color? accent;
  final double size = 52;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    final Color glyph = !enabled
        ? CceColors.neoTextSub
        : (accent ?? (active ? CceColors.info : CceColors.neoText));

    Widget content;
    if (svg != null) {
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

/// Botón ANCHO de "Aplicaciones" (clon del `.apps-btn` del dashboard): único
/// control de ancho completo del remote, va entre los rockers y el wordmark.
/// Reposo extruido (neo) → hundido (neoInset) al presionar, vía [_PressFx]+[_lerp].
/// NO gatea por online: lanzar una app despierta el TV desde standby.
class _AppsWideButton extends StatelessWidget {
  const _AppsWideButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);

    return _PressFx(
      onTap: onTap,
      builder: (t) => Semantics(
        button: true,
        label: 'Aplicaciones',
        child: Container(
          width: double.infinity,
          // Manual dashboard `.apps-btn`: height 48, radius 14, raised → inset.
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CceColors.neoBase,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _lerp(raised, inset, t),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CceIcon(CceIcons.appsGrid, size: 20, color: CceColors.neoText),
              const SizedBox(width: 10),
              const Text(
                'Aplicaciones',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: CceColors.neoText,
                ),
              ),
            ],
          ),
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
//  SHEET DE APPS INSTALADAS (grilla)
// ════════════════════════════════════════════════════════════════════════════

/// Abre el sheet con la GRILLA de apps instaladas en el TV. Al abrir se sondea
/// service.installedApps() (GET /tv/apps/installed). Tap en un tile → launchApp
/// + cierra el sheet + háptico. launchApp NO gatea por online (lanzar una app
/// despierta el TV desde standby), por eso el sheet se abre siempre.
void _openAppsSheet(BuildContext context, TvService service) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: CceColors.neoBase,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (_) => _AppsSheet(service: service),
  );
}

/// Bottom-sheet con la grilla de apps instaladas. StatefulWidget porque sondea
/// la lista una sola vez al abrir y maneja su propio estado (cargando / datos /
/// vacío) sin tocar el TvService (que es solo para comandos + status).
class _AppsSheet extends StatefulWidget {
  const _AppsSheet({required this.service});

  final TvService service;

  @override
  State<_AppsSheet> createState() => _AppsSheetState();
}

class _AppsSheetState extends State<_AppsSheet> {
  bool _loading = true;
  List<TvInstalledApp> _apps = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // installedApps() NUNCA tira (la api garantiza [] ante error), pero
    // igualmente protegemos el setState con el guard de `mounted`.
    final apps = await widget.service.installedApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  /// Lanza la app y cierra el sheet (con háptico). No esperamos el resultado:
  /// launchApp es optimista y el sheet ya cumplió su función al elegir la app.
  void _launch(TvInstalledApp app) {
    HapticFeedback.selectionClick();
    widget.service.launchApp(app.appId);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Apps', style: CceText.title)),
            const SizedBox(height: 20),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Estado: cargando (spinner centrado).
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: CircularProgressIndicator(color: CceColors.textTertiary),
        ),
      );
    }

    // Estado: vacío (no se detectaron apps / TV apagado).
    if (_apps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'No se detectaron apps · encendé el TV',
            textAlign: TextAlign.center,
            style: CceText.caption,
          ),
        ),
      );
    }

    // Estado: datos. Grilla de tiles (color de marca + nombre). shrinkWrap +
    // never-scroll porque ya vivimos dentro de un sheet scrollable (el Column
    // con MainAxisSize.min); el isScrollControlled del sheet le da el alto.
    final active = widget.service.app; // appId en foco → resalta el tile.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: _apps.length,
      itemBuilder: (context, i) {
        final app = _apps[i];
        return _AppGridTile(
          app: app,
          highlighted: active == app.appId,
          onTap: () => _launch(app),
        );
      },
    );
  }
}

/// Tile de la grilla de apps: pastilla neumórfica raised con un punto del color
/// de marca + el nombre de la app. Se hunde al tocar y resalta con un borde de
/// marca si está en foco (mismo lenguaje visual que _AppKey / _SourceChip).
class _AppGridTile extends StatelessWidget {
  const _AppGridTile({
    required this.app,
    required this.highlighted,
    required this.onTap,
  });

  final TvInstalledApp app;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raised = CceShadows.neo(blur: 8, offset: 3);
    final inset = CceShadows.neoInset(blur: 6, offset: 2);
    // Apple TV trae un brand casi negro (#111111) que no se ve sobre la base
    // neumórfica: forzamos blanco solo para ese appId.
    final brand = app.appId == '3201807016597'
        ? const Color(0xFFFFFFFF)
        : _parseBrand(app.brand);
    return _PressFx(
      onTap: onTap,
      builder: (t) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(CceRadii.control),
          border: highlighted
              ? Border.all(color: brand.withValues(alpha: 0.9), width: 1.5)
              : Border.all(color: CceColors.cardBevel, width: 1),
          boxShadow: _lerp(raised, inset, t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo oficial de la marca (vendoreado de icons0.dev), teñido con
            // el color de marca. Si la app no tiene logo conocido (p. ej. Flow)
            // cae al lettermark con la inicial sobre el color de marca.
            _AppLogo(appId: app.appId, label: app.label, brand: brand),
            const SizedBox(height: 8),
            Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: CceColors.neoText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convierte el hex de marca ("#E50914" / "E50914" / "#FFE50914") a Color.
  /// Cae a un gris neutro si viene vacío o malformado (el contrato dice que
  /// `brand` puede no venir). El parseo vive en la vista para que el modelo
  /// quede libre de dependencias de Flutter.
  static Color _parseBrand(String hex) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h'; // sin alpha ⇒ opaco.
    final value = int.tryParse(h, radix: 16);
    if (value == null) return CceColors.textSecondary;
    return Color(value);
  }
}

/// Logo de una app del TV: el SVG oficial vendoreado ([TvAppLogos]) teñido con
/// el color de marca, o —si no tenemos logo para ese `appId`— un lettermark con
/// la inicial sobre un disco del color de marca. Tamaño fijo 36 para alinear
/// con el resto de la grilla.
class _AppLogo extends StatelessWidget {
  const _AppLogo({
    required this.appId,
    required this.label,
    required this.brand,
  });

  final String appId;
  final String label;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final svg = TvAppLogos.forAppId(appId);
    if (svg != null) {
      return SizedBox(
        width: 36,
        height: 36,
        child: SvgPicture.string(
          svg,
          width: 36,
          height: 36,
          colorFilter: ColorFilter.mode(brand, BlendMode.srcIn),
        ),
      );
    }
    // Fallback (sin logo conocido): disco de marca con la inicial.
    final initial = label.isNotEmpty ? label.substring(0, 1).toUpperCase() : '?';
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: brand,
        boxShadow: CceShadows.neo(blur: 4, offset: 2),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
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
