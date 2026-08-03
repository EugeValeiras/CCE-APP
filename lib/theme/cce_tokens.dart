import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Design system de CCE Home.
///
/// DIRECCIÓN: instrumento cálido de casa. Se mira de noche, con poca luz, por
/// pocos segundos. De ahí se derivan TODAS las decisiones:
///
///  - Fondo profundo y quieto, de hue CÁLIDO (30°) — no el azul frío de las
///    apps de dashboard. La casa de noche es ámbar, no cian.
///  - UN solo acento: [accent] = el ámbar de la luz encendida. Es de lo que la
///    app trata. Todo lo demás (marcas de terceros, colores de dispositivo)
///    vive en el detalle, nunca en las listas.
///  - UNA sola estrategia de profundidad: escalones de superficie + hairlines.
///    Nada de relieve. Las sombras existen sólo para lo que de verdad flota
///    (sheets, diálogos) y son ambientales, no direccionales.
///
/// CONTRATO: ningún widget inventa colores, radios ni espaciados. Todo sale de
/// acá. Si algo no está, se agrega acá — no se hardcodea en la vista.
abstract final class CceColors {
  // ---------------------------------------------------------------------
  // Superficies. Una sola escala de elevación: mismo hue (30°), misma
  // saturación baja, sólo cambia la luminosidad. Cada escalón es de ~4 puntos
  // de L: se siente, no se ve.
  // ---------------------------------------------------------------------

  /// L0 · lienzo de la app. TODAS las pantallas usan este fondo — sin
  /// excepciones, sin gradientes propios.
  static const bg = Color(0xFF121110);

  /// L1 · cards, sheets, barras.
  static const surface = Color(0xFF1A1817);

  /// L2 · inputs, chips, tracks, estados hover.
  static const surfaceHigh = Color(0xFF232120);

  /// L3 · lo que se apoya sobre L2 (menús, popovers, thumbs).
  static const surfaceTop = Color(0xFF2C2A27);

  /// Superficie HUNDIDA (tracks de slider, huecos). Más oscura que el lienzo:
  /// un hueco recibe menos luz. Reemplaza al viejo relieve `neoInset`.
  static const surfaceSunken = Color(0xFF0D0C0B);

  // ---------------------------------------------------------------------
  // Hairlines. Un borde no debe verse; debe encontrarse cuando se lo busca.
  // ---------------------------------------------------------------------

  /// Borde estándar de card/tile.
  static const stroke = Color(0x14FFF6EC);

  /// Separación suave (divisores internos).
  static const strokeSoft = Color(0x0AFFF6EC);

  /// Énfasis: card seleccionada, borde de foco.
  static const strokeStrong = Color(0x2EFFF6EC);

  // ---------------------------------------------------------------------
  // Acento. UNO solo, y es el ámbar de la luz encendida.
  // ---------------------------------------------------------------------

  /// Acento del sistema: selección, controles activos, indicadores.
  static const accent = Color(0xFFFFB46B);

  /// Ámbar profundo: hover/pressed del acento, borde de elementos activos.
  static const accentDeep = Color(0xFFD98A45);

  /// Acento al 12% para fills de estado seleccionado.
  static const accentWash = Color(0x1FFFB46B);

  /// Alias histórico de [accent] (color canónico de luz cálida).
  static const warm = accent;
  static const warmDeep = accentDeep;

  // ---------------------------------------------------------------------
  // Texto. Cuatro niveles, todos cálidos: el blanco puro sobre un fondo
  // cálido se ve azul por contraste simultáneo.
  // ---------------------------------------------------------------------
  static const textPrimary = Color(0xFFF6F1EB);
  static const textSecondary = Color(0xAEF6F1EB);
  static const textTertiary = Color(0x73F6F1EB);
  static const textMuted = Color(0x47F6F1EB);

  // ---------------------------------------------------------------------
  // Semánticos. Desaturados: en dark, un verde puro vibra y ensucia.
  // Se usan SÓLO para estado, nunca para decorar.
  // ---------------------------------------------------------------------
  static const ok = Color(0xFF6FBF8B);
  static const danger = Color(0xFFE0685F);
  static const info = Color(0xFF6BA9C9);

