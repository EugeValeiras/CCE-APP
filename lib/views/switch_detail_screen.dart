import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../utils/icon_resolver.dart';

/// Pantalla de un device tipo switch: ícono, nombre, estado y un switch GRANDE
/// para prender/apagar tocándolo.
class SwitchDetailScreen extends StatelessWidget {
  final Device device;
  final DevicesService service;
  const SwitchDetailScreen({
    super.key,
    required this.device,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(service.displayName(device), style: CceText.title),
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final d = service.byId(device.id) ?? device;
          final on = d.state.on;
          final reachable = d.state.reachable;
          final accent = on ? CceColors.warm : CceColors.textTertiary;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícono del device.
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? CceColors.warm.withValues(alpha: 0.18)
                        : CceColors.surfaceHigh,
                  ),
                  alignment: Alignment.center,
                  child: IconResolver.widget(
                    d,
                    configuredIcon: service.iconFor(d.id),
                    customIcons: service.customIcons,
                    displayName: service.displayName(d),
                    size: 48,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  !reachable
                      ? 'Sin conexión'
                      : (on ? 'Encendido' : 'Apagado'),
                  style: CceText.display.copyWith(
                    fontSize: 26,
                    color: !reachable ? CceColors.textTertiary : accent,
                  ),
                ),
                const SizedBox(height: 40),
                _BigSwitch(
                  value: on,
                  enabled: reachable,
                  onChanged: (_) {
                    HapticFeedback.selectionClick();
                    service.toggleLight(d);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  d.type,
                  style: CceText.caption.copyWith(color: CceColors.textTertiary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Switch grande: pista pill + thumb circular, tocable en toda su superficie.
class _BigSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _BigSwitch({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const w = 240.0, h = 120.0, thumb = 100.0;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: w,
          height: h,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: value ? CceGradients.huePastel([CceColors.warm]) : null,
            color: value ? null : CceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: CceColors.stroke),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: thumb,
              height: thumb,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.power_settings_new,
                size: 40,
                color: value ? CceColors.warmDeep : CceColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
