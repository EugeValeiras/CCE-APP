import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/featured_item.dart';
import '../models/room_ref.dart';
import '../services/automations_service.dart';
import '../services/devices_service.dart';
import '../services/jbl_service.dart';
import '../services/tv_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../theme/components/cce_logo.dart';
import '../theme/components/room_card.dart';
import '../utils/room_icon.dart';
import '../widgets/pulse_on_update.dart';
import '../widgets/temperature_summary_card.dart';
import '../widgets/temperature_sensor_picker_sheet.dart';
import '../widgets/featured_home_cards.dart';
import '../widgets/thermostat_home_card.dart';
import '../widgets/vacuum_home_card.dart';
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
  static const String _tempSensorKey = 'home.tempSensorId';
  static const String _featuredKey = 'home.featured';

  /// Lista EDITABLE de Destacados (orden = orden de render). null = el usuario
  /// nunca editó → default dinámico (TV → JBL → termostato → robot), idéntico
  /// al comportamiento histórico.
  List<FeaturedItem>? _featured;

  /// Automatizaciones para las cards destacadas y el editor. Se crea acá (el
  /// shell no lo provee) reusando config+devices de DevicesService.
  late final AutomationsService _automations;

  /// Fuente de verdad del orden interactivo: lista de RoomRef.id. Estable
  /// (no se regenera con cada notify del service). El build deriva la lista
  /// de RoomRef desde acá vía [_applyOrder] sobre service.rooms.
  List<String> _savedOrder = const [];

  /// Id del termómetro elegido para el hero de clima (null ⇒ primero). Persiste
  /// en SharedPreferences; el TemperatureSummaryCard cae al primero si el id
  /// guardado ya no existe.
  String? _tempSensorId;

  @override
  void initState() {
    super.initState();
    _automations =
        AutomationsService(config: widget.service.config, devices: widget.service);
    _loadOrder();
    _loadTempSensor();
    _loadFeatured();
  }

  @override
  void dispose() {
    _automations.dispose();
    super.dispose();
  }

  Future<void> _loadFeatured() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_featuredKey);
      // `_featured == null`: si el usuario YA editó antes de que resuelva este
      // await (primer acceso a prefs puede ser lento), no pisar su edición.
      if (raw != null && mounted && _featured == null) {
        setState(() => _featured = _dedupe(FeaturedItem.decodeList(raw)));
      }
    } catch (_) {}
  }

  /// Dedupe preservando orden: entradas repetidas en prefs (o agregadas dos
  /// veces) romperían las keys del ReorderableListView del editor.
  static List<FeaturedItem> _dedupe(List<FeaturedItem> items) {
    final seen = <FeaturedItem>{};
    return [
      for (final i in items)
        if (seen.add(i)) i,
    ];
  }

  Future<void> _saveFeatured(List<FeaturedItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_featuredKey, FeaturedItem.encodeList(items));
    } catch (_) {}
  }

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_orderKey);
      if (saved != null && mounted) setState(() => _savedOrder = saved);
    } catch (_) {}
  }

  Future<void> _loadTempSensor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_tempSensorKey);
      if (saved != null && mounted) setState(() => _tempSensorId = saved);
    } catch (_) {}
  }

  Future<void> _saveTempSensor(String id) async {
    if (mounted) setState(() => _tempSensorId = id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tempSensorKey, id);
    } catch (_) {}
  }

  Future<void> _openTempSensorPicker() async {
    final picked = await TemperatureSensorPickerSheet.show(
      context,
      service: widget.service,
      selectedId: _tempSensorId,
    );
    if (picked != null) _saveTempSensor(picked);
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

  // ── Destacados editable ───────────────────────────────────────────────────

  /// Default histórico cuando el usuario nunca editó: TV → JBL → termostato →
  /// robot (los que existan).
  List<FeaturedItem> _defaultFeatured(Device? thermostat, Device? vacuum) => [
        if (widget.tv != null) const FeaturedItem(FeaturedKind.tv),
        if (widget.jbl != null) const FeaturedItem(FeaturedKind.jbl),
        if (thermostat != null)
          FeaturedItem(FeaturedKind.thermostat, thermostat.id),
        if (vacuum != null) FeaturedItem(FeaturedKind.vacuum, vacuum.id),
      ];

  List<FeaturedItem> _effectiveFeatured(Device? thermostat, Device? vacuum) =>
      _featured ?? _defaultFeatured(thermostat, vacuum);

  /// Sección completa. Entrada a la edición: LONG-PRESS sobre cualquier card
  /// (mismo gesto que el reorder de habitaciones). Sin cards (lista vacía o
  /// todo stale) se muestra un placeholder con el mismo formato de card que
  /// invita a editar — así la sección nunca es irrecuperable.
  List<Widget> _featuredSection(Device? thermostat, Device? vacuum) {
    void openEditor() {
      HapticFeedback.mediumImpact();
      _openFeaturedEditor(thermostat, vacuum);
    }

    final items = _effectiveFeatured(thermostat, vacuum);
    final cards = <Widget>[];
    for (final item in items) {
      final card = _featuredCard(item);
      if (card == null) continue; // ítem stale (device/escena borrados)
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 12));
      // Long-press abre el editor; los taps siguen siendo de la card (su
      // CceNeoPress no registra long-press cuando no lo usa).
      cards.add(GestureDetector(
        onLongPress: openEditor,
        child: RepaintBoundary(child: card),
      ));
    }
    return [
      const SizedBox(height: 20),
      _sectionLabel('Destacados'),
      const SizedBox(height: 10),
      if (cards.isEmpty)
        CceCard(
          onTap: openEditor,
          onLongPress: openEditor,
          radius: CceRadii.hueCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: CceColors.neoBase,
          neo: true,
          child: Row(
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.edit_outlined,
                    size: 26, color: CceColors.textTertiary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sin destacados',
                        style: CceText.title.copyWith(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      'Tocá para agregar dispositivos, luces, escenas y automatizaciones',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CceText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      else
        ...cards,
    ];
  }

  /// Card para un ítem destacado; null si el ítem ya no resuelve (se saltea
  /// sin romper — el editor lo muestra igual para poder quitarlo). [trailing]
  /// reemplaza el control derecho (modo edición: + / −).
  Widget? _featuredCard(FeaturedItem item, {Widget? trailing}) {
    final service = widget.service;
    switch (item.kind) {
      case FeaturedKind.tv:
        final tv = widget.tv;
        return tv == null ? null : TvHomeCard(service: tv, neo: true, trailing: trailing);
      case FeaturedKind.jbl:
        final jbl = widget.jbl;
        return jbl == null
            ? null
            : SoundbarHomeCard(service: jbl, neo: true, trailing: trailing);
      case FeaturedKind.thermostat:
        final d = item.id != null ? service.byId(item.id!) : null;
        return (d == null || !d.isThermostat)
            ? null
            : ThermostatHomeCard(
                service: service, device: d, neo: true, trailing: trailing);
      case FeaturedKind.vacuum:
        final d = item.id != null ? service.byId(item.id!) : null;
        return (d == null || !d.isVacuum)
            ? null
            : VacuumHomeCard(
                service: service, device: d, neo: true, trailing: trailing);
      case FeaturedKind.light:
        final d = item.id != null ? service.byId(item.id!) : null;
        return (d == null || d.hidden)
            ? null
            : LightHomeCard(service: service, device: d, trailing: trailing);
      case FeaturedKind.button:
        final d = item.id != null ? service.byId(item.id!) : null;
        return (d == null || d.hidden || !d.isSwitch)
            ? null
            : ButtonHomeCard(service: service, device: d, trailing: trailing);
      case FeaturedKind.scene:
        final s = service.scenes.firstWhereOrNull((x) => x.id == item.id);
        return s == null
            ? null
            : SceneHomeCard(service: service, scene: s, trailing: trailing);
      case FeaturedKind.hueScene:
        final s = service.hueScenes.firstWhereOrNull((x) => x.id == item.id);
        return s == null
            ? null
            : SceneHomeCard(service: service, hueScene: s, trailing: trailing);
      case FeaturedKind.automation:
        final a =
            _automations.automations.firstWhereOrNull((x) => x.id == item.id);
        return a == null
            ? null
            : AutomationHomeCard(
                service: _automations,
                devices: service,
                automation: a,
                trailing: trailing);
    }
  }

  /// Nombre legible de un ítem para el editor.
  String _featuredName(FeaturedItem item) {
    final service = widget.service;
    switch (item.kind) {
      case FeaturedKind.tv:
        return 'Samsung TV';
      case FeaturedKind.jbl:
        return 'JBL Soundbar';
      case FeaturedKind.thermostat:
      case FeaturedKind.vacuum:
      case FeaturedKind.light:
      case FeaturedKind.button:
        final d = item.id != null ? service.byId(item.id!) : null;
        return d != null ? service.displayName(d) : '(ya no existe)';
      case FeaturedKind.scene:
        return service.scenes
                .firstWhereOrNull((x) => x.id == item.id)
                ?.name ??
            '(escena borrada)';
      case FeaturedKind.hueScene:
        return service.hueScenes
                .firstWhereOrNull((x) => x.id == item.id)
                ?.name ??
            '(escena borrada)';
      case FeaturedKind.automation:
        return _automations.automations
                .firstWhereOrNull((x) => x.id == item.id)
                ?.name ??
            '(automatización borrada)';
    }
  }

  /// Etiqueta corta del tipo (chip del editor).
  String _kindLabel(FeaturedKind k) => switch (k) {
        FeaturedKind.tv => 'TV',
        FeaturedKind.jbl => 'JBL',
        FeaturedKind.thermostat => 'Termostato',
        FeaturedKind.vacuum => 'Robot',
        FeaturedKind.light => 'Luz',
        FeaturedKind.button => 'Botón',
        FeaturedKind.scene => 'Escena',
        FeaturedKind.hueScene => 'Escena Hue',
        FeaturedKind.automation => 'Automatización',
      };

  /// Subtítulo del editor: tipo + habitación cuando aplica ('Luz · Living',
  /// 'Escena Hue · Dormitorio') — desambigua homónimos en listas largas.
  String _featuredContext(FeaturedItem item) {
    final kind = _kindLabel(item.kind);
    switch (item.kind) {
      case FeaturedKind.light:
      case FeaturedKind.button:
        final room = widget.service.rooms
            .firstWhereOrNull((r) => r.deviceIds.contains(item.id))
            ?.name;
        return room != null ? '$kind · $room' : kind;
      case FeaturedKind.hueScene:
        final room = widget.service.hueScenes
            .firstWhereOrNull((x) => x.id == item.id)
            ?.roomName;
        return room != null ? '$kind · $room' : kind;
      default:
        return kind;
    }
  }

  void _openFeaturedEditor(Device? thermostat, Device? vacuum) {
    final service = widget.service;
    // Copia local editable; el default se materializa al abrir el editor.
    final sel = List<FeaturedItem>.of(_effectiveFeatured(thermostat, vacuum));

    void persist(StateSetter setSheet) {
      setSheet(() {});
      setState(() => _featured = List.of(sel));
      _saveFeatured(sel);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: CceColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      // AnimatedBuilder: los grupos "Agregar" dependen de los services (p.ej.
      // automatizaciones que terminan de cargar con el sheet abierto).
      builder: (sheetCtx) => AnimatedBuilder(
        animation: Listenable.merge([service, _automations]),
        builder: (context, _) => StatefulBuilder(
          builder: (context, setSheet) {
          // Candidatos = todo lo agregable que NO está ya en la lista.
          final selected = sel.toSet();
          final devices = <FeaturedItem>[
            if (widget.tv != null) const FeaturedItem(FeaturedKind.tv),
            if (widget.jbl != null) const FeaturedItem(FeaturedKind.jbl),
            for (final d in service.thermostats)
              FeaturedItem(FeaturedKind.thermostat, d.id),
            for (final d in service.vacuums)
              FeaturedItem(FeaturedKind.vacuum, d.id),
          ].where((i) => !selected.contains(i)).toList();
          final lights = [
            for (final d in service.lights) FeaturedItem(FeaturedKind.light, d.id),
          ].where((i) => !selected.contains(i)).toList();
          // Botones/switches (dial 4 teclas, botón simple, relés): viven en
          // sensors con isSwitch — no son luces ni sensores pasivos.
          final buttons = [
            for (final d in service.sensors.where((d) => d.isSwitch))
              FeaturedItem(FeaturedKind.button, d.id),
          ].where((i) => !selected.contains(i)).toList();
          final scenes = <FeaturedItem>[
            for (final s in service.scenes) FeaturedItem(FeaturedKind.scene, s.id),
            for (final s in service.hueScenes)
              FeaturedItem(FeaturedKind.hueScene, s.id),
          ].where((i) => !selected.contains(i)).toList();
          final autos = [
            for (final a in _automations.automations)
              FeaturedItem(FeaturedKind.automation, a.id),
          ].where((i) => !selected.contains(i)).toList();

          // Fallback para ítems que ya no resuelven (escena/device borrados):
          // fila simple con el nombre, para poder quitarlos igual.
          Widget stalePlaceholder(FeaturedItem item) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: CceColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(CceRadii.hueCard),
                ),
                child: Text(
                  '${_featuredName(item)} · ${_featuredContext(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CceText.caption,
                ),
              );

          // Botón − / + que ocupa el LUGAR del control de la card: "de goma"
          // neumórfica, el MISMO material que las teclas de la app (círculo
          // neoBase raised, glyph en el color estándar de ícono — réplica
          // visual de CceNeoIconButton). Decorativo: el tap real lo maneja el
          // overlay (quitar) o la card completa (agregar).
          Widget editControl(IconData icon) => Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CceColors.neoBase,
                  boxShadow: CceShadows.neo(blur: 8, offset: 3),
                ),
                child: Icon(icon, size: 20, color: CceColors.neoText),
              );

          // CARD REAL de la home, inerte (IgnorePointer: en el editor no se
          // togglea ni navega), con el − en el lugar del control. Una franja
          // derecha invisible captura el tap de quitar.
          Widget selectedTile(FeaturedItem item, int index) {
            final card = _featuredCard(item,
                trailing: editControl(Icons.remove));
            return Padding(
              key: ValueKey(item.encode()),
              padding: const EdgeInsets.only(bottom: 12),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child:
                          IgnorePointer(child: card ?? stalePlaceholder(item)),
                    ),
                    // Zona de tap del − (franja derecha, alto completo).
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 64,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          sel.remove(item);
                          persist(setSheet);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget addGroup(String title, List<FeaturedItem> items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Text(title.toUpperCase(), style: CceText.section),
                const SizedBox(height: 8),
                for (final item in items)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (sel.contains(item)) return; // anti doble-tap
                      HapticFeedback.selectionClick();
                      sel.add(item);
                      persist(setSheet);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: _featuredCard(item,
                                  trailing: editControl(Icons.add)) ??
                              stalePlaceholder(item),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Editar Destacados', style: CceText.title),
                    const SizedBox(height: 4),
                    Text(
                      'Mantené apretada una card para reordenarla, tocá la ✕ '
                      'para quitarla y tocá una de abajo para agregarla.',
                      style: CceText.caption,
                    ),
                    const SizedBox(height: 14),
                    if (sel.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Sin destacados — agregá desde abajo.',
                            style: CceText.caption),
                      )
                    else
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        onReorderStart: (_) => HapticFeedback.mediumImpact(),
                        onReorder: (oldI, newI) {
                          if (newI > oldI) newI -= 1;
                          sel.insert(newI, sel.removeAt(oldI));
                          persist(setSheet);
                        },
                        children: [
                          for (var i = 0; i < sel.length; i++)
                            selectedTile(sel[i], i),
                        ],
                      ),
                    addGroup('Dispositivos', devices),
                    addGroup('Luces', lights),
                    addGroup('Botones', buttons),
                    addGroup('Escenas', scenes),
                    addGroup('Automatizaciones', autos),
                  ],
                ),
              ),
            ),
          );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return AnimatedBuilder(
      // merge: las cards/editor de Destacados también dependen de
      // AutomationsService (sin esto, una automatización destacada no aparece
      // hasta que un evento ajeno de DevicesService fuerce rebuild).
      animation: Listenable.merge([service, _automations]),
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
        // Termostato destacado: a diferencia del TV/JBL (services dedicados) vive
        // DENTRO de DevicesService. Tomamos el primero si existe; la card escucha
        // al service y reresuelve por id.
        final thermostat =
            service.thermostats.isNotEmpty ? service.thermostats.first : null;
        // Robot aspiradora destacado: mismo criterio que el termostato (vive en
        // DevicesService, la card reresuelve por id).
        final vacuum =
            service.vacuums.isNotEmpty ? service.vacuums.first : null;
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
                        // HERO único: resumen de clima de toda la casa. Tappable
                        // → abre el selector de termómetros (si hay más de uno).
                        RepaintBoundary(
                          child: TemperatureSummaryCard(
                            service: service,
                            neo: true,
                            selectedSensorId: _tempSensorId,
                            onTap: _openTempSensorPicker,
                          ),
                        ),
                        // Grupo "destacados" EDITABLE: lista persistida de
                        // ítems (devices dedicados, luces, escenas y
                        // automatizaciones). Sin edición previa reproduce el
                        // default histórico TV → JBL → Termostato → Robot.
                        ..._featuredSection(thermostat, vacuum),
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
        iconBuilder: roomGlyphBuilder(room, service),
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
              tv: widget.tv,
              jbl: widget.jbl,
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