  /// Sensor de movimiento (evento de presencia).
  static const motion = Color(0xFF7C9BD6);

  /// Sensor de apertura (puerta/ventana).
  static const contact = Color(0xFFD9A05B);

  // ---------------------------------------------------------------------
  // Marcas de terceros. NO se usan en listas ni en la home: sólo dentro del
  // detalle del dispositivo, donde la marca informa en vez de competir.
  // ---------------------------------------------------------------------
  static const jblOrange = Color(0xFFFF6A00);

  // ---------------------------------------------------------------------
  // Cards de dispositivo.
  // ---------------------------------------------------------------------

  /// Card apagada. Es [surface]: un dispositivo apagado no es un color
  /// especial, es una superficie más.
  static const cardOff = surface;

  /// Círculo de ícono / fallback de escena sin swatch.
  static const cardOffHigh = surfaceHigh;

  /// Atenuación a la derecha del handle de brillo.
  static const hueDim = Color(0x33000000);

  /// Dot de "luz encendida" — el mismo ámbar del acento.
  static const amberHi = accent;

  // LEGACY: sin callers tras la unificación del acento.
  static const amberLo = accentDeep;
  static const inkOnAmber = Color(0xFF201709);

  // ---------------------------------------------------------------------
  // Plano (floor plan recoloreado). Mismo hue cálido que el resto.
  // ---------------------------------------------------------------------
  static const planWall = Color(0xFFA79E93);
  static const planGrid = Color(0x0BFFF6EC);
  static const planCanvasHi = Color(0xFF1F1D1B);
  static const planCanvasLo = Color(0xFF151312);

  // ---------------------------------------------------------------------
  // Triggers de automatizaciones. Se diferencian por semántica, no por
  // decoración: sensor = frío (algo pasó afuera), horario = acento (lo
  // programaste vos), manual = neutro (lo hacés a mano).
  // ---------------------------------------------------------------------
  static const triggerSensor = motion;
  static const triggerSchedule = accent;
  static const triggerManual = textTertiary;

  // ---------------------------------------------------------------------
  // COMPATIBILIDAD. El sistema neumórfico se retiró; estos alias mapean a la
  // escala de superficies para que el código existente siga compilando
  // mientras se migra. No usar en código nuevo.
  // ---------------------------------------------------------------------
  static const neoBase = surface;
  static const neoLight = surfaceTop;
  static const neoDark = surfaceSunken;
  static const neoSunken = surfaceSunken;
  static const neoText = textPrimary;
  static const neoTextSub = textSecondary;

  /// Canto de luz del borde SUPERIOR de una card. Un objeto iluminado desde
  /// arriba tiene el canto de arriba más claro que los costados; es lo que le
  /// da espesor a la pieza. Sutil a propósito: se siente, no se mira.
  static const cardBevel = Color(0x12FFF6EC);
}

/// Escala de espaciado. Base 4. Todo margen, padding y gap sale de acá —
/// los valores intermedios (3, 5, 7, 22…) son lo que hace que la interfaz se
/// vea "casi alineada".
abstract final class CceSpace {
  /// 4 · separación entre un ícono y su label.
  static const double xs = 4;

  /// 8 · gap dentro de un componente.
  static const double sm = 8;

  /// 12 · padding interno compacto.
  static const double md = 12;

  /// 16 · padding estándar de card, margen lateral de pantalla.
  static const double lg = 16;

  /// 24 · separación entre grupos de contenido.
  static const double xl = 24;

  /// 32 · separación entre secciones de una pantalla.
  static const double xxl = 32;

  /// 48 · respiro mayor (encabezado de pantalla, estados vacíos).
  static const double xxxl = 48;
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

  /// Foreground para superficies tintadas: si la base es clara, tinta
  /// cálida oscura; si no, el texto primario.
  static Color textOn(Color base) => base.computeLuminance() > 0.45
      ? const Color(0xFF181410)
      : CceColors.textPrimary;

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
  static const Color inkOnPastel = Color(0xFF181410);
  static const Color inkOnPastelSub = Color(0x99181410);
}

