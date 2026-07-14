import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/jbl_status.dart';
import '../../services/jbl_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_neo_button.dart';
import '../../theme/components/cce_neo_press.dart';
import '../../theme/components/status_dot.dart';

part 'soundbar_widgets.dart';

/// Pantalla de Soundbar JBL (PAQUETE C1). Entra directo en el IndexedStack
/// (tablet y phone) → tiene su propio [Scaffold].
///
/// El shell (tablet/phone) crea y dispone el [JblService] y posee el ciclo de
/// polling (arranca/para según la tab visible). Esta pantalla NO dispone el
/// service ni arranca el polling; solo hace un refresh de cortesía one-shot en
/// initState por si el shell aún no lo arrancó.
class SoundbarScreen extends StatefulWidget {
  const SoundbarScreen({
    super.key,
    required this.service,
  });

  /// El shell lo crea/dispone; la screen NO lo dispone.
  final JblService service;

  @override
  State<SoundbarScreen> createState() => _SoundbarScreenState();
}

class _SoundbarScreenState extends State<SoundbarScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh defensivo de cortesía (one-shot). El ciclo de polling lo posee
    // el shell según la tab visible — ver tablet_home_view / phone_home_view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.service.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      // Fondo NORMAL de la app (CceColors.neoBase, #1C1E24) — mismo canvas que
      // el home de teléfono/tablet. Ya NO usamos el casi-negro #16181D del
      // drawer (se veía demasiado negro). La carcasa neoBase flota igual con su
      // sombra externa exagerada, como el panel del dashboard sobre su página.
      backgroundColor: _kDrawerBg,
      // Sin AppBar: control full-screen. Se vuelve con el swipe iOS; el config de
      // IP sigue disponible desde la card de offline/error cuando hace falta.
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          // Centrado a ancho de celular (≈320 como el dashboard): en iPad
          // el control NO ocupa todo el ancho (queda feo); en teléfono la
          // pantalla es más angosta así que igual se ve full.
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _buildBody(context, service),
            ),
          ),
        ),
      ),
    );
  }

  /// CARCASA del control (réplica exacta del `.panel` del dashboard): radius 40,
  /// fondo neoBase PLANO (sin gradiente), sombra EXTERNA exagerada — 10/10/28
  /// negra abajo-der + -6/-6/20 luz arriba-izq — y padding 22. NO lleva bevel ni
  /// gradiente de almohada: el cuerpo es un bloque sólido que flota sobre el
  /// fondo más oscuro del scaffold. Los materiales internos (dial cóncavo, chips
  /// convexos, wells) aportan el relieve; la carcasa solo los sostiene.
  Widget _panel({required Widget child}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: CceColors.neoBase,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            // Sombra externa abajo-derecha (exagerada): 10/10/28 negra.
            BoxShadow(
              color: Color(0x73000000), // rgba(0,0,0,0.45)
              blurRadius: 28,
              offset: Offset(10, 10),
            ),
            // Luz externa arriba-izquierda: -6/-6/20.
            BoxShadow(
              color: Color(0x402A2D37), // rgba(42,45,55,0.25)
              blurRadius: 20,
              offset: Offset(-6, -6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildBody(BuildContext context, JblService service) {
    // [CRÍTICA-10] Rama 1: fallo real de red/servidor (sin estado conocido).
    // Mismo material continuo que online: el contenido de error va DENTRO de la
    // carcasa (no como card suelta sobre el scaffold).
    if (service.error != null && service.status == null) {
      return _panel(
        child: _ServerErrorPanel(service: service),
      );
    }

    // Rama 2: primera carga, todavía sin estado.
    if (service.status == null && service.loading) {
      return const Center(
        child: CircularProgressIndicator(color: CceColors.textTertiary),
      );
    }

    // [CRÍTICA-10] Rama 3: la barra respondió pero está offline (standby /
    // inalcanzable a nivel UPnP). El remote SÍ se monta: varias teclas
    // (tv/hdmi/bluetooth/playpause) despiertan la barra desde standby
    // (sendRemoteKey no gatea por online). Las radios funcionan server-side.
    // MISMA carcasa que online (sin volumen, que requiere UPnP vivo).
    if (!service.online) {
      return _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PowerButton(service: service),
            const SizedBox(height: 22),
            _OfflinePanel(
              service: service,
              onConfigureIp: () => showIpDialog(context, service),
            ),
            const SizedBox(height: 22),
            // Sin volumen en standby (UPnP caído): solo fuentes/accesos (varias
            // teclas despiertan la barra) + sintonización.
            const _SectionLabel('FUENTES'),
            const SizedBox(height: 10),
            _SourcesRow(service: service),
            const SizedBox(height: 22),
            const _SectionLabel('ACCESOS RÁPIDOS'),
            const SizedBox(height: 10),
            _QuickAccessGrid(service: service),
            const SizedBox(height: 22),
            const _JblWordmark(),
          ],
        ),
      );
    }

    // Rama 4: online — réplica exacta del `.panel` del dashboard: power redondo
    // arriba-izquierda, dial de volumen (plato cóncavo) con su píldora de mute,
    // sección Fuentes (chips convexos) y Accesos rápidos (botones convexos),
    // logo JBL abajo. SIN header de avatar/nombre (el dashboard no lo tiene) y
    // SIN hairlines: el gap uniforme de 22 separa las secciones.
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PowerButton(service: service),
          const SizedBox(height: 22),
          _VolumeDialCard(service: service),
          const SizedBox(height: 22),
          const _SectionLabel('FUENTES'),
          const SizedBox(height: 10),
          _SourcesRow(service: service),
          const SizedBox(height: 22),
          const _SectionLabel('ACCESOS RÁPIDOS'),
          const SizedBox(height: 10),
          _QuickAccessGrid(service: service),
          const SizedBox(height: 22),
          const _JblWordmark(),
        ],
      ),
    );
  }
}
