import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/featured_item.dart';

void main() {
  group('FeaturedItem encode/decode', () {
    test('singletons sin id (tv/jbl)', () {
      expect(const FeaturedItem(FeaturedKind.tv).encode(), 'tv');
      expect(FeaturedItem.decode('tv'), const FeaturedItem(FeaturedKind.tv));
      expect(FeaturedItem.decode('jbl'), const FeaturedItem(FeaturedKind.jbl));
    });

    test('con id (device/escena/automatización)', () {
      const item = FeaturedItem(FeaturedKind.light, 'dev_x');
      expect(item.encode(), 'light:dev_x');
      expect(FeaturedItem.decode('light:dev_x'), item);
      expect(
        FeaturedItem.decode('scene:sc_1'),
        const FeaturedItem(FeaturedKind.scene, 'sc_1'),
      );
      expect(
        FeaturedItem.decode('automation:auto-7'),
        const FeaturedItem(FeaturedKind.automation, 'auto-7'),
      );
    });

    test('id con dos puntos internos sobrevive el round-trip', () {
      const item = FeaturedItem(FeaturedKind.scene, 'a:b:c');
      expect(FeaturedItem.decode(item.encode()), item);
    });

    test('basura y kinds desconocidos → null (forward-compat)', () {
      expect(FeaturedItem.decode(''), isNull);
      expect(FeaturedItem.decode('widget:xyz'), isNull);
      expect(FeaturedItem.decode('light:'), isNull);
    });

    test('decodeList filtra las entradas inválidas sin romper', () {
      final items = FeaturedItem.decodeList(
          ['tv', 'basura:x', 'thermostat:dev_t', 'nope']);
      expect(items, hasLength(2));
      expect(items[0].kind, FeaturedKind.tv);
      expect(items[1].id, 'dev_t');
    });

    test('encodeList round-trip estable', () {
      final list = [
        const FeaturedItem(FeaturedKind.tv),
        const FeaturedItem(FeaturedKind.vacuum, 'dev_v'),
        const FeaturedItem(FeaturedKind.scene, 's1'),
      ];
      expect(
        FeaturedItem.decodeList(FeaturedItem.encodeList(list)),
        list,
      );
    });
  });
}
