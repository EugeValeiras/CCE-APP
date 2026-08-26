import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/phone_audio_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';

/// Los controles del audio de la llamada EN ESTE CELULAR (CCE#12).
///
/// Tres cosas, y ninguna es decorativa:
///
///  1. **Tomar y soltar.** Es la acción de la tarea entera. Mientras el audio no
///     esté acá, la llamada suena en el teléfono de la casa.
///  2. **Altavoz y mudo.** Un teléfono sin manos libres no es un teléfono, y sin
///     mudo no se puede atender un timbre en el medio de una llamada.
///  3. **Los medidores.** Sin ellos "no se escucha nada" es indebuggeable: no se
///     distingue falta de audio de falta de permiso, de un interlocutor mudo o
///     de un micrófono silenciado. Es criterio de aceptación del issue, y es lo
///     que hace que este panel sea diagnosticable a un metro de distancia.
class CallAudioPanel extends StatelessWidget {
  const CallAudioPanel({super.key, required this.audio});

  final PhoneAudioService audio;

  @override
  Widget build(BuildContext context) {
    final on = audio.isOn;
    final busy = audio.busy;

    return CceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CceIcon(
                on ? CceIcons.volume2 : CceIcons.speaker,
                size: 18,
                color: on ? CceColors.ok : CceColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      on ? 'Hablás por el celular' : 'El audio está en la casa',
                      style: CceText.label.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      on ? _outputLabel(audio.output) : audio.stateLabel,
                      style: CceText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _takeButton(on: on, busy: busy),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 10),
            _meters(),
            const SizedBox(height: 10),
            _controls(),
          ],
          if (audio.error case final message?) ...[
            const SizedBox(height: 8),
            _errorLine(message),
          ],
        ],
      ),
    );
  }

  /// El botón que trae o devuelve el audio.
  ///
  /// Tomar el audio **se lo saca a quien lo tenga** (gana el último, CCE#12), y
  /// el botón lo dice: sin eso, el usuario no entiende por qué al dashboard se
  /// le cortó la voz.
  Widget _takeButton({required bool on, required bool busy}) {
    final label = on ? 'Soltar' : 'Escuchar acá';
    return Semantics(
      button: true,
      label: on
          ? 'Soltar el audio y devolverlo al teléfono de la casa'
          : 'Traer el audio de la llamada a este celular',
      child: Tooltip(
        message: on
            ? 'La voz vuelve al teléfono de la casa'
            : 'Se lo saca a quien lo tenga (dashboard u otro celular)',
        child: FilledButton(
          onPressed: busy
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  if (on) {
                    audio.release();
                  } else {
                    audio.take();
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: on ? CceColors.surfaceTop : CceColors.accent,
            foregroundColor: on ? CceColors.textSecondary : CceColors.inkOnAmber,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            busy ? '…' : label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _meters() {
    return Column(
      children: [
        _MeterRow(
          icon: Icon(
            audio.muted ? Icons.mic_off : Icons.mic,
            size: 16,
            color: audio.muted ? CceColors.danger : CceColors.textTertiary,
          ),
          label: 'Tu voz',
          level: audio.inputLevel,
          color: CceColors.ok,
        ),
        const SizedBox(height: 6),
        _MeterRow(
          icon: const CceIcon(
            CceIcons.volume2,
            size: 16,
            color: CceColors.textTertiary,
          ),
          label: 'La línea',
          level: audio.outputLevel,
          color: CceColors.accent,
        ),
      ],
    );
  }

  Widget _controls() {
    // Con auriculares o manos libres conectados el altavoz no se ofrece: iOS ya
    // está mandando el audio ahí y forzarlo al parlante sería sacárselo de la
    // oreja al usuario sin que lo haya pedido.
    final routed = audio.output == PhoneAudioOutput.headphones ||
        audio.output == PhoneAudioOutput.bluetooth;
    return Row(
      children: [
        if (!routed)
          Expanded(
            child: _ToggleChip(
              icon: CceIcons.speaker,
              label: 'Altavoz',
              on: audio.speakerOn,
              onTap: () {
                HapticFeedback.selectionClick();
                audio.setSpeaker(!audio.speakerOn);
              },
            ),
          )
        else
          Expanded(
            child: Text(
              _outputLabel(audio.output),
              style: CceText.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: _ToggleChip(
            materialIcon: audio.muted ? Icons.mic_off : Icons.mic,
            label: audio.muted ? 'Mudo' : 'Silenciar',
            on: audio.muted,
            onColor: CceColors.danger,
            onTap: () {
              HapticFeedback.selectionClick();
              audio.setMuted(!audio.muted);
            },
          ),
        ),
      ],
    );
  }

  Widget _errorLine(String message) {
    // Un desalojo NO es un error: es lo que el sistema promete que pasa cuando
    // otro dispositivo reclama el audio. Se pinta distinto para que no se lea
    // como una falla de la app.
    final evicted = audio.state == PhoneAudioState.evicted;
    final color = evicted ? CceColors.accent : CceColors.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CceRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            evicted ? Icons.swap_horiz : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: CceText.caption.copyWith(color: CceColors.textSecondary),
            ),
          ),
          IconButton(
            onPressed: audio.clearError,
            icon: const Icon(Icons.close, size: 14),
            color: CceColors.textTertiary,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Cerrar',
          ),
        ],
      ),
    );
  }

  static String _outputLabel(PhoneAudioOutput output) {
    switch (output) {
      case PhoneAudioOutput.receiver:
        return 'Por el auricular del celular';
      case PhoneAudioOutput.speaker:
        return 'Por el altavoz del celular';
      case PhoneAudioOutput.headphones:
        return 'Por los auriculares';
      case PhoneAudioOutput.bluetooth:
        return 'Por el manos libres Bluetooth';
      case PhoneAudioOutput.other:
        return 'Por la salida del sistema';
    }
  }
}

/// Una barra de nivel con su etiqueta.
class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.icon,
    required this.label,
    required this.level,
    required this.color,
  });

  final Widget icon;
  final String label;
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Escala RAÍZ, igual que el dashboard: en lineal una voz normal casi no
    // mueve la barra y el medidor deja de servir para lo único que sirve.
    final width = math.sqrt(level.clamp(0, 1)).clamp(0.0, 1.0);
    return Semantics(
      label: '$label, nivel ${(width * 100).round()} por ciento',
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: CceColors.surfaceSunken),
                  FractionallySizedBox(
                    widthFactor: width,
                    child: Container(height: 6, color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: CceText.caption.copyWith(color: CceColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de dos estados, chato, para altavoz y mudo.
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    this.icon,
    this.materialIcon,
    required this.label,
    required this.on,
    required this.onTap,
    this.onColor = CceColors.accent,
  });

  final String? icon;
  final IconData? materialIcon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final color = on ? onColor : CceColors.textSecondary;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CceRadii.sm),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: on ? onColor.withValues(alpha: 0.16) : CceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(CceRadii.sm),
            border: Border.all(
              color: on ? onColor.withValues(alpha: 0.5) : CceColors.stroke,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (materialIcon != null)
                Icon(materialIcon, size: 16, color: color)
              else if (icon != null)
                CceIcon(icon!, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: CceText.caption.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
