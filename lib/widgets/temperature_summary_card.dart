import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/cce_card.dart';
import '../utils/room_temperature.dart';

/// Card "clima": temperatura + humedad actuales y, opcionalmente, cuántas
/// luces hay encendidas ([showLightsOn], hero de la home). Si [room] != null
/// toma solo los sensores de esa habitación; si es null, toda la casa. Se
/// auto-oculta si no hay nada que mostrar.
///
/// Es un hero de UNA fila de [kHeight]: cada dato es una columna con su
/// etiqueta en [CceText.section] arriba (el nombre del termómetro elegido
/// sube a etiqueta y deja de truncarse como "Living thermom…") y el número
/// en cifras tabulares abajo. Sin íconos: el número y la unidad ya dicen qué
/// es cada cosa.
class TemperatureSummaryCard extends StatelessWidget {
  final DevicesService service;
  final RoomRef? room;

  /// Sin padding vertical externo (vive en el header de una habitación).
  final bool compact;

  /// OPT-IN: relieve (solo home teléfono). Default false ⇒ render plano.
  final bool neo;

  /// Id del sensor de temperatura a mostrar como hero. Si es null o no matchea
  /// ningún sensor disponible, cae al primero (comportamiento histórico).
  final String? selectedSensorId;

  /// Tercera columna "Encendidas · N de M" con las luces de TODA la casa.
  /// Sólo tiene sentido en el hero de la home (scope casa); en una
  /// habitación el conteo ya lo lleva el encabezado de "Luces".
  final bool showLightsOn;

  /// OPT-IN: cuando != null la card se vuelve tappable.
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
    this.showLightsOn = false,
    this.onTap,
    this.onLongPress,
  });

  /// Altura del hero. Medida de componente (como `RoomCard.kHeight`): 88 → 72
  /// para que "Habitaciones" entre antes en la primera pantalla.
  static const double kHeight = 72;

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

    // Luces encendidas de toda la casa (sólo con showLightsOn).
    final lights = showLightsOn ? service.lights : const <Device>[];
    final lightsOn = lights.where((l) => l.state.on).length;

    if (tempSensors.isEmpty && humSensors.isEmpty && lights.isEmpty) {
      return const SizedBox.shrink();
    }

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

    // Card seleccionable: hay handler de long-press Y más de un termómetro
    // entre los que elegir. Con un solo sensor no aportaría nada.
    final canPick = onLongPress != null && tempSensors.length > 1;
    // Cuando es seleccionable, la etiqueta de temperatura pasa a ser el
    // NOMBRE del termómetro elegido (feedback de "cuál estoy viendo").
    final tempLabel = canPick && primary != null
        ? service.displayName(primary)
        : 'Temperatura';

    final columns = <Widget>[
      if (primaryTemp != null)
        _HeroReading(
          label: tempLabel,
          value: primaryTemp.toStringAsFixed(1),
          unit: '°C',
        ),
      if (primaryHum != null)
        _HeroReading(
          label: 'Humedad',
          value: primaryHum.toStringAsFixed(0),
          unit: '%',
        ),
      if (lights.isNotEmpty)
        _HeroReading(
          label: 'Encendidas',
          value: '$lightsOn',
          unit: 'de ${lights.length}',
          // El único número de acento del hero: cuántas luces hay prendidas
          // es de lo que la app trata.
          valueColor: lightsOn > 0 ? CceColors.accent : null,
        ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : CceSpace.sm),
      child: SizedBox(
        height: kHeight,
        child: CceCard(
          radius: CceRadii.card,
          padding: EdgeInsets.symmetric(
            horizontal: CceSpace.lg,
            vertical: CceSpace.sm,
          ),
          // border ya es false en neo (CceCard no lo dibuja); solo en plano.
          border: !neo,
          color: neo ? CceColors.neoBase : CceColors.surface,
          neo: neo,
          onTap: onTap,
          onLongPress: canPick ? onLongPress : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 40,
                    color: CceColors.strokeSoft,
                    margin: EdgeInsets.symmetric(horizontal: CceSpace.lg),
                  ),
                Expanded(child: columns[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final Device _dummy = Device(id: '', name: '', type: '', state: DeviceState());
}

class _HeroReading extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  /// Color del número; null ⇒ texto primario.
  final Color? valueColor;
  const _HeroReading({
    required this.label,
    required this.value,
    required this.unit,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CceText.section,
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
              style: valueColor == null
                  ? CceText.dataLarge
                  : CceText.dataLarge.copyWith(color: valueColor),
            ),
            SizedBox(width: CceSpace.xs),
            // La unidad es texto terciario, no un acento.
            Flexible(
              child: Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CceText.label.copyWith(color: CceColors.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
