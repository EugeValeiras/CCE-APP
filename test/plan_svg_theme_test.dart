import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/utils/plan_svg_theme.dart';

/// El theming del plano es lo último que pasa entre el editor del Dashboard y
/// la pantalla del celular, y es donde estaba armada la regresión: el
/// exportador pasó a emitir los muros como `fill` de un `<path>` mientras el
/// theming sólo aclaraba `stroke`, así que el primer plano que alguien
/// guardara iba a aparecer con las paredes casi invisibles sobre el fondo dark.
///
/// Los fixtures son los planos REALES de `cce-config.json`, en sus dos formas:
/// `legacySvg` (lo que hay guardado hoy) y `exportedSvg` (lo que va a quedar
/// guardado la próxima vez que se toque el plano). Se regeneran con
/// `npx tsx scripts/gen-app-plan-fixture.mts <repo-app>` desde CCE-Dashboard.
void main() {
  final plans = (jsonDecode(
    File('test/fixtures/real-plans-svg.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  String legacy(String name) =>
      plans.firstWhere((p) => p['name'] == name)['legacySvg'] as String;
  String exported(String name) =>
      plans.firstWhere((p) => p['name'] == name)['exportedSvg'] as String;

  /// Colores que quedan en un atributo dado, ya temados.
  List<String> colorsOf(String svg, String attr) => RegExp('$attr="([^"]*)"')
      .allMatches(svg)
      .map((m) => m.group(1)!)
      .toList();

  group('formato nuevo (semántico)', () {
    test('las paredes se aclaran aunque vengan como fill — la regresión', () {
      for (final plan in plans) {
        final name = plan['name'] as String;
        final src = plan['exportedSvg'] as String;
        final out = PlanSvgTheme.darken(src);

        // Punto de partida: el exportador nuevo pinta las paredes con fill.
        expect(src, contains('data-wall='), reason: '$name: el fixture tiene muros');
        expect(src, contains('fill="#444444"'),
            reason: '$name: los muros vienen como fill (el formato nuevo)');

        // Y después del theming NO queda ni un muro oscuro.
        expect(out, isNot(contains('fill="#444444"')),
            reason: '$name: quedó una pared oscura sin aclarar');
        expect(out, contains('fill="#9BA3B5"'),
            reason: '$name: las paredes tienen que terminar en planWall');
      }
    });

    test('cada muro exportado queda claro, uno por uno', () {
      final src = exported('Living');
      final out = PlanSvgTheme.darken(src);

      final wallTags =
          RegExp(r'<path[^>]*data-wall="[^"]*"[^>]*>').allMatches(out);
      expect(wallTags, isNotEmpty);
      for (final m in wallTags) {
        final tag = m.group(0)!;
        expect(tag, contains('#9BA3B5'),
            reason: 'muro sin aclarar: ${tag.substring(0, 90)}');
      }
    });

    test('el fondo de hoja desaparece y la grilla queda tenue', () {
      final out = PlanSvgTheme.darken(exported('Living'));
      final bg = RegExp(r'<rect[^>]*data-plan-bg[^>]*>').firstMatch(out)!.group(0)!;
      expect(bg, contains('fill="none"'));
      expect(out, contains('stroke="#ffffff" stroke-opacity="0.045"'),
          reason: 'la grilla del pattern se aclara');
      expect(out, isNot(contains('#fafafa')), reason: 'no queda papel blanco');
    });

    test('las salas quedan como un velo, no como una mancha blanca', () {
      final out = PlanSvgTheme.darken(exported('Living'));
      for (final m in RegExp(r'<path[^>]*data-room="[^"]*"[^>]*>').allMatches(out)) {
        expect(m.group(0)!, contains('fill-opacity="0.03"'));
      }
    });

    test('los rótulos se leen sobre el fondo dark', () {
      final out = PlanSvgTheme.darken(exported('Living'));
      final texts = RegExp(r'<text[^>]*>').allMatches(out);
      expect(texts, isNotEmpty, reason: 'el plano Living tiene rótulos');
      for (final m in texts) {
        expect(m.group(0)!, contains('fill="#C6CCD8"'));
      }
    });

    test('no toca la geometría: ni un path, ni el viewBox', () {
      for (final plan in plans) {
        final src = plan['exportedSvg'] as String;
        final out = PlanSvgTheme.darken(src);
        expect(colorsOf(out, 'd'), equals(colorsOf(src, 'd')),
            reason: '${plan['name']}: los path d tienen que ser idénticos');
        expect(RegExp(r'viewBox="([^"]*)"').firstMatch(out)!.group(1),
            equals(RegExp(r'viewBox="([^"]*)"').firstMatch(src)!.group(1)),
            reason: '${plan['name']}: el viewBox es identidad de dominio');
        // Ningún nodo se pierde ni se duplica.
        expect('<'.allMatches(out).length, equals('<'.allMatches(src).length),
            reason: '${plan['name']}: misma cantidad de nodos');
      }
    });
  });

  group('formato viejo: cero regresión', () {
    test('los planos ya guardados se ven igual que antes del cambio', () {
      for (final plan in plans) {
        final name = plan['name'] as String;
        final src = plan['legacySvg'] as String;
        final out = PlanSvgTheme.darken(src);

        expect(src, isNot(contains('data-plan-format')),
            reason: '$name: el fixture viejo no tiene el marcador de formato');
        // Exactamente el resultado de la heurística de siempre.
        expect(out, equals(_legacyReference(src)),
            reason: '$name: el formato viejo tiene que salir byte por byte '
                'igual que con el theming anterior');
      }
    });

    test('las paredes viejas (stroke #444444) siguen aclarándose', () {
      final out = PlanSvgTheme.darken(legacy('Living'));
      expect(out, isNot(contains('stroke="#444444"')));
      expect(out, contains('stroke="#9BA3B5"'));
    });
  });

  group('normalizaciones de parser', () {
    test('dominant-baseline se convierte en un dy numérico', () {
      const svg = '<svg viewBox="0 0 10 10">'
          '<text x="5" y="5" text-anchor="middle" dominant-baseline="middle" '
          'font-size="14" fill="#666">Cocina</text></svg>';
      final out = PlanSvgTheme.darken(svg);
      expect(out, isNot(contains('dominant-baseline')),
          reason: 'el parser de la app lo ignora y el rótulo queda corrido');
      expect(out, contains('dy="4.90"'), reason: 'dy = 0.35 · font-size');
      expect(out, contains('y="5"'), reason: 'el ancla no se mueve');
    });

    test('un dy ya presente no se pisa', () {
      const svg = '<svg viewBox="0 0 10 10">'
          '<text dy="2" dominant-baseline="middle" font-size="14">x</text></svg>';
      final out = PlanSvgTheme.darken(svg);
      expect(out, contains('dy="2"'));
      expect(RegExp(r'dy=').allMatches(out).length, 1);
    });

    test('el <svg> anidado de un glifo pasa a <g transform>', () {
      // Caja de 10.2×10.2 centrada en el origen sobre un viewBox 24×24:
      // k = 0.425, y el centro del viewBox cae en el centro de la caja.
      const svg = '<svg viewBox="0 0 800 600"><g transform="translate(100,50)">'
          '<svg x="-5.1" y="-5.1" width="10.2" height="10.2" '
          'viewBox="0 0 24 24" preserveAspectRatio="xMidYMid meet">'
          '<path d="M2 2h20v20H2z"/></svg></g></svg>';
      final out = PlanSvgTheme.darken(svg);

      expect(RegExp('<svg').allMatches(out).length, 1,
          reason: 'sólo queda el <svg> raíz');
      expect(out, contains('<g transform="translate(-5.1,-5.1) scale(0.425)">'),
          reason: 'el glifo se ubica y escala a mano, como haría el meet');
      expect(out, contains('<path d="M2 2h20v20H2z"'),
          reason: 'el dibujo del glifo se conserva');
      expect(RegExp(r'</g>').allMatches(out).length, 2,
          reason: 'el </svg> anidado se cerró como </g>');
    });

    test('un <svg> anidado sin dimensiones se deja como está', () {
      const svg = '<svg viewBox="0 0 10 10"><svg><path d="M0 0"/></svg></svg>';
      expect(() => PlanSvgTheme.darken(svg), returnsNormally);
    });
  });

  group('robustez', () {
    test('el cache devuelve el mismo resultado', () {
      final src = exported('Office');
      expect(PlanSvgTheme.darken(src), equals(PlanSvgTheme.darken(src)));
    });

    test('entradas degeneradas no explotan', () {
      for (final s in ['', '<svg', 'no es svg', '<svg data-plan-format="1">']) {
        expect(() => PlanSvgTheme.darken(s), returnsNormally, reason: s);
      }
    });

    test('un formato futuro sigue entrando por el camino semántico', () {
      const svg = '<svg data-plan-format="99">'
          '<path data-wall="w" d="M0 0" fill="#444444"/></svg>';
      expect(PlanSvgTheme.darken(svg), contains('#9BA3B5'));
    });
  });
}

/// Copia literal de la heurística por luminancia previa al contrato semántico.
/// Es el patrón de oro del formato viejo: si `PlanSvgTheme` se separa de esto
/// para un plano sin `data-plan-format`, es una regresión sobre lo guardado.
String _legacyReference(String svg) {
  var out = svg
      .replaceAll('fill="#fafafa"', 'fill="none"')
      .replaceAll("fill='#fafafa'", "fill='none'")
      .replaceAll('stroke="#e0e0e0"', 'stroke="#ffffff" stroke-opacity="0.045"')
      .replaceAll("stroke='#e0e0e0'", "stroke='#ffffff' stroke-opacity='0.045'");

  final hexAttr =
      RegExp("(fill|stroke)=([\"'])#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\2");
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

String _expand(String hex) {
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

double _luminance(String hex6) {
  final value = int.tryParse(hex6, radix: 16) ?? 0;
  return Color(0xFF000000 | value).computeLuminance();
}
