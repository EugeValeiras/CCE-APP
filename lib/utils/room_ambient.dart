import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../theme/components/sensor_chip.dart';
import 'room_temperature.dart';

/// "¿Qué tiene esta habitación para mostrar cuando no tiene luces?"
///
/// Hermano de [RoomTemperature] y por el mismo motivo: la `RoomCard` NO sabe de
/// sensores — recibe valores ya resueltos. Acá vive la única traducción de
/// devices a chips, pura y testeable sin montar widgets.
///
/// La temperatura NO se elige acá: sale de [RoomTemperature.source] con el
/// `selectedSensorId` de `TempSensorPrefs`, el mismo camino que el badge de las
/// filas con luces y el header del detalle. Si el usuario eligió qué termómetro
/// manda en esa habitación, el chip muestra ESE.
///
/// Sólo se leen los sensores que el chip sabe expresar (temperatura, humedad,
/// contacto, movimiento, mandos). Todo lo demás que viva en `room.deviceIds`
/// — un TV, un parlante, una cerradura — se ignora en silencio: la lista de
/// devices de una habitación no es una lista de sensores.
abstract final class RoomAmbient {
  /// Tope de chips por fila. Tres entran cómodos en el ancho que queda entre
  /// el ícono y el chevron en un teléfono chico; el cuarto empieza a competir
  /// con el nombre de la habitación, que es lo que la fila viene a decir.
  static const int maxChips = 3;

  /// Chips a mostrar para [room], en ORDEN FIJO por tipo de dato:
  /// temperatura → humedad → contacto → movimiento → mandos.
  ///
  /// El orden es por tipo y no por device para que la fila no baile entre
  /// refrescos: un evento de sensor cambia el VALOR de un chip, nunca su lugar.
  /// Lista vacía ⇒ la card no dibuja nada (una habitación sin sensores legibles
  /// se ve como hoy, con el nombre solo).
  static List<SensorChipData> forRoom(
    DevicesService service,
    RoomRef room, {
    String? selectedSensorId,
  }) {
    final devices =
        service.sensors.where((d) => room.deviceIds.contains(d.id)).toList();
    final chips = <SensorChipData>[];

    // ── Temperatura y humedad: la lectura de ambiente ───────────────────────
    final source =
        RoomTemperature.source(service, room, selectedSensorId: selectedSensorId);
    final temperature = source == null ? null : RoomTemperature.reading(source);
    if (temperature != null) {
      final value = temperature.toStringAsFixed(1);
      chips.add(SensorChipData(
        glyph: CceIcons.thermometer,
        label: '$value°',
        semanticLabel: 'Temperatura $value grados',
      ));
    }

    // Del MISMO aparato que la temperatura mientras se pueda (no se mezclan dos
    // lecturas de dos lugares distintos como si fueran una). Si el elegido no
    // reporta humedad — un termostato, típicamente — se acepta el primer
    // higrómetro de la habitación antes que perder el dato.
    final humidity = source?.sensor?.humidity ??
        devices
            .map((d) => d.sensor?.humidity)
            .firstWhere((h) => h != null, orElse: () => null);
    if (humidity != null) {
      final value = humidity.toStringAsFixed(0);
      chips.add(SensorChipData(
        glyph: CceIcons.droplet,
        label: '$value%',
        semanticLabel: 'Humedad $value por ciento',
      ));
    }

    // ── Contacto: el estado de las puertas ──────────────────────────────────
    // Se muestra SIEMPRE que haya sensor, abierto o cerrado: "Cerrada" es
    // información (la casa está cerrada), no ruido. Abierto va en
    // [CceColors.contact], el mismo naranja del StatusDot que reemplaza —
    // el hecho es el mismo, el lenguaje de color también.
    final contacts = devices.where((d) => d.isContactSensor).toList();
    if (contacts.isNotEmpty) {
      final open = contacts.where((d) => d.sensor?.contact == true).length;
      final label = open > 0
          ? (open == 1 ? 'Abierta' : '$open abiertas')
          : (contacts.length == 1 ? 'Cerrada' : '${contacts.length} cerradas');
      chips.add(SensorChipData(
        glyph: open > 0 ? CceIcons.doorOpen : CceIcons.doorClosed,
        label: label,
        glyphColor: open > 0 ? CceColors.contact : null,
        semanticLabel: open > 0 ? 'Puerta abierta' : 'Puerta cerrada',
      ));
    }

    // ── Movimiento: SÓLO cuando lo hay ──────────────────────────────────────
    // Al revés que el contacto: "sin movimiento" es el estado por defecto de la
    // casa entera y estaría permanentemente en pantalla sin decir nada. Aparece
    // y desaparece igual que el dot azul que reemplaza en esta fila.
    if (devices.any((d) => d.isMotionSensor && d.sensor?.motion == true)) {
      chips.add(const SensorChipData(
        glyph: CceIcons.personStanding,
        label: 'Movimiento',
        glyphColor: CceColors.motion,
        semanticLabel: 'Movimiento detectado',
      ));
    }

    // ── Mandos: cuántos controles hay para esta habitación ───────────────────
    final remotes = devices.where(_isRemote).length;
    if (remotes > 0) {
      chips.add(SensorChipData(
        glyph: CceIcons.handTap,
        label: remotes == 1 ? '1 mando' : '$remotes mandos',
        semanticLabel: remotes == 1 ? '1 mando' : '$remotes mandos',
      ));
    }

    return chips.length > maxChips ? chips.sublist(0, maxChips) : chips;
  }

  /// Mando: un control a pilas (botón de 1 o 4 teclas, tap dial). Se cuentan
  /// APARATOS, no teclas — un mando de cuatro botones sigue siendo un mando.
  ///
  /// El relé-pulsador de pared queda afuera ([Device.isButtonRelay]): es un
  /// actuador que además tiene tecla, y contarlo como mando sería anunciar como
  /// control de la habitación algo que ya se cuenta entre sus luces. El
  /// `sensor != null` descarta relés legacy sin capabilities, que sólo se
  /// distinguen de un mando por tener estado propio y ninguna pila.
  static bool _isRemote(Device d) =>
      (d.hasCapability('button') || d.isSwitch) &&
      !d.isButtonRelay &&
      d.sensor != null;
}
