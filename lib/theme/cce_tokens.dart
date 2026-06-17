import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paleta del design system CCE Home (estilo Hue, dark-first).
abstract final class CceColors {
  static const bg = Color(0xFF101014); // fondo app (casi negro, calido)
  static const surface = Color(0xFF1B1D24); // cards/sidebar/sheets
  static const surfaceHigh = Color(0xFF252833); // hover/inputs/chips
  static const stroke = Color(0x14FFFFFF); // bordes hairline
  static const accent = Color(0xFF8A7CFF); // violeta Hue (seed, indicadores nav)
  static const jblOrange = Color(0xFFFF6A00); // naranja de la marca JBL
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

  // Neomorfismo dark (home teléfono). Base media-oscura, NO negro puro.
  // Fuente de luz canónica: arriba-izquierda.
  static const neoBase = Color(0xFF1C1E24); // fondo página + cards neo
  static const neoLight = Color(0xFF2A2D37); // highlight (luz, sup-izq)
  static const neoDark = Color(0xFF0C0D11); // sombra (inf-der en extrusión)
  static const neoSunken = Color(0xFF141519); // fondo de superficies hundidas (badge/switch)
  // Foreground canónico sobre superficies neo (CONTRATO: no improvisar):
  static const neoText = textPrimary; // iconos/labels sobre neoBase/neoSunken
  static const neoTextSub = textSecondary; // subtítulos

  /// Hairline highlight del canto superior de las cards raised (bevel suave).
  static const cardBevel = Color(0x0FFFFFFF); // blanco ~6%
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

  // Pastel Hue: clamps de saturación del pastel de cards encendidas.
  static const double pastelSatMin = 0.12;
  static const double pastelSatMax = 0.40;