/// Sombras del sistema.
///
/// UNA sola estrategia: la profundidad la dan los escalones de superficie y
/// los hairlines. Las sombras existen únicamente para lo que de verdad flota
/// sobre el contenido, y son AMBIENTALES (caen hacia abajo, sin dirección de
/// luz inventada) porque una luz direccional simulada es lo que hacía que la
/// interfaz se leyera como plástico.
abstract final class CceShadows {
  /// Elemento apoyado sobre el lienzo (card, tile, chip).
  ///
  /// Dos capas: una sombra de CONTACTO corta y marcada (asienta la pieza sobre
  /// el fondo) y una difusa larga (la despega). Es la materialidad que hace que
  /// una card se sienta como un objeto y no como un rectángulo pintado — la
  /// diferencia con el neumorfismo viejo es que la luz viene de arriba y nada
  /// más, sin el par direccional que convertía todo en plástico.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x38000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// Elemento que flota de verdad (sheet, diálogo, menú).
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x59000000), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// Halo de una luz ENCENDIDA. Es el único "glow" que sobrevive porque no es
  /// decoración: una lámpara prendida emite luz, y ese es el estado que la app
  /// existe para comunicar. Muy contenido — insinúa, no ilumina.
  static List<BoxShadow> glowOn(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.16),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -6,
        ),
      ];

  /// Halo de dots de dispositivo en el plano (mismo criterio que [glowOn],
  /// escalado a un punto).
  static List<BoxShadow> glowDot(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.30),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ];

  // ---------------------------------------------------------------------
  // COMPATIBILIDAD con el sistema neumórfico retirado. Todo mapea a la
  // estrategia única. No usar en código nuevo.
  // ---------------------------------------------------------------------

  /// Antes: relieve extruido con par de sombras direccionales.
  static List<BoxShadow> neo({
    double blur = 14,
    double offset = 6,
    double intensity = 1,
  }) =>
      [
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, (0.25 * intensity).clamp(0, 1)),
          blurRadius: blur,
          offset: const Offset(0, 2),
        ),
      ];

  /// Antes: inner-shadow neumórfica. Un hueco ahora se expresa con
  /// [CceColors.surfaceSunken] + hairline, no con sombra interna.
  static List<BoxShadow> neoInset({
    double blur = 8,
    double offset = 3,
    double intensity = 1,
  }) =>
      const [];

  /// Antes: "plato" cóncavo (relieve externo + cara hundida).
  static List<BoxShadow> plato({double blur = 15, double offset = 6}) => raised;

  /// Antes: almohada flotante.
  static List<BoxShadow> cardFloat({double intensity = 1}) => [
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, (0.28 * intensity).clamp(0, 1)),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

/// Radios. Cuatro pasos: cuanto más grande la superficie, más suave el canto.
abstract final class CceRadii {
  /// 10 · chips, switches, badges.
  static const double sm = 10;

  /// 16 · tiles, controles, botones.
  static const double control = 16;

  /// 22 · cards.
  static const double card = 22;

  /// 28 · sheets y diálogos.
  static const double sheet = 28;

  static const double pill = 999;

  // Alias de compatibilidad.
  static const double tile = control;
  static const double hueCard = card;
  static const double hueScene = control;
}

/// Tipografía.
///
/// Seis pasos, sin medios puntos. Los títulos llevan tracking negativo (a
/// tamaño grande, el espaciado por defecto se ve suelto); las etiquetas de
/// sección llevan tracking positivo porque van en mayúsculas.
///
/// Los DATOS ([data], [dataLarge]) usan cifras tabulares: una temperatura que
/// cambia de 23.7 a 24.0 no debe mover el layout.
abstract final class CceText {
  /// Sin relieve. El texto se lee por contraste y peso, no por sombra.
  static const List<Shadow> embossShadows = <Shadow>[];

