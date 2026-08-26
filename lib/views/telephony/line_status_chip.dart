import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../models/phone_call.dart';
import '../../theme/cce_tokens.dart';
import 'phone_surface.dart';

/// El estado de la línea en UNA línea: `● Línea activa · Personal · WCDMA` y
/// la señal a la derecha. Antes era una card de dos renglones que competía
/// con el número por la mitad de arriba (CCE#14); ahora es un chip fino bajo
/// el header, porque es contexto, no protagonista.
///
/// Registrado y OPERATIVO son cosas distintas: una línea sin habilitar se
/// registra igual y muestra operador y señal impecables sin poder cursar nada.
/// Por eso el estado de la línea va primero y con su propio color, separado
/// del operador y la red.
///
/// Los datos EN VIVO ([state], por socket) mandan sobre el seed de `/status`
/// ([status]): son la misma verdad, pero uno llega antes.
class LineStatusChip extends StatelessWidget {
  const LineStatusChip({super.key, required this.status, required this.state});

  final PhoneStatus status;
  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final bars = state.signalBars ?? status.signalBars;
    final lineActive = state.lineActive ?? status.lineActive;

    final (String lineText, Color lineColor) = switch (lineActive) {
      'active' => ('Línea activa', CceColors.ok),
      'inactive' => ('Línea inactiva', CceColors.danger),
      _ => ('Línea sin verificar', CceColors.textTertiary),
    };

    final operator = state.networkOperator ?? status.operator ?? 'Sin operador';
    final tail = [
      state.networkTech ?? status.tech ?? 'sin red',
      if (status.balance != null) 'Saldo ${status.balance}',
    ].join(' · ');

    // Lo que hay que ver venir. El tope del backend existe y corta: mejor
    // saberlo antes que descubrirlo con un rechazo.
    final (String? caution, Color cautionColor) = switch (status) {
      PhoneStatus(enabled: false) => (
          'La telefonía está deshabilitada en el servidor.',
          CceColors.danger,
        ),
      PhoneStatus(online: false) => (
          'El módem no responde. Se reconecta solo cuando vuelva.',
          CceColors.danger,
        ),
      PhoneStatus(rateLimitNear: true) => (
          '${status.rateLimitLabel}. Al llegar al tope el servidor no deja '
              'llamar por un rato.',
          CceColors.accent,
        ),
      _ => (null, CceColors.textSecondary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PhoneSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: lineColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // El estado de la línea y la red van SIEMPRE enteros; lo que
              // cede cuando no entra es el nombre del operador, que es lo
              // más largo y lo menos urgente ("AR PERSONAL Personal").
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '$lineText · ',
                      style: CceText.label.copyWith(
                        color: CceColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      // Se desvanece en vez de cortarse con puntos: el
                      // ellipsis deja un hueco de un glifo antes del
                      // separador y se lee como un renglón roto.
                      child: Text(
                        operator,
                        style: CceText.caption,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                    Text(' · $tail', style: CceText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SignalBars(bars),
            ],
          ),
        ),
        if (caution != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              caution,
              style: CceText.caption.copyWith(color: cautionColor),
            ),
          ),
      ],
    );
  }
}

/// Las cinco barritas de señal, a escala. Las mismas en el chip y en la card
/// de la home: la señal se lee igual en los dos lugares.
class SignalBars extends StatelessWidget {
  const SignalBars(this.bars, {super.key, this.height = 12});

  /// 0–5.
  final int bars;

  /// Alto de la barra más alta.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Señal $bars de 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= 5; i++) ...[
            Container(
              width: 3,
              height: height * (0.4 + 0.15 * i),
              decoration: BoxDecoration(
                color: i <= bars ? CceColors.accent : CceColors.strokeStrong,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            if (i < 5) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}
