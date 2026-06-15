import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_logo.dart';
import '../theme/components/room_card.dart';
import '../utils/icon_resolver.dart';
import '../widgets/pulse_on_update.dart';
import '../widgets/temperature_summary_card.dart';
import 'room_detail_screen.dart';
import 'soundbar/soundbar_home_card.dart';
import 'splash_view.dart';
import 'tv/tv_home_card.dart';

/// Lista de habitaciones estilo Hue (phone). Las habitaciones y sus stats
/// salen SIEMPRE de DevicesService (rooms / statsFor) — acá no se deriva nada.
/// [jbl] != null agrega la card del JBL Soundbar (accionable desde la home).
/// [tv] != null agrega la card del Samsung TV, que va PRIMERO en la lista de
/// dispositivos dedicados (antes del soundbar).
///
/// Reorder: las RoomCards se reordenan por long-press (haptic + animación de
/// elevación) y el orden se persiste en SharedPreferences ('home.roomOrder',
/// List<String> de RoomRef.id). Las lead cards (clima + JBL) van en el header
/// no-arrastrable. PHONE-ONLY: el sidebar del tablet no usa este orden.
class RoomsListScreen extends StatefulWidget {
  final DevicesService service;
  final JblService? jbl;
  final TvService? tv;
  final void Function(BuildContext)? onOpenHistory;
  final void Function(BuildContext)? onOpenAgent;
  final void Function(BuildContext)? onOpenAlarm;
  const RoomsListScreen({
    super.key,
    required this.service,
    this.jbl,
    this.tv,
    this.onOpenHistory,
    this.onOpenAgent,
    this.onOpenAlarm,
  });

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  static const String _orderKey = 'home.roomOrder';

