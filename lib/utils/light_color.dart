import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../theme/cce_tokens.dart';

/// Color efectivo de una luz según su estado real (respeta colormode).
///
/// Única fuente de verdad de "qué color está mostrando esta luz".
/// El bridge Philips Hue NO actualiza hue/sat cuando la luz está en modo
/// `xy` o `ct` (quedan stale): hay que respetar `state.colormode`.
/// Los devices matter no traen colormode/xy y su hue/sat (canónicos
/// hue∈[0,65535], sat∈[0,254]) están frescos → se usan directo.
class LightColorResult {
  final Color color; // RGB final con V=1 (la UI maneja brillo aparte)
  final bool isWhite; // true => modo blanco/CT: la UI usa champagne/pastel
  final double? hueDeg; // hue efectivo 0-360 (null si isWhite)
  final double? sat01; // saturación efectiva 0-1 (null si isWhite)
  const LightColorResult({
    required this.color,
    required this.isWhite,
    this.hueDeg,
    this.sat01,
  });
}

/// Punto de entrada único. Reglas:
/// 1. colormode == 'xy' && xy != null  → xyToColor(); isWhite si la sat HSV
///    resultante <= 0.157 (≡ 40/254, mismo umbral histórico de la app)
/// 2. colormode == 'ct' && ct != null  → ctToWhiteColor(); isWhite = true
///    SIEMPRE (ignora hue/sat stale)
/// 3. resto ('hs' o sin colormode = matter) → hue/65535*360, sat/254;
///    isWhite si sat == null || sat <= 40
/// 4. sin nada de color pero ct != null → ctToWhiteColor(); isWhite = true
/// 5. fallback → blanco cálido (CceColors.warm), isWhite = true
LightColorResult resolveLightColor(DeviceState s) {
  // 1. Modo xy: el color real está en las coordenadas CIE.
  if (s.colormode == 'xy' && s.xy != null) {
    final c = xyToColor(s.xy![0], s.xy![1]);
    final hsv = HSVColor.fromColor(c);
    if (hsv.saturation <= 0.157) {
      return LightColorResult(color: c, isWhite: true);
    }
    return LightColorResult(
      color: c,
      isWhite: false,
      hueDeg: hsv.hue,
      sat01: hsv.saturation,
    );
  }
  // 2. Modo ct: blanco real según mireds (hue/sat están stale).
  if (s.colormode == 'ct' && s.ct != null) {
    return LightColorResult(color: ctToWhiteColor(s.ct!), isWhite: true);
  }
  // 3. Modo hs explícito, o sin colormode (matter): hue/sat canónicos frescos.
  if (s.hue != null && s.sat != null) {
    if (s.sat! <= 40) {
      // Saturación baja: rama blanca.
      final c = s.ct != null ? ctToWhiteColor(s.ct!) : CceColors.warm;
      return LightColorResult(color: c, isWhite: true);
    }
    final h = ((s.hue! / 65535) * 360.0).clamp(0.0, 360.0).toDouble();
    final sat = (s.sat! / 254).clamp(0.0, 1.0).toDouble();
    return LightColorResult(
      color: HSVColor.fromAHSV(1.0, h, sat, 1.0).toColor(),
      isWhite: false,
      hueDeg: h,
      sat01: sat,
    );
  }
  // 4. Sin hue/sat pero con ct: blanco real.
  if (s.ct != null) {
    return LightColorResult(color: ctToWhiteColor(s.ct!), isWhite: true);
  }
  // 5. Fallback: cálido por defecto.
  return const LightColorResult(color: CceColors.warm, isWhite: true);
}

/// CIE xy → sRGB (algoritmo Philips: XYZ con Y=1, matriz Wide RGB D65,
/// normalización por componente máximo, gamma sRGB).
Color xyToColor(double x, double y) {
  if (y <= 0) return Colors.white;
  final xx = x / y;
  final zz = (1 - x - y) / y; // Y = 1
  var r = 1.656492 * xx - 0.354851 - 0.255038 * zz;
  var g = -0.707196 * xx + 1.655397 + 0.036152 * zz;
  var b = 0.051713 * xx - 0.121364 + 1.011530 * zz;
  if (r < 0) r = 0;
  if (g < 0) g = 0;
  if (b < 0) b = 0;
  final maxC = [r, g, b, 1.0].reduce(math.max);
  r /= maxC;
  g /= maxC;
  b /= maxC;
  double gamma(double c) =>
      c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  int to8(double c) => (gamma(c) * 255).round().clamp(0, 255).toInt();
  return Color.fromARGB(255, to8(r), to8(g), to8(b));
}

/// Mireds → blanco real. Interpolación LINEAL EN RGB entre anclas:
/// 153 mireds → 0xFFDDE6F0 (frío), 370 mireds → 0xFFFFE3A0 (cálido, ámbar
/// amarillo — 2700K se ve claramente cálido, no gris). ct > 370 clampea.
Color ctToWhiteColor(int ct) {
  const cold = Color(0xFFDDE6F0); // 153 mireds
  const warm = Color(0xFFFFE3A0); // 370 mireds (más amarillo)
  final t = ((ct - 153) / (370 - 153)).clamp(0.0, 1.0).toDouble();
  return Color.lerp(cold, warm, t)!;
}