  /// ÚNICA fuente del pastel Hue. Conserva hue; S' = (S*0.55) clampeado a
  /// [0.12,0.40]; L' = 0.45 + L*0.35 (afín, sin clamp: L∈[0,1] ⇒
  /// L'∈[0.45,0.80]); alpha forzado 1.0.
  static Color pastel(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(
            (hsl.saturation * 0.55).clamp(pastelSatMin, pastelSatMax).toDouble())
        .withLightness(0.45 + hsl.lightness * 0.35)
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

  /// Relieve neumórfico EXTRUIDO (sale del fondo). Par de sombras EXTERNAS:
  /// highlight sup-izq + sombra inf-der (luz canónica arriba-izquierda).
  /// [intensity] escala opacidad.
  static List<BoxShadow> neo({double blur = 14, double offset = 6, double intensity = 1}) => [
        BoxShadow(
          color: CceColors.neoDark.withValues(alpha: (0.70 * intensity).clamp(0, 1)),
          blurRadius: blur,
          offset: Offset(offset, offset),
          spreadRadius: 1,
        ),
        BoxShadow(
          color: CceColors.neoLight.withValues(alpha: (0.55 * intensity).clamp(0, 1)),
          blurRadius: blur,
          offset: Offset(-offset, -offset),
          spreadRadius: 1,
        ),
      ];

  /// Relieve neumórfico HUNDIDO (inner-shadow nativa vía BlurStyle.inner).
  /// Va en la BoxDecoration de la superficie (NO es un overlay): nada se pinta
  /// sobre el contenido. Sombra interna sup-izq + highlight interno inf-der.
  static List<BoxShadow> neoInset({double blur = 8, double offset = 3, double intensity = 1}) => [
        // sombra interna en sup-izq (la pared interna tapa la luz)
        BoxShadow(
          color: CceColors.neoDark.withValues(alpha: (0.85 * intensity).clamp(0, 1)),
          blurRadius: blur,
          offset: Offset(offset, offset),
          blurStyle: BlurStyle.inner,
        ),
        // highlight interno en inf-der
        BoxShadow(
          color: CceColors.neoLight.withValues(alpha: (0.45 * intensity).clamp(0, 1)),
          blurRadius: blur,
          offset: Offset(-offset, -offset),
          blurStyle: BlurStyle.inner,
        ),
      ];

  /// PLATO (dashboard): relieve cóncavo que SOBRESALE pero hunde la cara.
  /// Combina relieve EXTERNO [neo] (el cuerpo sale del fondo) con sombras
  /// INSET suaves [neoInset] (la cara se mete hacia adentro). Pareja con
  /// [CceGradients.concave]. Es el look de D-pad, dials y el estado grande de
  /// la cerradura. La cara hundida usa la mitad de blur/offset que el relieve.
  static List<BoxShadow> plato({double blur = 15, double offset = 6}) => [
        ...neo(blur: blur, offset: offset),
        ...neoInset(blur: blur * 0.5, offset: offset * 0.5),
      ];

  /// Elevación "almohada flotante": drop difuso hacia ABAJO + rim-light tenue
  /// arriba. Reemplaza el look simétrico de neo() para CARDS (no para botones).
  /// Barato (2 BoxShadow, sin blur de capa). [intensity] escala opacidad.
  static List<BoxShadow> cardFloat({double intensity = 1}) => [
        // drop: flotación hacia abajo (difusa).
        BoxShadow(
          color: CceColors.neoDark.withValues(alpha: (0.55 * intensity).clamp(0, 1)),
          blurRadius: 22,
          offset: const Offset(0, 10),
          spreadRadius: -2,
        ),
        // rim-light: canto de luz superior tenue.
        BoxShadow(
          color: CceColors.neoLight.withValues(alpha: (0.35 * intensity).clamp(0, 1)),
          blurRadius: 14,
          offset: const Offset(0, -6),
          spreadRadius: -6,
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
  /// Tinte de los títulos: gris-claro de "material" (no blanco puro). Es lo que
  /// permite que el relieve neumórfico se note: la letra es del color de la
  /// goma del fondo, con canto de luz arriba-izq y sombra abajo-der.
  static const Color titleInk = Color(0xFFD3D7DF);

  /// Relieve "goma" FUERTE para títulos de header: la letra parece extruida de
  /// la goma del fondo (canto de luz arriba-izquierda + sombra profunda
  /// abajo-derecha + sombra difusa que la despega). Pensado para [titleInk].
  static const List<Shadow> embossShadows = [
    // Canto de luz superior-izquierda (rim claro, casi blanco).
    Shadow(color: Color(0x80FFFFFF), offset: Offset(-1.2, -1.6), blurRadius: 1.5),
    // Sombra de contacto inferior-derecha (profundidad nítida).
    Shadow(color: Color(0xD907080C), offset: Offset(1.8, 2.6), blurRadius: 3),
    // Sombra difusa que despega el título del fondo.
    Shadow(color: Color(0x66000000), offset: Offset(2.6, 4.0), blurRadius: 8),
  ];
  static const display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
    color: titleInk,
    shadows: embossShadows,
  );
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: titleInk,
    shadows: embossShadows,
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
  /// CÓNCAVO (dashboard): plato que sobresale pero hunde la cara. Gradiente
  /// 145° (topLeft→bottomRight) OSCURO→CLARO: la luz canónica arriba-izquierda
  /// pega en la pared lejana, dejando el borde sup-izq en sombra. Para neoBase
  /// reproduce ≈ #16181d→#22252e. darker = base L-0.03, lighter = base L+0.03.
  /// Es la cara de D-pad, dials y el estado grande de la cerradura.
  static LinearGradient concave(Color base) {
    final hsl = HSLColor.fromColor(base);
    final darker = hsl
        .withLightness((hsl.lightness - 0.03).clamp(0.0, 1.0).toDouble())
        .toColor();
    final lighter = hsl
        .withLightness((hsl.lightness + 0.03).clamp(0.0, 1.0).toDouble())
        .toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [darker, lighter],
    );
  }

  /// CONVEXO (dashboard): superficie que sobresale (almohada). Mismo eje 145°
  /// que [concave] pero CLARO→OSCURO: el canto sup-izq atrapa la luz y el
  /// inf-der cae en sombra. Para OK, chips y los +/- steppers.
  static LinearGradient convex(Color base) {
    final hsl = HSLColor.fromColor(base);
    final darker = hsl
        .withLightness((hsl.lightness - 0.03).clamp(0.0, 1.0).toDouble())
        .toColor();
    final lighter = hsl
        .withLightness((hsl.lightness + 0.03).clamp(0.0, 1.0).toDouble())
        .toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lighter, darker],
    );
  }

  /// Superficie de card raised: gradiente vertical SUTIL claro-arriba ->
  /// oscuro-abajo derivado de [base] (efecto convexo de almohada). Paramétrico
  /// por color base (sirve para neoBase, cardOff, neoSunken). NO usar sobre
  /// fills de color saturado (ON) — solo en estado apagado/raised.
  static LinearGradient cardSurface(Color base) {
    final hsl = HSLColor.fromColor(base);
    final top = hsl
        .withLightness((hsl.lightness + 0.045).clamp(0.0, 1.0).toDouble())
        .toColor();
    final bottom = hsl
        .withLightness((hsl.lightness - 0.040).clamp(0.0, 1.0).toDouble())
        .toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    );
  }

  /// centerLeft→centerRight. Cada color pasa por CceTint.pastel.
  /// [] → [warm]; 1 color → duplicado; máx 5.
  static LinearGradient huePastel(List<Color> colors) {
    final src = (colors.isEmpty ? const <Color>[CceColors.warm] : colors).take(5).toList();
    if (src.length == 1) {
      // Un color: gradiente VERTICAL claro→profundo (look Hue real).
      // top = pastel con L'+0.05 (máx 0.82); bottom = L'-0.06 (mín 0.40).
      final hsl = HSLColor.fromColor(CceTint.pastel(src.first));
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          hsl.withLightness((hsl.lightness + 0.05).clamp(0.0, 0.82).toDouble()).toColor(),
          hsl.withLightness((hsl.lightness - 0.06).clamp(0.40, 1.0).toDouble()).toColor(),
        ],
      );
    }
    final pastels = [for (final c in src) CceTint.pastel(c)];
    return LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: pastels);
  }

  /// Fill COMPLETO de LightCard estilo Hue: card siempre llena, gradiente
  /// vertical claro→profundo SIN línea dura. El brillo modula lightness y
  /// saturación (no la altura). NO pasa por CceTint.pastel (preserva el oro).
  /// [brightness] 0..1; [reachable] false ⇒ gris apagado aunque on sea true.
  static LinearGradient lightFull(Color color, double brightness, bool reachable) {
    final hsl = HSLColor.fromColor(color);
    final double b = brightness.clamp(0.0, 1.0).toDouble();
    // Saturación: alta a full, baja un poco al atenuar; piso 0.45 conserva el oro.
    double satP = (0.55 + 0.45 * b).clamp(0.45, 1.0).toDouble();
    // Lightness base modulada por brillo.
    final double lFull = (0.62 + 0.16 * b).clamp(0.62, 0.78).toDouble();
    const double lDim = 0.34;
    double lMid = (lDim + (lFull - lDim) * b);
    // Sin conexión: gris apagado, llena igual.
    if (!reachable) {
      satP *= 0.6;
      lMid = math.min(lMid, 0.55);
    }
    final double lTop = (lMid + 0.09).clamp(0.0, 0.86).toDouble();
    final double lBot = (lMid - 0.11).clamp(0.18, 1.0).toDouble();
    Color at(double l) => hsl
        .withSaturation(satP)
        .withLightness(l)
        .withAlpha(1.0)
        .toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [at(lTop), at(lMid), at(lBot)],
      stops: const [0.0, 0.55, 1.0],
    );
  }

  /// Color representativo (promedio Top/Mid) del gradiente lightFull, para
  /// decidir contraste de texto vía CceTint.textOn.
  static Color lightFullSampleColor(Color color, double brightness, bool reachable) {
    final hsl = HSLColor.fromColor(color);
    final double b = brightness.clamp(0.0, 1.0).toDouble();
    double satP = (0.55 + 0.45 * b).clamp(0.45, 1.0).toDouble();
    final double lFull = (0.62 + 0.16 * b).clamp(0.62, 0.78).toDouble();
    const double lDim = 0.34;
    double lMid = (lDim + (lFull - lDim) * b);
    if (!reachable) {
      satP *= 0.6;
      lMid = math.min(lMid, 0.55);
    }
    final double lTop = (lMid + 0.09).clamp(0.0, 0.86).toDouble();
    return hsl.withSaturation(satP).withLightness((lTop + lMid) / 2).withAlpha(1.0).toColor();
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

  /// LEGACY: fill de LightCard desde abajo, proporcional a brightness 0..1.
  /// Reemplazado por [lightFull] (card llena, sin línea dura). Sin callers tras
  /// la migración de LightCard; conservado como fallback / referencia.
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
