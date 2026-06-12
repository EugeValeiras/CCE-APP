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

// ── Volumen ─────────────────────────────────────────────────────────────────

/// Card de volumen: slider 0..100, botones −/+ y botón mute. Si el transporte
/// UPnP de volumen falló ([JblService.hasVolume] == false) se atenúa el slider
/// y se muestra "Volumen no disponible".
class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final hasVolume = service.hasVolume;
    final muted = service.muted;

    return CceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Volumen', style: CceText.caption),
              const Spacer(),
              if (hasVolume)
                Text(
                  '${service.volume}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CceColors.textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasVolume) ...[
            CceBrightnessSlider(
              value: (service.volume / 100).clamp(0.0, 1.0),
              activeColor: CceColors.accent,
              onChanged: (v) => service.setVolume((v * 100).round()),
              onChangeEnd: (v) => service.setVolume((v * 100).round()),
            ),
          ] else ...[
            Opacity(
              opacity: 0.4,
              child: IgnorePointer(
                child: CceBrightnessSlider(
                  value: 0,
                  activeColor: CceColors.accent,
                  onChanged: (_) {},
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Volumen no disponible', style: CceText.caption),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _NudgeButton(
                icon: CceIcons.minus,
                semanticLabel: 'Bajar volumen',
                onTap: () {
                  HapticFeedback.selectionClick();
                  _handle(service.nudgeVolume(-5), context);
                },
              ),
              const SizedBox(width: 12),
              _NudgeButton(
                icon: CceIcons.plus,
                semanticLabel: 'Subir volumen',
                onTap: () {
                  HapticFeedback.selectionClick();
                  _handle(service.nudgeVolume(5), context);
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _handle(service.toggleMute(), context),
                icon: CceIcon(
                  muted ? CceIcons.volumeX : CceIcons.volume2,
                  size: 18,
                  color:
                      muted ? CceColors.danger : CceColors.textSecondary,
                ),
                label: Text(
                  muted ? 'Silenciado' : 'Silenciar',
                  style: TextStyle(
                    color:
                        muted ? CceColors.danger : CceColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón circular −/+ del volumen.
class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CceCard(
      color: CceColors.surfaceHigh,
      radius: CceRadii.pill,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: CceIcon(icon, size: 22, color: CceColors.textPrimary),
      ),
    );
  }
}

// ── Power ───────────────────────────────────────────────────────────────────

/// Botón de encendido/apagado del parlante. Glow suave cuando está encendido.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.service});

  final JblService service;

  @override
  Widget build(BuildContext context) {
    final isOn = service.isOn;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CceRadii.control),
        boxShadow: isOn ? CceShadows.glowOn(CceColors.ok) : null,
      ),
      child: FilledButton.tonal(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _handle(service.togglePower(), context);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CceIcon(
              CceIcons.power,
              size: 20,
              color: isOn ? CceColors.ok : CceColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Text(isOn ? 'Apagar' : 'Encender'),
          ],
        ),
      ),
    );
  }
}

// ── Radios ──────────────────────────────────────────────────────────────────

/// Lista de radios guardadas. Cada item reproduce al tocar y se borra con
/// long-press (con confirmación). Funciona aún con la barra offline
/// (server-side); el 502 se reporta vía SnackBar.
class _RadioList extends StatelessWidget {
  const _RadioList({required this.service});

  final JblService service;

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

    return Column(
      children: [
        for (final r in radios) ...[
          _RadioTile(
            radio: r,
            playing: src != null && src == r.name,
            onTap: () => _handle(service.playRadio(r.name), context),
            onLongPress: () => _confirmDelete(context, r),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
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
