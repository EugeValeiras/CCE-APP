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

  // REGLA: Room cards ON usan el gradiente pastel del tint real de las
  // luces (Hue-style); todo color derivado de luces pasa por CceTint.pastel,
  // que vive SOLO en cce_tokens.dart.
  // LEGACY: ya no lo usan las room cards; candidato a limpieza posterior.
  static const amberHi = Color(0xFFF4D993);
  // LEGACY: ya no lo usan las room cards; candidato a limpieza posterior.
  static const amberLo = Color(0xFFE7BE69);
  // LEGACY: ya no lo usan las room cards; candidato a limpieza posterior.
  static const inkOnAmber = Color(0xFF211B10); // texto sobre ámbar

  // Cards estilo Hue (light/sensor tiles, room cards apagadas).
  static const cardOff = Color(0xFF232327); // base apagada (gris neutro Hue, sin tinte azul)
  static const cardOffHigh = Color(0xFF2F2F33); // círculo de ícono / fallback escena sin swatch
  static const hueDim = Color(0x2E000000); // overlay de atenuación a la derecha del handle (zona "no llenada")
  static const info = Color(0xFF5AC8FA);
  static const ok = Color(0xFF34D399);
  static const danger = Color(0xFFFF4D5E);
  static const motion = Color(0xFF5A8BFA);
  static const contact = Color(0xFFFF9F43);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xB3FFFFFF); // white70
  static const textTertiary = Color(0x8AFFFFFF); // white54

  // Plano (canvas dark del floor plan recoloreado).
  static const planWall = Color(0xFF9BA3B5);
  static const planGrid = Color(0x0BFFFFFF); // blanco ~4.5%
  static const planCanvasHi = Color(0xFF1E2029);
  static const planCanvasLo = Color(0xFF14151B);

  // Colores por tipo de trigger de automatizaciones (aliases).
  static const triggerSensor = motion; // #5A8BFA
  static const triggerSchedule = warm; // #FFB46B
  static const triggerManual = accent; // #8A7CFF
}

/// Pipeline de tint estilo Hue: ningún color derivado de luces se pinta
/// crudo — siempre pasa por [normalize] (clamp de saturación y luminosidad
/// en HSL, conservando el hue).
abstract final class CceTint {
  static const double satMin = 0.38, satMax = 0.62;
  static const double lightMin = 0.52, lightMax = 0.64;

  /// Clamp en HSL: conserva hue, S→[satMin,satMax], L→[lightMin,lightMax].
  static Color normalize(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(hsl.saturation.clamp(satMin, satMax).toDouble())
        .withLightness(hsl.lightness.clamp(lightMin, lightMax).toDouble())
        .toColor();
  }

  /// Foreground para superficies tintadas: si la base es clara, texto
  /// casi-negro; si no, blanco.
  static Color textOn(Color base) =>
      base.computeLuminance() > 0.45 ? const Color(0xFF14161C) : Colors.white;

  /// 70% alpha del resultado de [textOn] (para subtítulos).
  static Color subTextOn(Color base) => textOn(base).withValues(alpha: 0.7);

  // Pastel Hue: clamps del pastel de cards encendidas.
  static const double pastelSatMin = 0.42;
  static const double pastelSatMax = 0.58;
  static const double pastelLightMin = 0.74;
  static const double pastelLightMax = 0.82;

  /// ÚNICA fuente del pastel Hue. Conserva hue; S→[0.42,0.58];
  /// L→[0.74,0.82]; alpha forzado 1.0.
  static Color pastel(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(hsl.saturation.clamp(pastelSatMin, pastelSatMax).toDouble())
        .withLightness(hsl.lightness.clamp(pastelLightMin, pastelLightMax).toDouble())
        .withAlpha(1.0)
        .toColor();
  }

  /// Tinta sobre fondo pastel (el pastel garantiza L>=0.74, siempre legible).
  static const Color inkOnPastel = Color(0xFF1A1A1E);
  static const Color inkOnPastelSub = Color(0x991A1A1E); // 60%
}

/// Sombras/glow compartidos del design system.
abstract final class CceShadows {
  /// Glow suave bajo cards encendidas.
  static List<BoxShadow> glowOn(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
          spreadRadius: -4,
        ),
      ];

  /// Halo de dots de dispositivo en el plano.
  static List<BoxShadow> glowDot(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.45),
          blurRadius: 18,
          spreadRadius: 2,
        ),
      ];
}

/// Radios de borde congelados del design system.
abstract final class CceRadii {
  static const double card = 28;
  static const double tile = 22;
  static const double sheet = 32;
  static const double control = 16;
  static const double pill = 999;
  static const double hueCard = 24; // light/sensor tiles y room cards
  static const double hueScene = 16; // scene cards
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
  /// centerLeft→centerRight. Cada color pasa por CceTint.pastel.
  /// [] → [warm]; 1 color → duplicado; máx 5.
  static LinearGradient huePastel(List<Color> colors) {
    final src = (colors.isEmpty ? const <Color>[CceColors.warm] : colors).take(5).toList();
    if (src.length == 1) {
      // Un color: gradiente VERTICAL claro→profundo (look Hue real).
      final hsl = HSLColor.fromColor(CceTint.pastel(src.first));
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          hsl.withLightness(0.78).toColor(),
          hsl.withLightness(0.62).toColor(),
        ],
      );
    }
    final pastels = [for (final c in src) CceTint.pastel(c)];
    return LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: pastels);
  }

  // LEGACY: ya no lo usan las room cards; candidato a limpieza posterior.
  static LinearGradient roomOn([Color? tint]) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [CceColors.amberHi, CceColors.amberLo],
    );
  }

  // LEGACY: ya no lo usan las room cards; candidato a limpieza posterior.
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
