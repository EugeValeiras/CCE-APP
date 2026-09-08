import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/device.dart';
import '../../services/devices_service.dart';
import '../../services/tv_service.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_card.dart';
import '../../theme/components/cce_switch.dart';
import '../../theme/components/featured_tile.dart';
import '../../theme/components/status_dot.dart';
import 'tv_screen.dart';

/// Card de UN Samsung para la home (lo "expone como dispositivo"): muestra
/// estado + power rápido y abre SU control al tocarla. Clon directo de
/// [SoundbarHomeCard] adaptado al TV (ícono de TV, acento azul "vivo").
///
/// Desde CCE#130 la home tiene una card POR APARATO, así que la card sabe cuál
/// es el suyo ([deviceId]) y no muestra el del estado global: con dos Samsung,
/// dos cards leyendo `service.isOn` decían siempre lo mismo. Su estado y su
/// nombre salen del inventario ([devices]), igual que el tile de la habitación;
/// el TvService sólo conoce el del aparato ELEGIDO.
class TvHomeCard extends StatefulWidget {
  final TvService service;

  /// Aparato que representa ESTA card (`dev_tv-ce588d39`). En null la card es
  /// la histórica del aparato elegido (backend sin GET /tv/tvs, o un destacado
  /// viejo que todavía no nombra aparato).
  final String? deviceId;

  /// De dónde sale el estado cuando hay [deviceId]: TvService sólo conoce el
  /// del aparato elegido, el de los demás vive en /devices/merged.
  final DevicesService? devices;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ render
  /// idéntico al plano.
  final bool neo;

  /// Si se provee, al tocar la card se llama esto EN VEZ de pushear la pantalla
  /// (en tablet el control se muestra inline en el panel derecho, no full-screen
  /// — la tablet no tiene swipe-back para volver).
  final VoidCallback? onOpen;

  /// Override del control derecho (modo edición del editor de Destacados):
  /// reemplaza el switch/acción por el widget dado (p.ej. un + o un −).
  final Widget? trailing;

  /// true ⇒ se renderiza como [FeaturedTile] (grilla 2 × 2 de la home);
  /// false ⇒ fila a todo el ancho (tablet, editor de Destacados).
  final bool tile;

  /// Se REENVÍA a la pantalla pusheada para su header de clima (esta card
  /// solo escucha a su TvService). null ⇒ la pantalla sin header.
  const TvHomeCard({
    super.key,
    required this.service,
    this.deviceId,
    this.devices,
    this.neo = false,
    this.onOpen,
    this.trailing,
    this.tile = false,
  });

  @override
  State<TvHomeCard> createState() => _TvHomeCardState();
}

class _TvHomeCardState extends State<TvHomeCard> {
  // Acento del sistema, no el azul de la marca. En la home lo que se comunica
  // es "encendido", y eso tiene que verse igual en todos los dispositivos: un
  // color por marca convertía la lista en un semáforo donde nada destaca.
  // La identidad de Samsung vive en el detalle del TV.
  static const Color _tvAccent = CceColors.accent;

  /// El device del inventario que representa esta card, si lo tiene y está.
  Device? get _device {
    final id = widget.deviceId;
    return id == null ? null : widget.devices?.byId(id);
  }

  /// A quién escucha la card, armado UNA vez: `Listenable.merge` no define
  /// `==`, así que construirlo dentro del build hacía que el AnimatedBuilder
  /// desenganchara y reenganchara listeners en los dos servicios en cada
  /// rebuild.
  late final Listenable _escucha = widget.deviceId == null ||
          widget.devices == null
      ? widget.service
      : Listenable.merge([widget.service, widget.devices!]);

