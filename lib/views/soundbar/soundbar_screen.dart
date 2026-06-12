import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/jbl_status.dart';
import '../../services/jbl_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/brightness_slider.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/section_header.dart';
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
      appBar: AppBar(
        toolbarHeight: 64,
        title: const Text('Sonido', style: CceText.display),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: CceColors.textSecondary),
            tooltip: 'Configurar IP',
            onPressed: () => showIpDialog(context, service),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: CceColors.textSecondary),
            tooltip: 'Actualizar',
            onPressed: service.refresh,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) => _buildBody(context, service),
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
    // inalcanzable a nivel UPnP). Las radios SÍ se muestran (server-side).
    if (!service.online) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _OfflineCard(
            service: service,
            onConfigureIp: () => showIpDialog(context, service),
          ),
          const SectionHeader(title: 'Radios'),
          _RadioList(service: service),
        ],
      );
    }

    // Rama 4: online — controles completos.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SoundbarHeaderCard(service: service),
        const SizedBox(height: 12),
        _VolumeCard(service: service),
        const SizedBox(height: 12),
        _PowerButton(service: service),
        SectionHeader(
          title: 'Radios',
          trailing: TextButton(
            onPressed: service.canCommand
                ? () => _handle(service.saveCurrentRadio(), context)
                : null,
            child: const Text('Guardar la actual'),
          ),
        ),
        _RadioList(service: service),
      ],
    );
  }
}
