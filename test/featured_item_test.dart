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
      expect(
        FeaturedItem.decode('button:dev_dial'),
        const FeaturedItem(FeaturedKind.button, 'dev_dial'),
      );
      expect(
        FeaturedItem.decode('lock:dev_matheu'),
        const FeaturedItem(FeaturedKind.lock, 'dev_matheu'),
      );
      expect(
        FeaturedItem.decode('sensor:dev_motion'),
        const FeaturedItem(FeaturedKind.sensor, 'dev_motion'),
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

    test('un Samsung por device canónico (CCE#130)', () {
      const item = FeaturedItem(FeaturedKind.tv, 'dev_tv-ce588d39');
      expect(item.encode(), 'tv:dev_tv-ce588d39');
      expect(FeaturedItem.decode('tv:dev_tv-ce588d39'), item);
      expect(FeaturedItem.decode('tv:dev_tv'),
          const FeaturedItem(FeaturedKind.tv, 'dev_tv'));
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

  // La card "TV" única pasa a una card por Samsung (EugeValeiras/CCE#130).
  // Esto toca SharedPreferences: quien ya tenía la card destacada tiene que
  // seguir teniendo una card de TV después de actualizar. Si la migración se
  // equivoca, el usuario pierde su home.
  group('FeaturedItem.expandLegacyTv', () {
    const televisor = 'dev_tv';
    const monitor = 'dev_tv-ce588d39';

    test('el `tv` viejo se abre en un ítem por aparato, EN SU LUGAR', () {
      final migrated = FeaturedItem.expandLegacyTv(
        const [
          FeaturedItem(FeaturedKind.jbl),
          FeaturedItem(FeaturedKind.tv),
          FeaturedItem(FeaturedKind.vacuum, 'dev_robot'),
        ],
        const [televisor, monitor],
      );
      expect(migrated, const [
        FeaturedItem(FeaturedKind.jbl),
        FeaturedItem(FeaturedKind.tv, televisor),
        FeaturedItem(FeaturedKind.tv, monitor),
        FeaturedItem(FeaturedKind.vacuum, 'dev_robot'),
      ], reason: 'el resto de los destacados no se mueve de lugar');
    });

    test('sin la lista de aparatos NO se toca nada', () {
      const items = [FeaturedItem(FeaturedKind.tv)];
      final migrated = FeaturedItem.expandLegacyTv(items, const []);
      expect(identical(migrated, items), isTrue,
          reason: 'contra un backend sin GET /tv/tvs, o antes de que la lista '
              'llegue, migrar dejaría al usuario sin su card de TV');
    });

    test('destacados ya migrados no se vuelven a tocar', () {
      const items = [
        FeaturedItem(FeaturedKind.tv, televisor),
        FeaturedItem(FeaturedKind.jbl),
      ];
      expect(
        identical(FeaturedItem.expandLegacyTv(items, const [televisor, monitor]),
            items),
        isTrue,
        reason: 'y en particular NO se agrega el monitor a la home de alguien '
            'que ya eligió qué destacar',
      );
    });

    test('sin ningún destacado de TV tampoco', () {
      const items = [FeaturedItem(FeaturedKind.jbl)];
      expect(
        identical(FeaturedItem.expandLegacyTv(items, const [televisor]), items),
        isTrue,
      );
    });

    test('un aparato ya destacado no queda duplicado', () {
      final migrated = FeaturedItem.expandLegacyTv(
        const [
          FeaturedItem(FeaturedKind.tv, monitor),
          FeaturedItem(FeaturedKind.tv),
        ],
        const [televisor, monitor],
      );
      expect(migrated, const [
        FeaturedItem(FeaturedKind.tv, monitor),
        FeaturedItem(FeaturedKind.tv, televisor),
      ], reason: 'dos ítems iguales rompen las keys del reorder del editor');
    });

    test('con un solo Samsung queda una sola card, como estaba', () {
      final migrated = FeaturedItem.expandLegacyTv(
          const [FeaturedItem(FeaturedKind.tv)], const [televisor]);
      expect(migrated, const [FeaturedItem(FeaturedKind.tv, televisor)]);
    });

    test('lo migrado sobrevive el round-trip por prefs', () {
      final migrated = FeaturedItem.expandLegacyTv(
          const [FeaturedItem(FeaturedKind.tv)], const [televisor, monitor]);
      expect(
        FeaturedItem.decodeList(FeaturedItem.encodeList(migrated)),
        migrated,
        reason: 'es lo que se guarda y se vuelve a leer en el próximo arranque',
      );
    });
  });
}
