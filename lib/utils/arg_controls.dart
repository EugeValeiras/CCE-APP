import '../models/capability.dart';
import '../models/device.dart';

/// Rango y paso con los que el editor de acciones arma un control NUMÉRICO
/// (CCE#62). El catálogo declara un rango documental, pero el bueno es el del
/// device: el setpoint de un termostato va de `state.minTemp` a `state.maxTemp`
/// y cambia por modelo, así que el ArgSpec nombra esos campos en
/// `minFrom`/`maxFrom` y acá se resuelven contra el estado real.
class ArgRange {
  final double min;
  final double max;

  /// 0.5 = medio grado. Siempre > 0.
  final double step;

  const ArgRange({required this.min, required this.max, required this.step});

  /// Redondea al paso y deja el valor dentro del rango.
  double snap(double value) {
    final snapped = min + ((value - min) / step).round() * step;
    return snapped.clamp(min, max).toDouble();
  }

  /// Cuántas posiciones tiene el slider.
  int get divisions => ((max - min) / step).round().clamp(1, 1000);

  /// El arg viaja como int cuando el paso es entero (volumen) y como double
  /// cuando no (medio grado del termostato).
  num asArg(double value) {
    final v = snap(value);
    return step % 1 == 0 ? v.round() : v;
  }
}

/// Rango efectivo de un arg numérico, o null si no hay uno utilizable (un
/// `step` suelto sin min/max, como el de volumeUp, no se puede dibujar).
ArgRange? argRangeFor(CatalogArgSpec arg, DeviceState state) {
  if (arg.type != 'number') return null;
  final min = (state.numField(arg.minFrom) ?? arg.min)?.toDouble();
  final max = (state.numField(arg.maxFrom) ?? arg.max)?.toDouble();
  if (min == null || max == null || max <= min) return null;
  final step = (arg.step ?? 1).toDouble();
  return ArgRange(min: min, max: max, step: step > 0 ? step : 1);
}

/// Valor con el que nace el control: el VIGENTE del campo que la acción afecta
/// (el setpoint de ahora, el volumen de ahora). Un slider de temperatura que
/// nace en el mínimo propone 5°, que no es lo que nadie quiere pedir.
num initialArgValue(CatalogActionSpec spec, ArgRange range, DeviceState state) {
  final current =
      state.numField(spec.affects.isNotEmpty ? spec.affects.first : null);
  return range.asArg(current?.toDouble() ?? range.min);
}

/// 21 → "21", 21.5 → "21.5" (misma convención que la pantalla del termostato).
String fmtArgNum(num n) => n == n.roundToDouble()
    ? n.toStringAsFixed(0)
    : n.toDouble().toStringAsFixed(1);
