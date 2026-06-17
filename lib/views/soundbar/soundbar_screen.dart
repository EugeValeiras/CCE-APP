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
import '../../theme/components/status_pill.dart';

part 'soundbar_widgets.dart';

/// Pantalla de Soundbar JBL (PAQUETE C1). Entra directo en el IndexedStack
/// (tablet y phone) → tiene su propio [Scaffold].
///
/// El shell (tablet/phone) crea y dispone el [JblService] y posee el ciclo de
/// polling (arranca/para según la tab visible). Esta pantalla NO dispone el
/// service ni arranca el polling; solo hace un refresh de cortesía one-shot en
/// initState por si el shell aún no lo arrancó.
class SoundbarScreen extends StatefulWidget {
  const SoundbarScreen({super.key, required this.service});

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
      backgroundColor: CceColors.neoBase,
      // Sin AppBar: control full-screen. Se vuelve con el swipe iOS; el config de
      // IP sigue disponible desde la card de offline/error cuando hace falta.
      body: SafeArea(
        child: AnimatedBuilder(
          animation: service,
          // Centrado a ancho de celular: en iPad el control NO ocupa todo el
          // ancho (queda feo); en teléfono la pantalla es más angosta que 480
          // así que igual se ve full.
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _buildBody(context, service),
            ),
          ),
        ),
      ),
    );
  }

  /// Superficie pasiva UNIFICADA del panel: el MISMO material continuo para
  /// TODAS las ramas (online / offline / error). Mismo par color+gradiente
  /// (neoBase + CceGradients.cardSurface), mismo bevel y mismo cardFloat que la
  /// rama online — así el panel se ve de un solo material, sin saltos planos.
  /// Los wells (_NeoWell, dial) NO se aplanan: viven dentro de esta superficie.
  Widget _panel({required Widget child}) {
    return SingleChildScrollView(
      // Sin padding inferior: el panel llega hasta abajo así no se corta la
      // última fila de accesos en el teléfono (antes el bottom 16 + 18 del panel
      // empujaban la grilla fuera de pantalla).
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        decoration: BoxDecoration(
          gradient: CceGradients.cardSurface(CceColors.neoBase),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: CceColors.cardBevel),
          boxShadow: CceShadows.cardFloat(),
        ),
        child: child,
      ),
    );
  }

  Widget _buildBody(BuildContext context, JblService service) {
    // Hairline separador entre secciones dentro del panel unificado.
    Widget divider() => Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          height: 1,
          color: Colors.white.withValues(alpha: 0.05),
        );

    // [CRÍTICA-10] Rama 1: fallo real de red/servidor (sin estado conocido).
    // Mismo material continuo que online: el contenido de error va DENTRO del
    // panel unificado (no como card suelta sobre el scaffold plano).
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
    // MISMO material/panel que online (sin volumen, que requiere UPnP vivo).
    if (!service.online) {
      return _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OfflinePanel(
              service: service,
              onConfigureIp: () => showIpDialog(context, service),
            ),
            divider(),
            // Sin volumen en standby (UPnP caído): solo fuentes/accesos (varias
            // teclas despiertan la barra) + sintonización.
            const _SectionLabel('FUENTES'),
            const SizedBox(height: 10),
            _SourcesRow(service: service),
            const SizedBox(height: 18),
            const _SectionLabel('ACCESOS RÁPIDOS'),
            const SizedBox(height: 10),
            _QuickAccessGrid(service: service),
          ],
        ),
      );
    }

    // Rama 4: online — TODO el control en UN solo panel neumórfico (estilo
    // "control remoto", como la pantalla de la TV): header + dial + fuentes +
    // accesos viven dentro de la misma superficie, separados por hairlines.
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SoundbarHeaderCard(service: service),
          divider(),
          _VolumeDialCard(service: service),
          divider(),
          const _SectionLabel('FUENTES'),
          const SizedBox(height: 10),
          _SourcesRow(service: service),
          const SizedBox(height: 18),
          const _SectionLabel('ACCESOS RÁPIDOS'),
          const SizedBox(height: 10),
          _QuickAccessGrid(service: service),
        ],
      ),
    );
  }
}
