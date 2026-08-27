import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/automation.dart';
import '../../services/automations_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';

/// Botón "Probar"/"Ejecutar" — SOLO el widget; toda la lógica de ejecución
/// (probe del endpoint, simulate-button, replay con matriz de degradación)
/// vive en [AutomationsService.runNow].
///
/// 3 estados: idle → spinner (timeout 8 s) → check ok 1.2 s. Si la
/// ejecución degrada, el warning se muestra ANTES de ejecutar (pill ámbar
/// en modo editor, SnackBar en modo compacto).
class RunAutomationButton extends StatefulWidget {
  const RunAutomationButton({
    super.key,
    required this.automation,
    required this.service,
    this.compact = false,
    this.size = 44,
  });

  final Automation automation;
  final AutomationsService service;

  /// true = ▶ circular de [size] (cards); false = "Probar" del editor.
  final bool compact;

  /// Diámetro del ▶ compacto (44 en las filas; 32 en los tiles de la home).
  final double size;

  @override
  State<RunAutomationButton> createState() => _RunAutomationButtonState();
}

enum _RunState { idle, running, done, failed }

class _RunAutomationButtonState extends State<RunAutomationButton> {
  _RunState _state = _RunState.idle;
  String? _warning;
  Timer? _resetTimer;
  Timer? _warningTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _warningTimer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_state == _RunState.running) return;

    // Warning de degradación ANTES de ejecutar.
    final warning = widget.service.clientReplayWarning(widget.automation);
    if (warning != null) {
      if (widget.compact) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning)),
        );
      } else {
        _warningTimer?.cancel();
        setState(() => _warning = warning);
        _warningTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _warning = null);
        });
      }
    }

    setState(() => _state = _RunState.running);
    RunResult result;
    try {
      result = await widget.service
          .runNow(widget.automation)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      result = const RunResult(ok: false, warning: 'La prueba tardó demasiado');
    } catch (_) {
      result = const RunResult(ok: false, warning: 'Falló la prueba');
    }
    if (!mounted) return;

    setState(() => _state = result.ok ? _RunState.done : _RunState.failed);
    if (!result.ok && result.warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.warning!)),
      );
    }
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _state = _RunState.idle);
    });
  }

  Widget _icon(Color color) {
    // Glyph proporcional al botón: 18 en el ▶ de 44, 16 en el de 32.
    final double s = widget.compact && widget.size < 44 ? 16 : 18;
    switch (_state) {
      case _RunState.running:
        return SizedBox(
          width: s - 2,
          height: s - 2,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );
      case _RunState.done:
        return CceIcon(CceIcons.check, size: s, color: CceColors.ok);
      case _RunState.failed:
        return CceIcon(CceIcons.close, size: s, color: CceColors.danger);
      case _RunState.idle:
        return CceIcon(CceIcons.play, size: s, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Tooltip(
        message: 'Ejecutar ahora',
        child: InkWell(
          onTap: _run,
          borderRadius: BorderRadius.circular(CceRadii.pill),
          child: Container(
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CceColors.surfaceHigh,
              shape: BoxShape.circle,
              // Hairline: un control apagado tiene que verse (system.md).
              border: Border.all(color: CceColors.stroke),
            ),
            child: _icon(CceColors.textSecondary),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_warning != null) ...[
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: CceColors.warm.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(CceRadii.pill),
                border: Border.all(
                    color: CceColors.warm.withValues(alpha: 0.5)),
              ),
              child: Text(
                _warning!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CceColors.warm,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        OutlinedButton.icon(
          onPressed: _state == _RunState.running ? null : _run,
          icon: _icon(CceColors.textPrimary),
          label: const Text('Probar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: CceColors.textPrimary,
            side: const BorderSide(color: CceColors.stroke),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}
