import 'dart:ui' show Color;

/// Recolorea los SVG claros del editor del Dashboard (fondo #fafafa, grid
/// #e0e0e0, paredes oscuras) a la paleta dark de la app, sin tocar el
/// layout: reglas exactas para la plantilla conocida + regla genérica por
/// luminancia sobre cualquier `fill=`/`stroke=` hexa. Cache por hash del
/// string (los planos no cambian dentro de una sesión).
abstract final class PlanSvgTheme {
  static final Map<int, String> _cache = <int, String>{};

  static String darken(String svg) {
    final key = svg.hashCode;
    final cached = _cache[key];
    if (cached != null) return cached;

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

    _cache[key] = out;
    return out;
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
