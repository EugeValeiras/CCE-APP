import 'package:flutter/material.dart';

import '../models/event_record.dart';
import '../services/api_service.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../utils/time_format.dart';

/// Una fila del historial, ya traducida a lenguaje humano por la pantalla.
class EventHistoryEntry {
  /// Qué pasó: "Botón 2 · Mantenido", "Movimiento", "Abierta"…
  final String label;

  /// Detalle opcional (ej. la automatización que disparó).
  final String? detail;

  /// SVG de [CceIcons].
  final String glyph;

  /// Acento: tiñe el glyph y le da glow al chip cuando [glowing].
  final Color color;

  final bool glowing;
  final DateTime timestamp;

  const EventHistoryEntry({
    required this.label,
    required this.glyph,
    required this.color,
    required this.timestamp,
    this.detail,
    this.glowing = false,
  });
}

/// Sección HISTORIAL reutilizable (canon de [LockScreen]): header con refrescar
/// + well hundido con filas separadas por hairlines y chip convexo por evento.
///
/// La pantalla decide QUÉ mostrar vía [mapper] (devolver null saltea el
/// evento); esto lee del histórico persistido del backend por el bindingId del
/// provider — el backend indexa los eventos por ahí, no por el dev_* canónico.
class EventHistorySection extends StatefulWidget {
  final DevicesService service;

  /// Id con el que el backend indexa los eventos (bindingId del provider).
  final String historyId;

  /// Traduce la tanda de eventos crudos (canal interno) a filas. Recibe la
  /// LISTA completa para poder aparear eventos entre sí (p.ej. una pulsación
  /// con la automatización que disparó, que llega como un evento aparte).
  final List<EventHistoryEntry> Function(List<EventRecord>) builder;

  final String emptyLabel;
  final int limit;

  /// Se llama con el evento MÁS RECIENTE cuando termina de cargar (null si no
  /// hay). Existe para que la métrica "ÚLTIMA" de las pantallas de botones
  /// pueda mostrar algo cuando el proveedor no manda trigTime —Hue no lo
  /// manda— sin repetir el request que esta sección ya hace.
  final void Function(DateTime? lastAt)? onLoaded;

  const EventHistorySection({
    super.key,
    required this.service,
    required this.historyId,
    required this.builder,
    this.emptyLabel = 'Sin eventos registrados',
    this.limit = 40,
    this.onLoaded,
  });

  @override
  State<EventHistorySection> createState() => _EventHistorySectionState();
}

class _EventHistorySectionState extends State<EventHistorySection> {
  late final ApiService _api;
  List<EventHistoryEntry> _entries = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.service.config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await _api.getEvents(
        globalId: widget.historyId,
        limit: widget.limit,
      );
      if (!mounted) return;
      // Solo el canal interno: websocket duplica cada evento.
      final internal = page.items
          .where((e) => e.channel == 'internal')
          .toList();
      setState(() {
        _entries = widget.builder(internal);
        _loading = false;
      });
      widget.onLoaded?.call(internal.isEmpty ? null : internal.first.timestamp);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('HISTORIAL', style: CceText.section),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _load,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CceColors.neoBase,
                  boxShadow: CceShadows.neo(blur: 6, offset: 2),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CceColors.textSecondary,
                        ),
                      )
                    : SizedBox.square(
                        dimension: 16,
                        child: CceIcon(
                          CceIcons.refreshCw,
                          size: 16,
                          color: CceColors.textSecondary,
                          emboss: false,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                _loading ? 'Cargando eventos…' : widget.emptyLabel,
                style: const TextStyle(
                  color: CceColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: CceColors.neoBase,
              borderRadius: BorderRadius.circular(18),
              boxShadow: CceShadows.neoInset(blur: 6, offset: 2),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _entries.length; i++)
                  _row(_entries[i], last: i == _entries.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(EventHistoryEntry e, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: CceColors.neoDark.withValues(alpha: 0.55),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CceColors.neoBase,
              gradient: CceGradients.convex(CceColors.neoBase),
              boxShadow: [
                ...CceShadows.neo(blur: 8, offset: 3),
                if (e.glowing)
                  BoxShadow(
                    color: e.color.withValues(alpha: 0.40),
                    blurRadius: 8,
                  ),
              ],
            ),
            child: SizedBox.square(
              dimension: 18,
              child: CceIcon(e.glyph, size: 18, color: e.color, emboss: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: CceColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.detail ??
                      '${TimeFormat.dayLabel(e.timestamp)} · ${TimeFormat.hm(e.timestamp)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: e.detail != null
                        ? CceColors.accent
                        : CceColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            TimeFormat.relative(e.timestamp),
            style: const TextStyle(
              fontSize: 11.5,
              color: CceColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