  /// Fuente de verdad del orden interactivo: lista de RoomRef.id. Estable
  /// (no se regenera con cada notify del service). El build deriva la lista
  /// de RoomRef desde acá vía [_applyOrder] sobre service.rooms.
  List<String> _savedOrder = const [];

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_orderKey);
      if (saved != null && mounted) setState(() => _savedOrder = saved);
    } catch (_) {}
  }

  Future<void> _saveOrder(List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, ids);
    } catch (_) {}
  }

  /// Merge parcial (calcado de room_detail): rooms conocidas siguen el orden
  /// guardado; rooms nuevas (no en [order]) caen al final preservando el orden
  /// de service.rooms entre sí; ids borrados se ignoran (residuo inocuo).
  List<RoomRef> _applyOrder(List<RoomRef> rooms, List<String> order) {
    if (order.isEmpty) return rooms; // sin orden guardado → orden de config.
    final idx = {for (var i = 0; i < order.length; i++) order[i]: i};
    final out = List<RoomRef>.of(rooms);
    out.sort((a, b) {
      final ia = idx[a.id], ib = idx[b.id];
      if (ia != null && ib != null) return ia.compareTo(ib); // ambos conocidos.
      if (ia != null) return -1; // conocido antes que nuevo.
      if (ib != null) return 1;
      return 0; // dos nuevos → mantienen orden de service.rooms.
    });
    return out;
  }

  /// Ícono de la habitación: el configurado (iconName) resuelto vía
  /// IconResolver con un device representativo, o el genérico de sala.
  Widget _roomIcon(RoomRef room) {
    final rep =
        room.deviceIds.map(widget.service.byId).whereType<Device>().firstOrNull;
    if (room.iconName != null && room.iconName!.isNotEmpty && rep != null) {
      return Icon(
        IconResolver.resolve(rep,
            configuredIcon: room.iconName, displayName: room.name),
      );
    }
    return const CceIcon(CceIcons.room);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.loading && service.all.isEmpty) {
          // Mientras no haya datos seguimos mostrando "Preparando tu hogar"
          // (mismo visual que el splash) en vez de un spinner genérico.
          return const SplashLoadingView();
        }

        // Orden derivado como variable LOCAL del build (sin mutar estado en
        // build): estable porque _savedOrder lo es; no hay carrera de
        // identidades aunque service.rooms regenere RoomRef en cada notify.
        final ordered = _applyOrder(service.rooms, _savedOrder);
        return Scaffold(
          // Fondo neumórfico (home teléfono): card y fondo comparten neoBase.
          backgroundColor: CceColors.neoBase,
          appBar: AppBar(
            toolbarHeight: 64,
            // Logo de CCE (edificio del splash) extruido neumórfico, en vez del
            // texto plano "CCE". FittedBox lo achica si la pantalla es angosta
            // (no recorta nunca contra los actions).
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CceLogo(height: 18, color: Color(0xFFECEEF2)),
            ),
            actions: [
              // Íconos "goma" neumórficos (mismo relieve que el Historial): el
              // glyph sobresale del fondo, sin botón circular.
              if (widget.onOpenHistory != null)
                IconButton(
                  tooltip: 'Historial',
                  // CceIcon ya embossa solo (size 22 >= 18) -> sin wrapper.
                  icon: const CceIcon(
                    CceIcons.history,
                    size: 22,
                    color: CceColors.textSecondary,
                  ),
                  onPressed: () => widget.onOpenHistory!(context),
                ),
              if (widget.onOpenAgent != null)
                IconButton(
                  tooltip: 'Agente',
                  icon: const CceIcon(
                    CceIcons.agent,
                    size: 22,
                    color: CceColors.textSecondary,
                  ),
                  onPressed: () => widget.onOpenAgent!(context),
                ),
              if (widget.onOpenAlarm != null)
                IconButton(
                  tooltip: 'Alarma',
                  // Rojo cuando la alarma está armada (estado en vivo del service).
                  icon: CceIcon(
                    CceIcons.alarmShield,
                    size: 22,
                    color: service.alarmArmed
                        ? CceColors.danger
                        : CceColors.textSecondary,
                  ),
                  onPressed: () => widget.onOpenAlarm!(context),
                ),
            ],
          ),
          body: ordered.isEmpty
              ? Center(
                  child: Text(
                    service.error ?? 'No hay habitaciones configuradas',
                    style: CceText.caption,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: service.refresh,
                  color: CceColors.textPrimary,
                  backgroundColor: CceColors.surfaceHigh,
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    // El drag se inicia con long-press sobre el ítem (ver
                    // ReorderableDelayedDragStartListener); sin handle a la
                    // derecha.
                    buildDefaultDragHandles: false,
                    // Lead cards (clima + TV + JBL) fijas en el header NO
                    // arrastrable. Cada una en su RepaintBoundary para preservar
                    // el aislamiento de repintado de las sombras neumórficas. El
                    // TV va PRIMERO de los dispositivos dedicados (antes del JBL).
                    header: Column(
                      children: [
                        RepaintBoundary(
                          child: TemperatureSummaryCard(
                              service: service, neo: true),
                        ),
                        if (widget.tv != null) ...[
                          const SizedBox(height: 12),
                          RepaintBoundary(
                            child: TvHomeCard(service: widget.tv!, neo: true),
                          ),
                        ],
                        if (widget.jbl != null) ...[
                          const SizedBox(height: 12),
                          RepaintBoundary(
                            child: SoundbarHomeCard(
                                service: widget.jbl!, neo: true),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                    onReorderStart: (_) => HapticFeedback.mediumImpact(),
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final t = Curves.easeInOut.transform(animation.value);
                          final scale = 1.0 + 0.04 * t; // se agranda al 104%.
                          final elevation = 14.0 * t; // sombra de elevación.
                          return Transform.scale(
                            scale: scale,
                            child: Material(
                              color: Colors.transparent,
                              elevation: elevation,
                              borderRadius:
                                  BorderRadius.circular(CceRadii.hueCard),
                              shadowColor: Colors.black.withValues(alpha: 0.35),
                              child: child,
                            ),
                          );
                        },
                      );
                    },
                    onReorder: (oldI, newI) {
                      if (newI > oldI) newI -= 1;
                      // Muta la fuente de verdad (ids) y persiste: el build que
                      // sigue deriva el mismo orden mostrado (idempotente, sin
                      // rollback). Purga oportunista de ids borrados.
                      setState(() {
                        final ids = ordered.map((r) => r.id).toList();
                        final moved = ids.removeAt(oldI);
                        ids.insert(newI, moved);
                        _savedOrder = ids;
                      });
                      HapticFeedback.selectionClick(); // "soltar".
                      _saveOrder(_savedOrder);
                    },
                    itemCount: ordered.length,
                    itemBuilder: (context, i) {
                      final room = ordered[i];
                      // Key estable por id en el widget raíz del ítem (requisito
                      // de ReorderableListView). El padding inferior va DENTRO
                      // del widget keyed para que viaje con el drag (sin gap
                      // fantasma en el proxy).
                      return Padding(
                        key: ValueKey('room-${room.id}'),
                        padding: EdgeInsets.only(
                            bottom: i < ordered.length - 1 ? 12 : 0),
                        child: ReorderableDelayedDragStartListener(
                          index: i,
                          // Long-press (~500ms) levanta el ítem. El tap corto
                          // (abrir detalle) gana la arena antes del delay; el
                          // switch togglea con tap corto.
                          child: RepaintBoundary(
                            child: _buildRoomCard(context, room),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _buildRoomCard(BuildContext context, RoomRef room) {
    final service = widget.service;
    final stats = service.statsFor(room);
    return PulseOnUpdate(
      triggerAt: stats.latestEventAt,
      color: stats.anyOn && stats.tint != null ? stats.tint! : CceColors.info,
      borderRadius: CceRadii.card,
      child: RoomCard(
        title: room.name,
        icon: _roomIcon(room),
        lightsOn: stats.lightsOn,
        lightsTotal: stats.lightsTotal,
        anyOn: stats.anyOn,
        tint: stats.tint,
        tintColors: stats.tintColors,
        // compact nunca muestra slider; el brillo por sala vive en el detalle.
        brightness: null,
        compact: true,
        motion: stats.anyMotion,
        contactOpen: stats.anyContactOpen,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RoomDetailScreen(
              title: room.name,
              deviceIds: room.deviceIds,
              service: service,
              room: room,
            ),
          ));
        },
        onToggle: (v) => service.setRoomOn(room, v),
        neo: true,
      ),
    );
  }
}
