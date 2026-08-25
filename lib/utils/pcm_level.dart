/// Medidores de nivel del audio de la llamada (CCE#12).
///
/// Sin un medidor, "no se escucha nada" es indebuggeable: no se distingue falta
/// de audio de falta de permiso, de un interlocutor mudo o de un micrófono
/// silenciado. Es criterio de aceptación del issue, igual que en el dashboard.
///
/// El formato es el de la línea, sin transcodificar: **PCM 16-bit little-endian,
/// mono** (`EugeValeiras/CCE#5`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// RMS de un bloque PCM 16-bit LE, normalizado a 0-1.
///
/// Un byte suelto al final se ignora: es medio sample y no vale la pena
/// desalinear el recorrido por él.
double pcmLevel(Uint8List bytes) {
  final samples = bytes.lengthInBytes ~/ 2;
  if (samples == 0) return 0;
  final view = ByteData.sublistView(bytes, 0, samples * 2);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = view.getInt16(i * 2, Endian.little).toDouble();
    sum += s * s;
  }
  return math.min(1, math.sqrt(sum / samples) / 32768);
}

/// Promedio de niveles en una ventana, con caída cuando deja de llegar audio.
///
/// Un medidor congelado en un valor alto es PEOR que no tener medidor: dice que
/// hay señal cuando la llamada ya terminó. Por eso [decay] existe y la pantalla
/// lo llama aunque no haya llegado nada.
class LevelMeter {
  double _sum = 0;
  int _count = 0;
  double _value = 0;

  /// Nivel actual, 0-1.
  double get value => _value;

  /// Suma un bloque de PCM al promedio de la ventana en curso.
  void add(Uint8List bytes) {
    final level = pcmLevel(bytes);
    _sum += level * level;
    _count++;
  }

  /// Cierra la ventana: si entró audio devuelve su RMS, si no baja el nivel.
  ///
  /// El factor de caída es el mismo del dashboard (0,6 cada 250 ms allá, cada
  /// 100 ms acá): baja rápido pero no de golpe, que es lo que hace que el
  /// medidor se lea como un VU y no como un parpadeo.
  void tick() {
    if (_count == 0) {
      _value *= 0.6;
      if (_value < 0.001) _value = 0;
      return;
    }
    _value = math.sqrt(_sum / _count);
    _sum = 0;
    _count = 0;
  }

  void reset() {
    _sum = 0;
    _count = 0;
    _value = 0;
  }
}