  /// Alias histórico del color de título.
  static const Color titleInk = CceColors.textPrimary;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// 32 · número o título protagonista de una pantalla.
  static const display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.1,
    color: CceColors.textPrimary,
  );

  /// 20 · título de pantalla y de card grande.
  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.2,
    color: CceColors.textPrimary,
  );

  /// 17 · nombre de dispositivo o habitación en una lista.
  static const headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
    color: CceColors.textPrimary,
  );

  /// 15 · texto corrido.
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: CceColors.textPrimary,
  );

  /// 13 · estado, metadato, subtítulo bajo un nombre.
  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: CceColors.textSecondary,
  );

  /// 13 · etiqueta de control (peso medio para aguantar el tamaño chico).
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: CceColors.textSecondary,
  );

  /// 11 · encabezado de sección. Usar con .toUpperCase().
  static const section = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    height: 1.2,
    color: CceColors.textTertiary,
  );

  /// Dato grande (temperatura, porcentaje) — cifras tabulares.
  static const dataLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    height: 1.0,
    color: CceColors.textPrimary,
    fontFeatures: _tabular,
  );

  /// Dato en línea (volumen, batería, hora) — cifras tabulares.
  static const data = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: CceColors.textPrimary,
    fontFeatures: _tabular,
  );
}

/// Gradientes.
///
/// Se conservan SÓLO los que codifican información (el color y el brillo real
/// de una luz). Los gradientes que simulaban relieve — cóncavo, convexo,
/// superficie de card — se retiraron: ahora son superficies planas de la
/// escala de elevación.
abstract final class CceGradients {
  /// Superficie de una card: canto de luz arriba + cuerpo + base en sombra.
  ///
  /// Tres paradas, no dos. La primera es un canto FINO y claro (los primeros
  /// 6% de la altura) que hace de bisel; el resto es una caída suave hacia la
  /// base. Ese canto es lo que le da espesor a la pieza — con un degradado
  /// lineal de dos paradas la card se ve teñida, no con volumen.
  ///
  /// Todo el rango es de ~5 puntos de lightness: se siente, no se mira.
  static LinearGradient cardSurface(Color base) {
    final hsl = HSLColor.fromColor(base);
    Color at(double d) =>
        hsl.withLightness((hsl.lightness + d).clamp(0.0, 1.0).toDouble()).toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [at(0.045), at(0.012), at(-0.022)],
      stops: const [0.0, 0.06, 1.0],
    );
  }

  /// COMPAT: antes cara cóncava (hundida). Ahora usa la misma superficie.
  static LinearGradient concave(Color base) => cardSurface(base);

  /// COMPAT: antes cara convexa. Ahora usa la misma superficie.
  static LinearGradient convex(Color base) => cardSurface(base);

  /// Gradiente de MARCA de Philips Hue: los MISMOS stops del logo. Vive sólo
  /// en el detalle de un dispositivo Hue — nunca en listas ni en la home.
  static const LinearGradient hueBrand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF00B1F3),
      Color(0xFF40D6AC),
      Color(0xFF9FD045),
      Color(0xFFFFC500),
      Color(0xFFFFA200),
      Color(0xFFFE3503),
    ],
    stops: [0.0, 0.274, 0.391, 0.611, 0.749, 1.0],
  );

  /// centerLeft→centerRight. Cada color pasa por CceTint.pastel.
  /// [] → [warm]; 1 color → duplicado; máx 5.
  static LinearGradient huePastel(List<Color> colors) {
    final src = (colors.isEmpty ? const <Color>[CceColors.warm] : colors).take(5).toList();
    if (src.length == 1) {
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

  /// Fill de una luz encendida: el color real de la lámpara, con el brillo
  /// modulando lightness y saturación. Esto NO es decoración — es el estado
  /// del dispositivo, y por eso es el único lugar donde el color manda.
  static LinearGradient lightFull(Color color, double brightness, bool reachable) {
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

  // LEGACY: sin callers.
  static LinearGradient roomOn([Color? tint]) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CceColors.accent, CceColors.accentDeep],
      );

  // LEGACY: sin callers.
  static const LinearGradient roomOff = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [CceColors.surface, CceColors.surface],
  );

  /// LEGACY: fill proporcional al brillo. Reemplazado por [lightFull].
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
