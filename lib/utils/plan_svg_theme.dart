import 'dart:ui' show Color;

/// Recolorea los SVG claros del editor del Dashboard (fondo #fafafa, grid
/// #e0e0e0, paredes oscuras) a la paleta dark de la app, sin tocar el layout.
///
/// Hay DOS formatos de plano dando vueltas y los dos tienen que verse bien:
///
///  * **Semántico** (`data-plan-format` en la raíz). El exportador declara el
///    ROL de cada nodo — `data-wall`, `data-room`, `data-furniture`,
///    `data-opening`, … — así que el theming decide por rol y no tiene que
///    adivinar nada. Es el único camino que funciona con el exportador actual,
///    que emite los muros como `fill` de un `<path>`: la heurística vieja sólo
///    aclaraba `stroke`, con lo que las paredes de cualquier plano recién
///    guardado quedaban casi invisibles sobre el fondo dark.
///
///  * **Viejo** (sin ese atributo). Los planos ya guardados en `cce-config.json`
///    tienen los muros como `<line stroke="#444444">`. Para ésos se conserva
///    EXACTAMENTE la heurística por luminancia de siempre, byte por byte: no
///    hay ninguna razón para arriesgar una regresión sobre lo que hoy se ve
///    bien.
///
/// Además, sobre los dos formatos se normaliza lo que `flutter_svg` no sabe
/// parsear: `dominant-baseline` (los rótulos quedaban corridos media línea) y
/// el `<svg>` anidado de los glifos de mueble (descarta `x`/`y` y
/// `preserveAspectRatio`, y el mueble se dibujaba en el origen del plano).
///
/// Cache por hash del string (los planos no cambian dentro de una sesión).
abstract final class PlanSvgTheme {
  static final Map<int, String> _cache = <int, String>{};

  // ── Paleta dark. Tiene que seguir a `CceColors`; se repite acá para que el
  //    theming sea texto→texto puro y testeable sin material. ──
  static const String _wall = '#9BA3B5'; // CceColors.planWall
  static const String _wallOpacity = '0.92';
  static const String _text = '#C6CCD8';
  static const String _light = '#ffffff';

  /// Marca del contrato semántico. La emite el exportador del Dashboard
  /// (`PLAN_SVG_FORMAT`); si sube de versión, este archivo se revisa.
  static const String _formatMarker = 'data-plan-format=';

  static String darken(String svg) {
    final key = svg.hashCode;
    final cached = _cache[key];
    if (cached != null) return cached;

    var out = svg.contains(_formatMarker) ? _themeSemantic(svg) : _themeLegacy(svg);
    // Normalizaciones de parser: valen para los dos formatos. Sobre el
    // exportador nuevo son no-ops (ya no emite ninguna de las dos cosas).
    out = _inlineTextBaseline(out);
    out = _flattenNestedSvg(out);

    _cache[key] = out;
    return out;
  }

  // ───────────────────────── formato semántico ─────────────────────────

  /// Rol de un nodo, deducido de su hook `data-*`. Los hijos de un `<g>` con
  /// rol lo heredan (un mueble es un grupo con paths adentro).
  static _Role _roleOf(String tag) {
    if (tag.contains('data-wall-stroke') ||
        tag.contains('data-wall-plate') ||
        tag.contains('data-wall=')) {
      return _Role.wall;
    }
    if (tag.contains('data-wall-tick')) return _Role.accent;
    if (tag.contains('data-room-label') ||
        tag.contains('data-label=') ||
        tag.contains('data-furniture-label')) {
      return _Role.text;
    }
    if (tag.contains('data-room=')) return _Role.room;
    if (tag.contains('data-opening')) return _Role.opening;
    if (tag.contains('data-furniture')) return _Role.furniture;
    if (tag.contains('data-plan-bg')) return _Role.background;
    if (tag.contains('data-plan-grid')) return _Role.grid;
    return _Role.none;
  }

