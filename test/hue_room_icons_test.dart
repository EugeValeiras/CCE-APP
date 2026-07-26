import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/theme/cce_icons.dart';

void main() {
  group('CceIcons.hueRoomIcon', () {
    test('cada archetype real del bridge resuelve a un ícono propio', () {
      // Los 7 archetypes que hoy devuelve GET /hue/rooms.
      const enUso = [
        'living_room',
        'bedroom',
        'guest_room',
        'hallway',
        'office',
        'front_door',
        'home',
      ];
      for (final a in enUso) {
        expect(CceIcons.hueRoomIcon(a), isNotEmpty, reason: a);
      }
      // Y no colapsan todos al mismo glyph genérico.
      final distintos = enUso.map(CceIcons.hueRoomIcon).toSet();
      expect(distintos.length, greaterThanOrEqualTo(6));
    });

    test('archetype desconocido, vacío o nulo cae en el sofá genérico', () {
      expect(CceIcons.hueRoomIcon(null), CceIcons.room);
      expect(CceIcons.hueRoomIcon(''), CceIcons.room);
      expect(CceIcons.hueRoomIcon('other'), CceIcons.room);
      expect(CceIcons.hueRoomIcon('archetype_que_hue_invente_mañana'),
          CceIcons.room);
    });

    test('los archetypes que comparten glyph a propósito lo comparten', () {
      expect(CceIcons.hueRoomIcon('garage'), CceIcons.hueRoomIcon('carport'));
      expect(CceIcons.hueRoomIcon('garage'), CceIcons.hueRoomIcon('driveway'));
      expect(CceIcons.hueRoomIcon('nursery'),
          CceIcons.hueRoomIcon('kids_bedroom'));
    });

    // Guard del bug de iOS/Impeller: un SVG cuyo viewBox no coincide con su
    // width/height se renderiza a pantalla completa (fue el "candado gigante").
    test('todo ícono de room tiene viewBox 0 0 24 24 y width/height 24', () {
      const archetypes = [
        'living_room', 'lounge', 'man_cave', 'bedroom', 'guest_room',
        'kids_bedroom', 'nursery', 'kitchen', 'dining', 'bathroom', 'toilet',
        'office', 'computer', 'studio', 'music', 'tv', 'reading', 'recreation',
        'gym', 'hallway', 'staircase', 'front_door', 'porch', 'garage',
        'carport', 'driveway', 'garden', 'terrace', 'balcony', 'pool',
        'barbecue', 'laundry_room', 'closet', 'storage', 'attic', 'top_floor',
        'upstairs', 'downstairs', 'home', 'other',
      ];
      for (final a in archetypes) {
        final svg = CceIcons.hueRoomIcon(a);
        expect(svg, contains('viewBox="0 0 24 24"'), reason: a);
        expect(svg, contains('width="24"'), reason: a);
        expect(svg, contains('height="24"'), reason: a);
      }
    });
  });
}
