import 'package:flutter/material.dart';
import '../models/event_record.dart';
import '../theme/cce_icons.dart';
import '../theme/cce_tokens.dart';

/// Vocabulario visual de una fila del historial del detalle de un sensor.
class SensorEventRowSpec {
  const SensorEventRowSpec({
    required this.activeLabel,
    required this.idleLabel,
    required this.activeGlyph,
    required this.idleGlyph,
    required this.activeColor,
  });
  final String activeLabel;
  final String idleLabel;
  final String activeGlyph;
  final String idleGlyph;
  final Color activeColor;
}

/// Lo que dibuja una fila: etiqueta, glifo, color y si va resaltada.
class SensorEventRow {
  const SensorEventRow({
    required this.label,
    required this.glyph,
    required this.color,
    required this.active,
  });
  final String label;
  final String glyph;
  final Color color;
  /// true = el sensor estaba activo (movimiento / abierta) en ese evento.
  final bool active;
}

/// El estado del sensor DEL EVENTO (no del device): cada fila cuenta qué pasó
/// en ese instante. null si el evento no trae ese campo.
bool? sensorEventActive(EventRecord ev, {required bool isContact}) {
  final sensor = ev.payload?['sensor'];
  if (sensor is! Map) return null;
  final v = isContact ? sensor['contact'] : sensor['motion'];
  return v is bool ? v : null;
}

/// La lectura de luz del evento («17 lx»), o null.
String? sensorEventLux(EventRecord ev) {
  final sensor = ev.payload?['sensor'];
  if (sensor is! Map) return null;
  final v = sensor['lux'];
  return v is num ? '${v.round()} lx' : null;
}

/// Una fila del historial del sensor (CCE#112). El bloque viene ACUMULADO: un
/// cambio de luz del SNZB-03PR2 trae también `motion`, así que la fila dice
/// las dos cosas («Sin movimiento · 17 lx»); una lectura de luz sola lleva su
/// propio glifo, no las huellas; y sin nada reconocible dice «Actualización».
SensorEventRow sensorEventRow(
  EventRecord ev, {
  required bool isContact,
  required SensorEventRowSpec spec,
}) {
  final active = sensorEventActive(ev, isContact: isContact);
  final lux = sensorEventLux(ev);
  final label = active == null
      ? (lux ?? 'Actualización')
      : [active ? spec.activeLabel : spec.idleLabel, lux]
          .whereType<String>()
          .join(' · ');
  final glyph = active == true
      ? spec.activeGlyph
      : (active == null && lux != null ? CceIcons.sunMedium : spec.idleGlyph);
  return SensorEventRow(
    label: label,
    glyph: glyph,
    color: active == true ? spec.activeColor : CceColors.textTertiary,
    active: active == true,
  );
}