  /// Recorre los tags llevando una pila de roles: al entrar a un `<g>` con rol
  /// lo apila, al `</g>` lo desapila. Cada tag se recolorea con el rol propio
  /// o, si no tiene, con el que hereda.
  static String _themeSemantic(String svg) {
    final out = StringBuffer();
    final stack = <_Role>[];
    var i = 0;

    while (i < svg.length) {
      final start = svg.indexOf('<', i);
      if (start < 0) {
        out.write(svg.substring(i));
        break;
      }
      out.write(svg.substring(i, start));
      final end = svg.indexOf('>', start);
      if (end < 0) {
        out.write(svg.substring(start));
        break;
      }

      final tag = svg.substring(start, end + 1);
      final isClose = tag.startsWith('</');
      final isGroup = tag.startsWith('<g') || tag.startsWith('</g');
      final selfClosing = tag.endsWith('/>');

      if (isClose) {
        if (isGroup && stack.isNotEmpty) stack.removeLast();
        out.write(tag);
      } else {
        var role = _roleOf(tag);
        if (role == _Role.none && stack.isNotEmpty) role = stack.last;
        if (isGroup && !selfClosing) stack.add(role);
        out.write(_recolor(tag, role));
      }
      i = end + 1;
    }

    // El grid vive dentro de `<pattern>` en `<defs>`, fuera del alcance de los
    // hooks: su color lo emite el exportador fijo, así que se reemplaza literal.
    return out
        .toString()
        .replaceAll('stroke="#e0e0e0"', 'stroke="$_light" stroke-opacity="0.045"');
  }

  /// Reescribe `fill`/`stroke` de un tag según su rol. Dentro del rol, la
  /// luminancia sigue sirviendo para distinguir "esto era claro" (un relleno
  /// de papel) de "esto era oscuro" (una línea): el rol dice QUÉ es, la
  /// luminancia sólo cómo tratarlo.
  static String _recolor(String tag, _Role role) {
    if (role == _Role.none || role == _Role.grid || role == _Role.accent) return tag;

    return tag.replaceAllMapped(_colorAttr, (m) {
      final attr = m.group(1)!;
      final value = m.group(2)!;
      if (value == 'none' || value.startsWith('url(')) return m.group(0)!;

      final lum = _luminanceOf(value);
      final alpha = _alphaOf(value);

      switch (role) {
        case _Role.background:
          return '$attr="none"';

        case _Role.wall:
          // El corazón del arreglo: la pared se aclara valga como `fill`
          // (exportador nuevo) o como `stroke` (planos viejos).
          return attr == 'fill'
              ? 'fill="$_wall" fill-opacity="$_wallOpacity"'
              : 'stroke="$_wall" stroke-opacity="0.9" stroke-linecap="round"';

        case _Role.room:
          return attr == 'fill'
              ? 'fill="$_light" fill-opacity="0.03"'
              : 'stroke="$_light" stroke-opacity="0.10"';

        case _Role.opening:
          // El rect que tapaba el hueco en las puertas legacy usa el color de
          // fondo del papel: sobre dark tiene que desaparecer, no pintar.
          if (attr == 'fill') {
            return lum > 0.7 ? 'fill="none"' : 'fill="$_wall" fill-opacity="0.9"';
          }
          // El arco de barrido va en negro translúcido: se invierte
          // conservando su alpha.
          return alpha < 1
              ? 'stroke="$_light" stroke-opacity="${alpha.toStringAsFixed(2)}"'
              : 'stroke="$_wall" stroke-opacity="0.9"';

        case _Role.furniture:
          if (attr == 'fill') {
            return lum > 0.7
                ? 'fill="$_light" fill-opacity="0.05"'
                : 'fill="$_wall" fill-opacity="0.28"';
          }
          return 'stroke="$_wall" stroke-opacity="0.85"';

        case _Role.text:
          return attr == 'fill' ? 'fill="$_text"' : 'stroke="none"';

        case _Role.none:
        case _Role.grid:
        case _Role.accent:
          return m.group(0)!;
      }
    });
  }

