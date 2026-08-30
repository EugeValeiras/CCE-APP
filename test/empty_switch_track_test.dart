// CCE#59: la habitación sin luces muestra el riel del switch VACÍO.
//
// Lo que se prueba no son píxeles sino la promesa del cambio: que la fila sin
// luces tenga la MISMA silueta que las demás (ícono, nombre, badge y control en
// su lugar) y que lo único distinto sea la perilla ausente. De ahí que casi
// todos los expects comparen el riel vacío contra un CceSwitch real en vez de
// contra números escritos a mano: si mañana el switch cambia de medida o de
// color, estos tests siguen valiendo — y si el riel vacío NO cambia con él,
// fallan, que es exactamente el error que el issue quería hacer imposible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/theme/components/cce_switch.dart';
import 'package:cce_app/theme/components/room_card.dart';

/// El BoxDecoration efectivo del óvalo de un [CceSwitch] o de un
/// [CceSwitchEmptyTrack]: en los dos casos es el PRIMER contenedor del subárbol
/// (la perilla, cuando existe, viene después).
BoxDecoration trackDecoration(WidgetTester tester, Finder of) {
  final container = tester.widgetList(find.descendant(
    of: of,
    matching: find.byWidgetPredicate((w) =>
        (w is Container && w.decoration != null) ||
        (w is AnimatedContainer && w.decoration != null)),
  )).first;
  final decoration = container is Container
      ? container.decoration
      : (container as AnimatedContainer).decoration;
  return decoration! as BoxDecoration;
}

Future<void> pumpRoom(
  WidgetTester tester, {
  required int lightsTotal,
  double? temperature,
  bool anyOn = false,
  ValueChanged<bool>? onToggle,
  VoidCallback? onTap,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: RoomCard(
              title: 'Guest',
              icon: const Icon(Icons.light),
              lightsOn: anyOn ? 1 : 0,
              lightsTotal: lightsTotal,
              anyOn: anyOn,
              temperature: temperature,
              onTap: onTap ?? () {},
              onToggle: onToggle ?? (_) {},
            ),
          ),
        ),
      ),
    ));

void main() {
  group('CceSwitchEmptyTrack', () {
    testWidgets('es la pista del switch apagado, sin la perilla',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CceSwitch(value: false, onChanged: _noop),
                CceSwitchEmptyTrack(),
              ],
            ),
          ),
        ),
      ));

      // Mismo rectángulo y mismo material que la pista de al lado: el riel
      // vacío no se dibuja aparte, se toma prestado.
      expect(
        tester.getSize(find.byType(CceSwitchEmptyTrack)),
        tester.getSize(find.byType(CceSwitch)),
      );
      expect(
        trackDecoration(tester, find.byType(CceSwitchEmptyTrack)),
        trackDecoration(tester, find.byType(CceSwitch)),
      );

      // …y ni un círculo adentro: la perilla ausente ES el mensaje.
      expect(
        find.descendant(
          of: find.byType(CceSwitchEmptyTrack),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle),
        ),
        findsNothing,
      );
    });

    testWidgets('va a opacidad plena: no es un switch deshabilitado',
        (tester) async {
      // El deshabilitado (onChanged: null) baja al 40% y DEJA la perilla —
      // "existe pero está bloqueado". Acá el control no existe.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: CceSwitchEmptyTrack())),
      ));
      for (final o in tester.widgetList<Opacity>(find.descendant(
        of: find.byType(CceSwitchEmptyTrack),
        matching: find.byType(Opacity),
      ))) {
        expect(o.opacity, 1.0);
      }
    });

    testWidgets('es inerte: no se anuncia como control activable',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: CceSwitchEmptyTrack())),
      ));

      // Un óvalo vacío no dice nada solo: lo dice la etiqueta. Y nada más —
      // matchesSemantics exige que TODO lo que no se declara acá (los flags de
      // toggle y de botón, la acción de tap) esté en false: el riel no se
      // anuncia como un control.
      expect(
        tester.getSemantics(find.byType(CceSwitchEmptyTrack)),
        matchesSemantics(label: 'Sin luces'),
      );

      // Sin GestureDetector propio: no hay nada que tocar acá adentro.
      expect(
        find.descendant(
          of: find.byType(CceSwitchEmptyTrack),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('RoomCard sin luces (CCE#59)', () {
    testWidgets('conserva la silueta: badge en su columna y riel a la derecha',
        (tester) async {
      await pumpRoom(tester, lightsTotal: 3, temperature: 20.1);
      final conLuces = tester.getRect(find.text('20.1°'));

      // Guest: sin luces pero CON termómetro. El badge vuelve (los chips de
      // #57 se lo llevaban) y cae en la misma columna que Bedroom.
      await pumpRoom(tester, lightsTotal: 0, temperature: 20.1);
      expect(find.text('20.1°'), findsOneWidget);
      expect(tester.getRect(find.text('20.1°')), conLuces);
      expect(find.byType(CceSwitchEmptyTrack), findsOneWidget);
    });

    testWidgets('sin termómetro no hay badge, pero el riel sigue',
        (tester) async {
      // Cocina, Guest Bathroom, Reception: nada que medir, nada que togglear.
      await pumpRoom(tester, lightsTotal: 0);
      expect(find.textContaining('°'), findsNothing);
      expect(find.byType(CceSwitchEmptyTrack), findsOneWidget);
    });

    testWidgets('la card sigue midiendo 88: la lista no cambia de ritmo',
        (tester) async {
      double height() => tester.getSize(find.byType(RoomCard)).height;

      await pumpRoom(tester, lightsTotal: 0);
      expect(height(), 88);
      await pumpRoom(tester, lightsTotal: 0, temperature: 20.1);
      expect(height(), 88);
      await pumpRoom(tester, lightsTotal: 3, temperature: 20.1, anyOn: true);
      expect(height(), 88);
    });

    testWidgets('tocar el riel no togglea nada; la card sí entra al detalle',
        (tester) async {
      var toggles = 0;
      var taps = 0;
      await pumpRoom(
        tester,
        lightsTotal: 0,
        onToggle: (_) => toggles++,
        onTap: () => taps++,
      );

      await tester.tap(find.byType(CceSwitchEmptyTrack));
      await tester.pumpAndSettle();
      expect(toggles, 0);
      // El riel no traga el gesto: la fila entera sigue siendo tappable, que
      // es la única acción real de una habitación sin luces.
      expect(taps, 1);
    });
  });
}

void _noop(bool _) {}
