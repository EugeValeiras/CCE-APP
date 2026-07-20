import '../models/device.dart';
import '../models/event_record.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';
import '../utils/time_format.dart';
import '../widgets/event_history_section.dart';

/// Nombre real de una pulsación (contrato del backend: lastKey 0/1/2).
String pressKindLabel(int? key) => switch (key) {
      0 => 'Click',
      1 => 'Doble click',
      2 => 'Mantenido',
      null => 'Pulsación',
      _ => 'Pulsación $key',
    };

/// Ícono por tipo de pulsación (icons0/lucide, ya vendoreados).
String pressKindGlyph(int? key) => switch (key) {
      1 => CceIcons.handTap, // doble
      2 => CceIcons.clock, // mantenido = tiempo
      _ => CceIcons.handTap,
    };

/// Valor del well "ÚLTIMA": relativo del último disparo.
String lastPressValue(int? trigTime) => trigTime == null
    ? '—'
    : TimeFormat.relative(DateTime.fromMillisecondsSinceEpoch(trigTime));

/// El backend indexa los eventos por el bindingId del provider, no por el
/// dev_* canónico.
String historyIdOf(Device d) =>
    d.bindingIds.isNotEmpty ? d.bindingIds.first : d.id;

/// Arma el historial de pulsaciones combinando las DOS fuentes que el backend
/// persiste para el mismo instante:
///  - `device.state.changed` → QUÉ se pulsó (outlet + lastKey).
///  - `automation.triggered` → QUÉ automatización disparó esa pulsación.
///
/// El evento de automatización llega ~ms después del de estado, así que se
/// aparean por proximidad temporal (ventana de 3 s).
List<EventHistoryEntry> buttonHistoryEntries(
  List<EventRecord> events, {
  required DevicesService service,
  required int outletCount,
}) {
  const window = Duration(seconds: 3);

  // Automatizaciones disparadas, para aparear.
  final fired = <({DateTime ts, String name})>[];
  for (final ev in events) {
    if (ev.eventName != 'automation.triggered') continue;
    final id = ev.payload?['automationId'];
    if (id is! String) continue;
    fired.add((ts: ev.timestamp, name: service.automationName(id)));
  }

  final out = <EventHistoryEntry>[];
  for (final ev in events) {
    if (ev.eventName != 'device.state.changed') continue;
    final sensor = ev.payload?['sensor'];
    if (sensor is! Map) continue;
    final key = (sensor['lastKey'] as num?)?.toInt();
    if (key == null) continue; // no fue una pulsación
    final outlet = (sensor['outlet'] as num?)?.toInt();
    final ts = ev.timestamp;

    final kind = pressKindLabel(key);
    final label = outletCount > 1 && outlet != null
        ? 'Botón ${outlet + 1} · $kind'
        : kind;

    // ¿Alguna automatización disparó junto con esta pulsación?
    String? detail;
    for (final f in fired) {
      if (f.ts.difference(ts).abs() <= window) {
        detail = 'Disparó «${f.name}»';
        break;
      }
    }

    out.add(EventHistoryEntry(
      label: label,
      detail: detail,
      glyph: pressKindGlyph(key),
      color: CceColors.warm,
      glowing: true,
      timestamp: ts,
    ));
  }
  return out;
}