  @override
  void initState() {
    super.initState();
    // Refresco de cortesía al aparecer (el shell maneja el polling continuo).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // La LISTA de Samsung siempre: de ella salen el nombre del aparato de
      // esta card y el `?tv=` de su switch.
      widget.service.loadTvs();
      // El estado del servicio es el del aparato ELEGIDO: sólo lo necesita la
      // card que NO tiene aparato propio. Condicionarlo a que el device no esté
      // en el inventario lo disparaba en cada arranque en frío —cuando el
      // inventario predeciblemente no llegó— y por cada card: dos lecturas del
      // aparato elegido que ninguna card iba a mirar.
      if (widget.deviceId == null) widget.service.refresh();
    });
  }

  void _open() {
    HapticFeedback.selectionClick();
    // El aparato se elige ACÁ, antes de abrir: `selectDevice` es síncrono en lo
    // que decide qué se ve, así que el control se construye ya mostrando el
    // Samsung de esta card y no el que quedó elegido desde otra pantalla.
    final deviceId = widget.deviceId;
    if (deviceId != null) widget.service.selectDevice(deviceId);
    if (widget.onOpen != null) {
      widget.onOpen!();
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TvScreen(service: widget.service, deviceId: deviceId),
      ));
    }
  }

  /// Power del aparato de ESTA card. Con un aparato propio va por
  /// `/tv/power?tv=…` (no puede llevarse el control de la otra card) y el
  /// optimismo se aplica sobre el inventario, que es de donde la card lee.
  Future<void> _setPower(bool on) async {
    final deviceId = widget.deviceId;
    if (deviceId == null) {
      await widget.service.setPower(on);
      return;
    }
    final devices = widget.devices;
    final prev = devices?.applyLocalOn(deviceId, on);
    final ok = await widget.service.setPowerOf(deviceId, on);
    if (!ok && prev != null) {
      devices!.restoreLocalOn(deviceId, prev.on, prev.applied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = widget.deviceId == null ? null : widget.devices;
    return AnimatedBuilder(
      animation: _escucha,
      builder: (context, _) {
        final tv = widget.service;
        final deviceId = widget.deviceId;
        final device = _device;
        // ¿El estado que hay a mano es el de ESTE aparato? Con el device del
        // inventario, siempre. Sin él, sólo si además es el aparato elegido:
        // en cualquier otro caso el estado del servicio es el del OTRO Samsung
        // y mostrarlo sería mentir sobre este.
        final mine =
            deviceId == null || device != null || deviceId == tv.selectedDeviceId;
        final known = device != null || (mine && tv.status != null);
        final online = device?.state.reachable ?? (mine && tv.online);
        final on = device?.state.on ?? (mine && tv.isOn);
        final neo = widget.neo;
        // `online` sólo puede ser true si ya hubo una lectura de ESTE aparato
        // (con device del inventario, `known` es true; sin él, `tv.online`
        // exige un status), así que `known && online` es `online`: el punto, el
        // glyph y el control ya caen al mismo gris neutro que corresponde a "no
        // se sabe". El único que necesitaba distinguirlo era el subtítulo.
        // Color de acento del estado. En neo, el "vivo" es accent (ON) y el
        // resto cae a los grises neo; en plano se conserva el warm histórico.
        final accent = !online
            ? CceColors.textTertiary
            : (on
                ? (neo ? _tvAccent : CceColors.warm)
                : CceColors.textSecondary);
        // Sin primera lectura, '—' (mismo placeholder que el tile de la
        // habitación): con dos Samsung, "Fuera de línea" mientras carga sería
        // una afirmación sobre un aparato del que todavía no se sabe nada.
        final sub = !known
            ? '—'
            : (!online ? 'Fuera de línea' : (on ? 'Encendido' : 'En espera'));
        // Dot de estado (solo neo): accent pulsante ON, gris terciario fuera.
        final dotColor = !online
            ? CceColors.textTertiary
            : (on ? _tvAccent : CceColors.textTertiary);
        final glyphColor = online && on ? _tvAccent : CceColors.textTertiary;

        // Mandamos el estado EXPLÍCITO del switch (PUT /tv/power {on:v}):
        // desde la home el isOn cacheado puede estar stale/"unknown", así
        // que setPower garantiza la dirección correcta.
        final Widget control = widget.trailing ??
            (online
                ? CceSwitch(
                    value: on,
                    accent: _tvAccent,
                    onChanged: _setPower,
                  )
                : FeaturedTile.chevron());

        // Nombre del APARATO de esta card. El del inventario manda (es el que
        // ya se ve en la habitación y en el plano); si el device no está, el de
        // GET /tv/tvs. Con un aparato propio SIN nombre, un neutro: caer a
        // `tv.displayName` rotulaba la card del monitor como «65" OLED», que es
        // el nombre del aparato SELECCIONADO. El estado de al lado ya dice «—»
        // correctamente; el título no puede mentir la identidad.
        final name = device != null
            ? inventory!.displayName(device)
            : (deviceId != null
                ? (tv.nameForDeviceId(deviceId) ?? 'Samsung TV')
                : tv.displayName);
        // Un monitor no es un televisor y conviene que se note: con una card
        // por aparato, el ícono es lo que las distingue de un vistazo.
        final isMonitor =
            deviceId != null && (tv.tvForDeviceId(deviceId)?.isMonitor ?? false);
        final Widget glyph = isMonitor
            ? const Icon(Icons.desktop_windows_rounded, size: 24)
            : const CceIcon(CceIcons.tv, size: 24);

        if (widget.tile) {
          return FeaturedTile(
            glyph: glyph,
            glyphColor: glyphColor,
            title: name,
            subtitle: sub,
            dotColor: dotColor,
            dotPulse: online && on,
            control: control,
            onTap: _open,
          );
        }

        final card = CceCard(
          onTap: _open,
          // En neo iguala el radio de las RoomCard (hueCard 24); en plano el
          // default histórico (28).
          radius: neo ? CceRadii.hueCard : CceRadii.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: neo ? CceColors.neoBase : null,
          neo: neo,
          child: Row(
            children: [
              // TV GRANDE extruido, SIN círculo (coherente con el ícono de las
              // RoomCard y la card del soundbar). Reservamos el mismo ancho
              // (48) con Center para no mover título/switch.
              SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: EmbossedGlyph(
                    size: neo ? 28 : 32,
                    color: neo ? glyphColor : accent,
                    highlight: CceEmboss.highlight.color,
                    shadow: CceEmboss.shadow.color,
                    // Ícono del sistema, no el logotipo de Samsung: en una
                    // lista, un logo de marca compite con el contenido y rompe
                    // la familia visual de los demás glyphs.
                    child: isMonitor
                        ? const Icon(Icons.desktop_windows_rounded, size: 30)
                        : const CceIcon(CceIcons.tv, size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: neo
                          ? CceText.title.copyWith(fontSize: 15)
                          : const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: CceColors.textPrimary,
                            ),
                    ),
                    SizedBox(height: neo ? 4 : 2),
                    if (neo)
                      Row(
                        children: [
                          StatusDot(
                            dotColor,
                            pulse: online && on,
                            semanticLabel: sub,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CceText.caption,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CceText.caption.copyWith(color: accent),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              control,
            ],
          ),
        );

        // Sin glow que se derrame: el relieve lo da CceCard (cardFloat) y el
        // estado ON lo marca el switch + el ícono. No se suma halo detrás.
        return card;
      },
    );
  }
}
