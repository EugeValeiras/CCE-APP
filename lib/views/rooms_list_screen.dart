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
          // Fondo de la app (matte oscuro, #101014): MÁS oscuro que las cards
          // (neoBase) para que el relieve se vea y las cards "floten". Antes el
          // fondo compartía neoBase con las cards y el relieve se perdía.
          backgroundColor: CceColors.bg,
          appBar: AppBar(
            toolbarHeight: 64,
            // El appbar comparte el fondo de la app y NO proyecta sombra/línea
            // de Material al hacer scroll (elevation + scrolledUnderElevation 0;
            // surfaceTint transparente).
            backgroundColor: CceColors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            // Logo de CCE (edificio del splash) extruido neumórfico, en vez del
            // texto plano "CCE". FittedBox lo achica si la pantalla es angosta
            // (no recorta nunca contra los actions). Tinte titleInk (gris-claro
            // de "material"): iguala la tinta de todos los títulos embossed, en
            // vez del casi-blanco anterior que brillaba de más.
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: const CceLogo(height: 22),
            ),
            actions: [
              // Riel de acciones embutido en la goma: en vez de 3 glyphs sueltos
              // flotando, un único contenedor HUNDIDO (neoSunken + neoInset +
              // radius pill) que aloja los 3 IconButton en fila. Agrupa 3
              // elementos en 1 bloque (menos ruido) y se lee como control del
              // mismo material que el JBL/TV. Cada handler se conserva intacto.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ActionRail(
                  onOpenHistory: widget.onOpenHistory,
                  onOpenAgent: widget.onOpenAgent,
                  onOpenAlarm: widget.onOpenAlarm,
                  alarmArmed: service.alarmArmed,
                  hostContext: context,
                ),
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
                  // Colores de la placa neo (no la paleta vieja surfaceHigh, que
                  // mete un gris ajeno): spinner textSecondary sobre neoSunken.
                  color: CceColors.textSecondary,
                  backgroundColor: CceColors.neoSunken,
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    // El drag se inicia con long-press sobre el ítem (ver
                    // ReorderableDelayedDragStartListener); sin handle a la
                    // derecha.
                    buildDefaultDragHandles: false,
                    // Header NO arrastrable, jerarquizado por AIRE (gaps), no por
                    // cajas: clima (hero) → [gap 20] → label DESTACADOS → TV y
                    // JBL (gap 12 entre sí) → [gap 20] → label HABITACIONES →
                    // grilla arrastrable. Gaps mayores ENTRE grupos (20) que
                    // DENTRO de un grupo (12) crean la jerarquía sin bordes. Cada
                    // lead card en su RepaintBoundary para aislar el repintado de
                    // las sombras neumórficas. El TV va PRIMERO de los
                    // dispositivos dedicados (antes del JBL).
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // HERO único: resumen de clima de toda la casa.
                        RepaintBoundary(
                          child: TemperatureSummaryCard(
                              service: service, neo: true),
                        ),
                        // Grupo "destacados" (dispositivos dedicados): solo se
                        // muestra el encabezado si hay al menos un dispositivo.
                        if (widget.tv != null || widget.jbl != null) ...[
                          const SizedBox(height: 20),
                          _sectionLabel('Destacados'),
                          const SizedBox(height: 10),
                          if (widget.tv != null)
                            RepaintBoundary(
                              child:
                                  TvHomeCard(service: widget.tv!, neo: true),
                            ),
                          if (widget.tv != null && widget.jbl != null)
                            const SizedBox(height: 12),
                          if (widget.jbl != null)
                            RepaintBoundary(
                              child: SoundbarHomeCard(
                                  service: widget.jbl!, neo: true),
                            ),
                        ],
                        // Grupo "habitaciones": encabezado de la grilla
                        // arrastrable.
                        const SizedBox(height: 20),
                        _sectionLabel('Habitaciones'),
                        const SizedBox(height: 10),
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

  /// Encabezado de sección (CceText.section, UPPERCASE): separa grupos del
  /// header sin meter cajas. Padding-left chico para alinearlo ópticamente con
  /// el contenido de las cards (que tienen su propio padding interno).
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: CceText.section),
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
        // Slider de brillo inline (igual que la tablet): aparece SÓLO cuando la
        // sala está encendida (avgBrightness != null → card 104px). Apagada cae
        // a null ⇒ card 76px sin slider, idéntica a la compacta de antes.
        brightness: stats.avgBrightness,
        compact: false,
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
        onBrightnessCommitted: (v) => service.setRoomBrightness(room, v),
        neo: true,
      ),
    );
  }
}

/// Riel de acciones del appbar (Historial / Agente / Alarma) embutido en la
/// goma: un canal HUNDIDO (neoSunken + neoInset + radius pill) que aloja los
/// glyphs en fila. Agrupa los controles sueltos en un solo bloque y los lee
/// como riel embutido (mismo lenguaje que los controles del JBL/TV). Conserva
/// los handlers exactos; solo se montan los que existen.
class _ActionRail extends StatelessWidget {
  final void Function(BuildContext)? onOpenHistory;
  final void Function(BuildContext)? onOpenAgent;
  final void Function(BuildContext)? onOpenAlarm;
  final bool alarmArmed;

  /// Contexto del call-site original (el que usaban los IconButton sueltos):
  /// los handlers de navegación esperan el context de la pantalla, no el del
  /// riel. Se pasa explícito para preservar el comportamiento exacto.
  final BuildContext hostContext;
  const _ActionRail({
    required this.onOpenHistory,
    required this.onOpenAgent,
    required this.onOpenAlarm,
    required this.alarmArmed,
    required this.hostContext,
  });

  /// Glyph "goma" tenue (neoTextSub) dentro del riel; sin botón circular. El
  /// área táctil se mantiene cómoda con un padding fijo. [color] permite que la
  /// alarma armada conmute a danger.
  Widget _slot({
    required String svg,
    required String tooltip,
    required VoidCallback onTap,
    Color color = CceColors.neoTextSub,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: CceIcon(svg, size: 22, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[
      if (onOpenHistory != null)
        _slot(
          svg: CceIcons.history,
          tooltip: 'Historial',
          onTap: () => onOpenHistory!(hostContext),
        ),
      if (onOpenAgent != null)
        _slot(
          svg: CceIcons.agent,
          tooltip: 'Agente',
          onTap: () => onOpenAgent!(hostContext),
        ),
      if (onOpenAlarm != null)
        _slot(
          svg: CceIcons.alarmShield,
          tooltip: 'Alarma',
          // Rojo cuando la alarma está armada (estado en vivo del service).
          color: alarmArmed ? CceColors.danger : CceColors.neoTextSub,
          onTap: () => onOpenAlarm!(hostContext),
        ),
    ];
    if (slots.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: CceColors.neoSunken,
        borderRadius: BorderRadius.circular(CceRadii.pill),
        boxShadow: CceShadows.neoInset(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: slots),
    );
  }
}
