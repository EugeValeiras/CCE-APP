import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../utils/room_temperature.dart';

/// Card "clima": temperatura + humedad actuales. Si [room] != null toma solo
/// los sensores de esa habitación; si es null, toda la casa. Se auto-oculta
/// si no hay lecturas. [compact] reduce el alto para vivir en el header.
class TemperatureSummaryCard extends StatelessWidget {
  final DevicesService service;
  final RoomRef? room;
  final bool compact;

  /// OPT-IN: relieve neumórfico (solo home teléfono). Default false ⇒ render
  /// idéntico al actual (los 3 call-sites fuera de Home quedan byte-idénticos).
  final bool neo;

  /// Id del sensor de temperatura a mostrar como hero. Si es null o no matchea
  /// ningún sensor disponible, cae al primero (comportamiento histórico).
  final String? selectedSensorId;

  /// OPT-IN: cuando != null la card se vuelve tappable (abre el selector de
  /// termómetros). Sin afordancia visual (el chevron se quitó a pedido del
  /// dueño); el label con el nombre del termómetro sigue indicando "cuál veo".
  /// Default null ⇒ render y comportamiento idénticos al actual.
  final VoidCallback? onTap;

  /// Long-press: abre el selector de termómetro/termostato. El TAP queda libre
  /// (antes el tap abría el selector: se volvía imposible tocar la card sin
  /// abrirlo).
  final VoidCallback? onLongPress;
  const TemperatureSummaryCard({
    super.key,
    required this.service,
    this.room,
    this.compact = false,
    this.neo = false,
    this.selectedSensorId,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Pool de temperatura del alcance (termómetros + termostatos, en ese
    // orden): lo resuelve RoomTemperature, la MISMA función que alimenta el
    // badge del RoomCard en la home y el picker — dos implementaciones de
    // "qué temperatura es esta" terminaban mostrando números distintos para
    // la misma habitación. OJO: cuando el elegido ES un termostato,
    // RoomTemperatureHeader renderiza el control con +/− y esta card ni se
    // construye.
    final tempSensors = RoomTemperature.pool(service, room);
    // La HUMEDAD sigue siendo asunto de esta card (el badge no la muestra):
    // solo termómetros de la room, sin termostatos.
    final scoped = room == null
        ? service.sensors
        : service.sensors
            .where((s) => room!.deviceIds.contains(s.id))
            .toList();
    final humSensors =
        scoped.where((s) => s.sensor?.humidity != null).toList();
    if (tempSensors.isEmpty && humSensors.isEmpty) return const SizedBox.shrink();

    // Hero = el sensor elegido por el usuario (selectedSensorId) si sigue
    // disponible; si no, el primero (fallback histórico).
    final primary = RoomTemperature.primary(
      service,
      room,
      selectedSensorId: selectedSensorId,
    );
    final primaryHumDevice = humSensors.firstWhere(
      (s) => s.id == primary?.id,
      orElse: () => humSensors.isNotEmpty ? humSensors.first : _dummy,
    );
    final primaryHum = primaryHumDevice.sensor?.humidity;
    final primaryTemp =
        primary == null ? null : RoomTemperature.reading(primary);

    // Card seleccionable: hay handler de tap Y más de un termómetro entre los
    // que elegir. Con un solo sensor el tap no aportaría nada → la card queda
    // estática y el render es el histórico.
    final canPick = onLongPress != null && tempSensors.length > 1;
    // Cuando es seleccionable, el label de temperatura pasa a ser el NOMBRE del
    // termómetro elegido (feedback de "cuál estoy viendo"); si no, "Temperatura".
    final tempLabel = canPick && primary != null
        ? service.displayName(primary)
        : 'Temperatura';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 8),
      child: CceCard(
        // En neo iguala el radio de las RoomCard (hueCard 24) para que la placa
        // se lea de un solo material; en plano conserva el default (28).
        radius: neo ? CceRadii.hueCard : CceRadii.card,
        padding: EdgeInsets.symmetric(
            horizontal: 22, vertical: compact ? 12 : 16),
        // border ya es false en neo (CceCard no lo dibuja); solo en plano.
        border: !neo,
        color: neo ? CceColors.neoBase : CceColors.surface,
        neo: neo,
        onTap: onTap,
        onLongPress: canPick ? onLongPress : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (primaryTemp != null)
              Expanded(
                child: _HeroReading(
                  icon: CceIcons.thermometer,
                  value: primaryTemp.toStringAsFixed(1),
                  unit: '°C',
                  label: tempLabel,
                  color: CceColors.textTertiary,
                  compact: compact,
                  neo: neo,
                ),
              ),
            if (primaryTemp != null && primaryHum != null)
              Container(
                width: 1,
                height: compact ? 40 : 56,
                // En neo, línea GRABADA en la goma (neoDark 1px) en vez del
                // hairline claro; en plano conserva el stroke histórico.
                color: CceColors.strokeSoft,
                margin: EdgeInsets.symmetric(horizontal: CceSpace.lg),
              ),
            if (primaryHum != null)
              Expanded(
                child: _HeroReading(
                  icon: _dropletSvg,
                  value: primaryHum.toStringAsFixed(0),
                  unit: '%',
                  label: 'Humedad',
                  color: CceColors.textTertiary,
                  compact: compact,
                  neo: neo,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // lucide:droplet (icons0.dev) — humedad, vendoreado inline (este archivo no
  // puede tocar cce_icons.dart; el resto de glyphs salen de CceIcons).
  static const String _dropletSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5S5 13 5 15a7 7 0 0 0 7 7"/></svg>';

  // RETIRADA la escala térmica de color (azul→verde→ámbar→rojo según la
  // lectura). Traía cinco colores fuera de la paleta para decir algo que el
  // número ya dice con más precisión, y hacía que el ícono de temperatura y
  // el de humedad nunca coincidieran entre sí.

  static final Device _dummy = Device(id: '', name: '', type: '', state: DeviceState());
}

class _HeroReading extends StatelessWidget {
  /// SVG inline del glyph (CceIcons.* o vendoreado local).
  final String icon;
  final String value;
  final String unit;
  final String label;
  final Color color;
  final bool compact;

  /// En neo el ícono se extruye como goma (EmbossedGlyph + par fijo CceEmboss,
  /// color tenue del valor); en plano queda el SVG plano tintado.
  final bool neo;
  const _HeroReading({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
    this.compact = false,
    this.neo = false,
  });

  @override
  Widget build(BuildContext context) {
    // Color del glyph: en neo lo bajamos a una chispa tenue del acento (igual
    // lenguaje que glyph/dot del resto), sobre la goma oscura; en plano el
    // color pleno histórico.
    final glyphColor = neo ? color.withValues(alpha: 0.85) : color;
    final Widget glyph = neo
        ? EmbossedGlyph(
            size: 20,
            color: glyphColor,
            highlight: CceEmboss.highlight.color,
            shadow: CceEmboss.shadow.color,
            child: CceIcon(icon, size: 20),
          )
        : CceIcon(icon, size: 20, color: glyphColor, emboss: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            glyph,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: CceText.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        SizedBox(height: CceSpace.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Cifras tabulares: al pasar de 23.9 a 24.0 el número no debe
            // empujar la unidad de lugar.
            Text(
              value,
              style: CceText.dataLarge.copyWith(
                fontSize: compact ? 30 : 38,
              ),
            ),
            SizedBox(width: CceSpace.xs),
            // La unidad es texto terciario, no un acento. Antes °C iba en
            // ámbar y % en celeste: dos colores para decir "esto es la unidad
            // de la cifra de al lado", que es justamente lo que menos importa
            // de la card.
            Text(unit, style: CceText.label.copyWith(color: CceColors.textTertiary)),
          ],
        ),
      ],
    );
  }
}
