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

  Widget _buildBody(BuildContext context, JblService service) {
    // [CRÍTICA-10] Rama 1: fallo real de red/servidor (sin estado conocido).
    if (service.error != null && service.status == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [_ServerErrorCard(service: service)],
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
    if (!service.online) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _OfflineCard(
            service: service,
            onConfigureIp: () => showIpDialog(context, service),
          ),
          const SizedBox(height: 24),
          // Sin volumen en standby (UPnP caído): solo fuentes/accesos (varias
          // teclas despiertan la barra) + sintonización.
          const _SectionLabel('FUENTES'),
          _SourcesRow(service: service),
          const SizedBox(height: 24),
          const _SectionLabel('ACCESOS RÁPIDOS'),
          _QuickAccessGrid(service: service),
        ],
      );
    }

    // Rama 4: online — control completo (dial de volumen + fuentes + accesos).
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SoundbarHeaderCard(service: service),
        const SizedBox(height: 16),
        _VolumeDialCard(service: service),
        const SizedBox(height: 24),
        const _SectionLabel('FUENTES'),
        _SourcesRow(service: service),
        const SizedBox(height: 24),
        const _SectionLabel('ACCESOS RÁPIDOS'),
        _QuickAccessGrid(service: service),
      ],
    );
  }
}
