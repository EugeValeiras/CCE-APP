// Parte de la librería de soundbar_screen.dart: así los sub-widgets privados
// (`_SoundbarHeaderCard`, etc.) y los helpers (`_handle`, `showIpDialog`)
// quedan visibles para la pantalla sin exportarse al resto de la app.
part of 'soundbar_screen.dart';

/// Sub-widgets del panel de Soundbar (PAQUETE C2). Privados al paquete: los
/// usa solo soundbar_screen.dart. Todos reciben el [JblService] y/o callbacks.
///
/// Todos los comandos pasan por [_handle] para reportar 502/fallos vía
/// SnackBar sin asumir éxito (los comandos del service devuelven bool).

/// Ejecuta un comando y muestra un SnackBar si devolvió false (falló/ignorado).
Future<void> _handle(Future<bool> action, BuildContext context) async {
  final ok = await action;
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo completar la acción')),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// Card de cabecera: ícono del parlante, nombre, estado de encendido y la
/// fuente actual (si la hay).
class _SoundbarHeaderCard extends StatelessWidget {
  const _SoundbarHeaderCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final String powerLabel;
    final Color dotColor;
    switch (service.status?.power) {
      case 'on':
        powerLabel = 'Encendido';
        dotColor = CceColors.ok;
        break;
      case 'off':
        powerLabel = 'En espera';
        dotColor = CceColors.textTertiary;
        break;
      default:
        powerLabel = 'Desconocido';
        dotColor = CceColors.textTertiary;
    }
    // [CRÍTICA-13] capturar en local: null-promotion no aplica a getters.
    final src = service.source;

    return CceCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: CceColors.surfaceHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: CceIcon(
              CceIcons.speaker,
              size: 32,
              color: service.isOn ? CceColors.accent : CceColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.displayName,
                  style: CceText.title,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusDot(
                      dotColor,
                      pulse: service.isOn,
                      semanticLabel: powerLabel,
                    ),
                    const SizedBox(width: 8),
                    Text(powerLabel, style: CceText.caption),
                    if (src != null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: StatusPill(label: src)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Remote Control (grilla neumórfica de 2 columnas) ────────────────────────

/// Grilla del control remoto: 2 columnas que replican el remote oficial del
/// JBL. Cada botón circular es un [CceNeoSvgIconButton] (variante SVG icons0,
/// NO toca los defaults de [CceNeoIconButton]). El fondo es transparente: la
/// pantalla ya pinta [CceColors.neoBase].
///
/// Power/Vol/Mute reusan los métodos existentes del service; el resto de las
/// teclas van por `sendRemoteKey(id)`; el Heart/favorito por `playRadio()`.
class _RemoteGrid extends StatelessWidget {
  const _RemoteGrid({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final muted = service.muted;
    final isOn = service.isOn;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Botones GRANDES: ~64% del ancho de media columna, acotado para que
        // se vean generosos tanto en teléfono como en iPad.
        final cell = constraints.maxWidth / 2;
        final btnSize = (cell * 0.64).clamp(96.0, 148.0).toDouble();

        // Cada fila = par de celdas (izquierda, derecha). null = celda vacía.
        final rows = <List<Widget?>>[
          [
            _PowerKey(service: service, isOn: isOn, size: btnSize),
            _RemoteKeyButton(
              svg: CceIcons.tv,
              label: 'TV',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.tv), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.plus,
              label: 'Vol +',
              size: btnSize,
              onTap: () => _handle(service.nudgeVolume(5), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.minus,
              label: 'Vol −',
              size: btnSize,
              onTap: () => _handle(service.nudgeVolume(-5), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.bluetooth,
              label: 'Bluetooth',
              size: btnSize,
              onTap: () => _handle(
                  service.sendRemoteKey(JblRemoteKeys.bluetooth), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.hdmi,
              label: 'HDMI',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.hdmi), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: muted ? CceIcons.volumeX : CceIcons.volume2,
              label: muted ? 'Silenciado' : 'Mute',
              iconColor: muted ? CceColors.danger : null,
              size: btnSize,
              onTap: () => _handle(service.toggleMute(), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.play,
              label: 'Play',
              size: btnSize,
              onTap: () => _handle(
                  service.sendRemoteKey(JblRemoteKeys.playpause), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.atmos,
              label: 'ATMOS',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.atmos), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.heart,
              label: 'Favorito',
              iconColor: CceColors.danger,
              size: btnSize,
              onTap: () => _handle(service.playRadio(), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.bass,
              label: 'BASS',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.bass), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.calibrate,
              label: 'CALIBR',
              size: btnSize,
              onTap: () => _handle(
                  service.sendRemoteKey(JblRemoteKeys.calibrate), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.rear,
              label: 'REAR',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.rear), context),
            ),
            _RemoteKeyButton(
              svg: CceIcons.surround,
              label: 'Surround',
              size: btnSize,
              onTap: () => _handle(
                  service.sendRemoteKey(JblRemoteKeys.surround), context),
            ),
          ],
          [
            _RemoteKeyButton(
              svg: CceIcons.smart,
              label: 'Smart',
              size: btnSize,
              onTap: () =>
                  _handle(service.sendRemoteKey(JblRemoteKeys.smart), context),
            ),
            null,
          ],
        ];

        return Column(
          children: [
            for (final row in rows) ...[
              Row(
                children: [
                  Expanded(
                    child: Center(child: row[0] ?? const SizedBox.shrink()),
                  ),
                  Expanded(
                    child: Center(child: row[1] ?? const SizedBox.shrink()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}

/// Celda del remote: botón circular neumórfico SVG + label opcional debajo.
class _RemoteKeyButton extends StatelessWidget {
  const _RemoteKeyButton({
    required this.svg,
    required this.onTap,
    this.label,
    this.iconColor,
    this.size = 96,
  });

  final String svg;
  final String? label;
  final Color? iconColor;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CceNeoSvgIconButton(
          svg: svg,
          tooltip: label,
          iconColor: iconColor,
          size: size,
          onPressed: onTap,
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: CceText.caption.copyWith(color: CceColors.neoTextSub),
          ),
        ],
      ],
    );
  }
}

/// Celda Power: envuelve el [CceNeoSvgIconButton] con el glow on cuando la
/// barra está encendida (reusa el patrón del antiguo _PowerButton).
class _PowerKey extends StatelessWidget {
  const _PowerKey({
    required this.service,
    required this.isOn,
    this.size = 96,
  });

  final JblService service;
  final bool isOn;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isOn ? CceShadows.glowOn(CceColors.ok) : null,
          ),
          child: CceNeoSvgIconButton(
            svg: CceIcons.power,
            tooltip: isOn ? 'Apagar' : 'Encender',
            iconColor: isOn ? CceColors.ok : null,
            size: size,
            onPressed: () => _handle(service.togglePower(), context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isOn ? 'Apagar' : 'Power',
          style: CceText.caption.copyWith(color: CceColors.neoTextSub),
        ),
      ],
    );
  }
}

// ── Sintonización (botón + bottom sheet de radios) ──────────────────────────

/// Botón "Sintonización": abre el bottom sheet neumórfico con las radios.
class _TuningButton extends StatelessWidget {
  const _TuningButton({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CceNeoActionButton(
        label: 'Sintonización',
        onPressed: () {
          HapticFeedback.selectionClick();
          _openRadioSheet(context, service);
        },
      ),
    );
  }
}

/// Bottom sheet neumórfico (fondo neoBase) con las radios guardadas: tocar
/// reproduce, mantener presionado borra (con confirmación). Funciona online y
/// offline (las radios son server-side) — NO se gatea por online.
Future<void> _openRadioSheet(BuildContext context, JblService service) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: CceColors.neoBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
    ),
    builder: (sheetCtx) {
      // El sheet escucha al service para reflejar guardar/borrar radios.
      return AnimatedBuilder(
        animation: service,
        builder: (context, _) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CceColors.neoTextSub,
                      borderRadius: BorderRadius.circular(CceRadii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Sintonización', style: CceText.title),
                    ),
                    TextButton(
                      onPressed: () =>
                          _handle(service.saveCurrentRadio(), context),
                      child: const Text('Guardar la actual'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(child: _RadioList(service: service, sheet: true)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── Radios ──────────────────────────────────────────────────────────────────

/// Lista de radios guardadas. Cada item reproduce al tocar y se borra con
/// long-press (con confirmación). Funciona aún con la barra offline
/// (server-side); el 502 se reporta vía SnackBar.
class _RadioList extends StatelessWidget {
  const _RadioList({required this.service, this.sheet = false});

  final JblService service;

  /// Cuando se monta dentro del bottom sheet: lista scrolleable y al tocar una
  /// radio se cierra el sheet.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final radios = service.radios;
    if (radios.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Sin radios guardadas', style: CceText.caption),
      );
    }
    // [CRÍTICA-13] capturar en local antes de comparar con cada item.
    final src = service.source;

    final tiles = <Widget>[
      for (final r in radios) ...[
        _RadioTile(
          radio: r,
          playing: src != null && src == r.name,
          onTap: () {
            _handle(service.playRadio(r.name), context);
            if (sheet) Navigator.of(context).maybePop();
          },
          onLongPress: () => _confirmDelete(context, r),
        ),
        const SizedBox(height: 12),
      ],
    ];

    if (sheet) {
      return ListView(shrinkWrap: true, children: tiles);
    }
    return Column(children: tiles);
  }

  Future<void> _confirmDelete(BuildContext context, JblRadio r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar radio'),
        content: Text('¿Eliminar "${r.name}" de las radios guardadas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _handle(service.deleteRadio(r.name), context);
    }
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.radio,
    required this.playing,
    required this.onTap,
    required this.onLongPress,
  });

  final JblRadio radio;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          CceIcon(
            CceIcons.radio,
            size: 22,
            color: playing ? CceColors.ok : CceColors.textSecondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              radio.name,
              style: CceText.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (playing) ...[
            const SizedBox(width: 8),
            const StatusDot(
              CceColors.ok,
              pulse: true,
              semanticLabel: 'Reproduciendo',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Estados de error / offline ──────────────────────────────────────────────

/// [CRÍTICA-10] Fallo real de red/servidor: el API CCE no respondió. NO se
/// muestran radios ni IP (no hay backend).
class _ServerErrorCard extends StatelessWidget {
  const _ServerErrorCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CceIcon(CceIcons.speaker, size: 32, color: CceColors.danger),
          const SizedBox(height: 12),
          const Text('No se pudo conectar al servidor', style: CceText.title),
          const SizedBox(height: 8),
          Text('Revisá la conexión con el API de CCE.', style: CceText.caption),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: service.refresh,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

/// [CRÍTICA-10] La barra respondió pero está en standby/inalcanzable a nivel
/// UPnP. Distinto de un fallo de servidor: las radios SÍ se muestran abajo.
class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.service, required this.onConfigureIp});

  final JblService service;
  final VoidCallback onConfigureIp;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CceIcon(CceIcons.speaker, size: 32, color: CceColors.textTertiary),
          const SizedBox(height: 12),
          const Text('Soundbar fuera de línea', style: CceText.title),
          const SizedBox(height: 8),
          Text(
            'No se encontró el JBL en la red. Verificá que esté encendido '
            'o configurá su IP.',
            style: CceText.caption,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: service.refresh,
                child: const Text('Reintentar'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onConfigureIp,
                child: const Text('Configurar IP'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Diálogo de configuración de IP ──────────────────────────────────────────

/// [CRÍTICA E3] La config de IP del JBL vive en la pantalla de Soundbar.
/// Prellenado capturando la IP actual en local [CRÍTICA-13].
Future<void> showIpDialog(BuildContext context, JblService service) async {
  final currentIp = service.status?.ip;
  final controller = TextEditingController(text: currentIp ?? '');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('IP del soundbar'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Dirección IP',
          hintText: '192.168.1.103',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          onPressed: () {
            final ip = controller.text.trim();
            Navigator.of(ctx).pop();
            _handle(service.setIp(ip), context);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
