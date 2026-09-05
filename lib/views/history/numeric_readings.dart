import 'package:flutter/material.dart';
import '../../theme/cce_icons.dart';
import '../../theme/cce_tokens.dart';

/// Una lectura numérica del bloque sensor: cómo se dibuja y cómo se escribe.
///
/// UNA tabla para todo el historial (CCE#112): la lectura suelta, la corrida
/// colapsada y las claves de agrupación. Antes cada lugar tenía su propia
/// lista y la de lux quedó sin escribir en dos de los tres.
class NumericReading {
  const NumericReading(this.key, this.icon, this.color, this.format);
  final String key;
  final String icon;
  final Color color;
  final String Function(double) format;
}

/// Las lecturas numéricas que el historial sabe leer, en orden de prioridad
/// (la primera decide el ícono cuando vienen varias juntas).
final List<NumericReading> numericReadings = [
  NumericReading('temperature', CceIcons.thermometer, CceColors.contact,
      (v) => '${v.toStringAsFixed(1)}°'),
  NumericReading('humidity', CceIcons.droplet, CceColors.info,
      (v) => '${v.toStringAsFixed(0)}%'),
  NumericReading(
      'lux', CceIcons.sunMedium, CceColors.warm, (v) => '${v.round()} lx'),
];

/// Las claves de la tabla, para quien sólo necesita saber qué campos son lecturas.
final List<String> numericReadingKeys =
    numericReadings.map((r) => r.key).toList();

/// TODAS las lecturas numéricas presentes en [sensor], con su valor, en el
/// orden de la tabla. Los providers emiten el bloque ACUMULADO (un movimiento
/// del SNZB-03PR2 trae su lux; un sensor combinado trae temperatura Y luz), y
/// devolver sólo la primera escondía el resto.
List<(NumericReading, double)> numericReadingsOf(Map sensor) {
  final out = <(NumericReading, double)>[];
  for (final r in numericReadings) {
    final v = sensor[r.key];
    if (v is num) out.add((r, v.toDouble()));
  }
  return out;
}

/// «21.5° · 17 lx»: las lecturas de [sensor] en una línea, o null si no hay.
String? numericReadingsLine(Map sensor) {
  final all = numericReadingsOf(sensor);
  if (all.isEmpty) return null;
  return all.map((r) => r.$1.format(r.$2)).join(' · ');
}