  // ───────────────────────── formato viejo ─────────────────────────

  /// La heurística de siempre, intacta. Cualquier cambio acá es una regresión
  /// sobre los planos que hoy se ven bien.
  static String _themeLegacy(String svg) {
    var out = svg
        // Fondo claro de la plantilla → transparente (el canvas dark lo pone
        // Flutter por detrás).
        .replaceAll('fill="#fafafa"', 'fill="none"')
        .replaceAll("fill='#fafafa'", "fill='none'")
        // Grid del editor → blanco ~4.5%.
        .replaceAll(
            'stroke="#e0e0e0"', 'stroke="#ffffff" stroke-opacity="0.045"')
        .replaceAll(
            "stroke='#e0e0e0'", "stroke='#ffffff' stroke-opacity='0.045'");

    // Regla genérica por luminancia: fills claros casi desaparecen, strokes
    // oscuros (paredes) pasan a planWall #9BA3B5.
    final hexAttr = RegExp(
        "(fill|stroke)=([\"'])#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\2");
    out = out.replaceAllMapped(hexAttr, (m) {
      final attr = m.group(1)!;
      final q = m.group(2)!;
      final lum = _luminance(_expand(m.group(3)!));
      if (attr == 'fill' && lum > 0.7) {
        return 'fill=$q#ffffff$q fill-opacity=${q}0.03$q';
      }
      if (attr == 'stroke' && lum < 0.3) {
        return 'stroke=$q#9BA3B5$q stroke-opacity=${q}0.9$q '
            'stroke-linecap=${q}round$q';
      }
      return m.group(0)!;
    });

    return out;
  }

  // ─────────────────── normalizaciones para flutter_svg ───────────────────

  /// `dominant-baseline="middle"` → `dy` numérico. El parser de la app ignora
  /// la propiedad, así que sin esto los rótulos de los planos viejos quedan
  /// corridos media línea respecto del editor y del visor web.
  static String _inlineTextBaseline(String svg) {
    if (!svg.contains('dominant-baseline')) return svg;
    return svg.replaceAllMapped(RegExp(r'<text[^>]*>'), (m) {
      final tag = m.group(0)!;
      if (!tag.contains('dominant-baseline')) return tag;
      var out = tag.replaceAll(
          RegExp('''\\s*dominant-baseline\\s*=\\s*(["'])[^"']*\\1'''), '');
      if (RegExp(r'\sdy\s*=').hasMatch(out)) return out;
      final fs = RegExp('''font-size\\s*=\\s*(["'])([\\d.]+)''').firstMatch(out);
      final size = double.tryParse(fs?.group(2) ?? '') ?? 14;
      final dy = (size * 0.35).toStringAsFixed(2);
      return out.replaceFirst('<text', '<text dy="$dy"');
    });
  }

