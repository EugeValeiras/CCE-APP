import 'package:flutter/material.dart';

/// Paleta del design system CCE Home (estilo Hue, dark-first).
abstract final class CceColors {
  static const bg = Color(0xFF101014); // fondo app (casi negro, calido)
  static const surface = Color(0xFF1B1D24); // cards/sidebar/sheets
  static const surfaceHigh = Color(0xFF252833); // hover/inputs/chips
  static const stroke = Color(0x14FFFFFF); // bordes hairline
  static const accent = Color(0xFF8A7CFF); // violeta Hue (seed, indicadores nav)
  static const warm = Color(0xFFFFB46B); // luz calida (default luces)
  static const warmDeep = Color(0xFFE8743D);
  static const info = Color(0xFF5AC8FA);
  static const ok = Color(0xFF34D399);
  static const danger = Color(0xFFFF4D5E);
  static const motion = Color(0xFF5A8BFA);
  static const contact = Color(0xFFFF9F43);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xB3FFFFFF); // white70
  static const textTertiary = Color(0x8AFFFFFF); // white54
}

/// Radios de borde congelados del design system.
abstract final class CceRadii {
  static const double card = 28;
  static const double tile = 22;
  static const double sheet = 32;
  static const double control = 16;
  static const double pill = 999;
}

/// Tipografia (system font; display = bold + tracking negativo).
abstract final class CceText {
  static const display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
    color: CceColors.textPrimary,
  );
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: CceColors.textPrimary,
  );
  // Usar con .toUpperCase().
  static const section = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: CceColors.textTertiary,
  );
  static const body = TextStyle(
    fontSize: 15,
    color: CceColors.textPrimary,
  );
  static const caption = TextStyle(
    fontSize: 13,
    color: CceColors.textSecondary,
  );
}

/// Gradientes compartidos.
abstract final class CceGradients {
  /// Card de habitacion encendida: base calida; si [tint] != null (promedio
  /// HSV de las luces ON, provisto por DevicesService.statsFor) se mezcla
  /// 45% sobre la base.
  static LinearGradient roomOn([Color? tint]) {
    var start = CceColors.warm;
    var end = CceColors.warmDeep;
    if (tint != null) {
      start = Color.lerp(start, tint, 0.45) ?? start;
      end = Color.lerp(end, tint, 0.45) ?? end;
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, end],
    );
  }

  static const LinearGradient roomOff = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22242C), Color(0xFF191A20)],
  );

  /// Fill de LightCard desde abajo, proporcional a brightness 0..1.
  static LinearGradient lightFill(Color color, double brightness) {
    final double b = brightness.clamp(0.0, 1.0).toDouble();
    final transparent = color.withValues(alpha: 0.0);
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [color, color, transparent, transparent],
      stops: [0.0, b * 0.82, b, 1.0],
    );
  }
}