  /// `<svg x y width height viewBox preserveAspectRatio>` anidado (los glifos
  /// de mueble de los planos viejos) → `<g transform="translate scale">`, que
  /// es lo mismo pero expresado como algo que `flutter_svg` sí aplica. Sin
  /// esto el mueble se dibuja pegado al origen del plano.
  static String _flattenNestedSvg(String svg) {
    // El primer `<svg` es la raíz; se busca a partir de ahí.
    var out = svg;
    var from = out.indexOf('<svg') + 1;
    while (true) {
      final start = out.indexOf('<svg', from);
      if (start < 0) break;
      final end = out.indexOf('>', start);
      if (end < 0) break;
      final tag = out.substring(start, end + 1);

      final x = _numAttr(tag, 'x') ?? 0;
      final y = _numAttr(tag, 'y') ?? 0;
      final w = _numAttr(tag, 'width');
      final h = _numAttr(tag, 'height');
      final vb = RegExp('''viewBox\\s*=\\s*(["'])([^"']*)\\1''').firstMatch(tag);

      if (w == null || h == null || vb == null) {
        from = end + 1;
        continue;
      }
      final parts = vb
          .group(2)!
          .trim()
          .split(RegExp(r'[\s,]+'))
          .map((s) => double.tryParse(s) ?? 0)
          .toList();
      if (parts.length < 4 || parts[2] <= 0 || parts[3] <= 0) {
        from = end + 1;
        continue;
      }
      final k = (w / parts[2]) < (h / parts[3]) ? w / parts[2] : h / parts[3];
      // Mismo encuadre que `xMidYMid meet`: el centro del viewBox cae en el
      // centro de la caja destino.
      final tx = x + w / 2 - (parts[0] + parts[2] / 2) * k;
      final ty = y + h / 2 - (parts[1] + parts[3] / 2) * k;
      final open = '<g transform="translate('
          '${_fmt(tx)},${_fmt(ty)}) scale(${_fmt(k)})">';

      // El `<svg>` anidado que emitía el editor nunca anida otro adentro.
      final close = out.indexOf('</svg>', end);
      if (close < 0) break;
      out = out.replaceRange(close, close + '</svg>'.length, '</g>');
      out = out.replaceRange(start, end + 1, open);
      from = start + open.length;
    }
    return out;
  }

  // ───────────────────────── helpers ─────────────────────────

  /// `fill="…"` / `stroke="…"` con cualquier valor entre comillas dobles (el
  /// exportador nunca usa simples).
  static final RegExp _colorAttr = RegExp(r'(fill|stroke)="([^"]*)"');

  static double? _numAttr(String tag, String name) {
    final m = RegExp('''\\s$name\\s*=\\s*(["'])([-\\d.]+)''').firstMatch(tag);
    return m == null ? null : double.tryParse(m.group(2)!);
  }

  static String _fmt(double v) {
    final r = (v * 1000).round() / 1000;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  /// Luminancia de un color CSS (`#rgb`, `#rrggbb`, `rgba(...)`). Los valores
  /// que no se reconocen se tratan como oscuros, que es el caso por defecto
  /// del editor.
  static double _luminanceOf(String value) {
    final v = value.trim();
    if (v.startsWith('#')) return _luminance(_expand(v.substring(1)));
    final rgb = RegExp(r'rgba?\(([^)]*)\)').firstMatch(v);
    if (rgb != null) {
      final n = rgb
          .group(1)!
          .split(',')
          .map((s) => double.tryParse(s.trim()) ?? 0)
          .toList();
      if (n.length >= 3) {
        final c = Color.fromARGB(
            255, n[0].round().clamp(0, 255), n[1].round().clamp(0, 255),
            n[2].round().clamp(0, 255));
        return c.computeLuminance();
      }
    }
    return 0;
  }

  /// Alpha de un `rgba(...)`; 1 para todo lo demás.
  static double _alphaOf(String value) {
    final rgb = RegExp(r'rgba\(([^)]*)\)').firstMatch(value.trim());
    if (rgb == null) return 1;
    final n = rgb.group(1)!.split(',');
    if (n.length < 4) return 1;
    return (double.tryParse(n[3].trim()) ?? 1).clamp(0.0, 1.0);
  }

  static String _expand(String hex) {
    if (hex.length == 3) {
      final b = StringBuffer();
      for (final c in hex.split('')) {
        b.write(c);
        b.write(c);
      }
      return b.toString();
    }
    return hex;
  }

  static double _luminance(String hex6) {
    final value = int.tryParse(hex6, radix: 16) ?? 0;
    return Color(0xFF000000 | value).computeLuminance();
  }
}

/// Rol semántico de un nodo del plano.
enum _Role { none, background, grid, wall, room, opening, furniture, text, accent }
