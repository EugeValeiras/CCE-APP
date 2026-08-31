// CCE#63: la línea de estado de la RoomCard son BADGES, uno por hecho activo.
//
// Lo que se prueba es la promesa del cambio, no los píxeles: que lo que pasa en
// la habitación se LEA independientemente de cuántas cosas pasen (antes, con
// dos o más estados activos el texto se vaciaba y quedaban puntos mudos), que
// el ancho se reparta con una regla y no por accidente, y que nada de esto
// estire la card de 88px.
//
// OJO con los anchos: en `flutter test` la tipografía es la de prueba, donde
// cada carácter mide exactamente fontSize. "Movimiento" es ahí bastante más
// ancho que en un teléfono real, así que los tests que quieren ver las tres
// palabras montan la card en un ancho generoso, y la regla de reparto se
// prueba aparte, sin widgets, contra los anchos que la propia medición
// devuelve.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/theme/components/room_card.dart';
import 'package:cce_app/theme/components/status_badge.dart';

Future<void> pumpRoom(
  WidgetTester tester, {
  bool contactOpen = false,
  bool motion = false,
  bool anyOn = false,
  String title = 'Living',
  String? subtitleOverride,
  double? temperature,
  double? brightness,
  double width = 700,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RoomCard(
              title: title,
              icon: const Icon(Icons.light),
              lightsOn: anyOn ? 1 : 0,
              lightsTotal: 3,
              anyOn: anyOn,
              motion: motion,
              contactOpen: contactOpen,
              subtitleOverride: subtitleOverride,
              temperature: temperature,
              brightness: brightness,
              onTap: () {},
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    ));

/// Los badges dibujados, en orden de izquierda a derecha.
List<StatusBadgeData> badgesOf(WidgetTester tester) => tester
    .widgetList<StatusBadge>(find.byType(StatusBadge))
    .map((b) => b.data)
    .toList();

void main() {
  group('badges de estado en la RoomCard (CCE#63)', () {
    testWidgets('un solo estado activo: un badge con su palabra',
        (tester) async {
      await pumpRoom(tester, anyOn: true);
      expect(badgesOf(tester).map((b) => b.semanticLabel), ['Luz encendida']);
      expect(find.text('Luz'), findsOneWidget);
    });

    testWidgets('dos estados: los dos se leen (el caso que motivó el issue)',
        (tester) async {
      // Living/Office mostraban un punto naranja y uno azul, sin una palabra.
      await pumpRoom(tester, contactOpen: true, motion: true);
      expect(badgesOf(tester).map((b) => b.semanticLabel),
          ['Puerta abierta', 'Movimiento detectado']);
      expect(find.text('Abierta'), findsOneWidget);
      expect(find.text('Movimiento'), findsOneWidget);
    });

    testWidgets('tres estados: se ven los tres, en orden fijo', (tester) async {
      await pumpRoom(tester, contactOpen: true, motion: true, anyOn: true);
      expect(badgesOf(tester).map((b) => b.semanticLabel),
          ['Puerta abierta', 'Movimiento detectado', 'Luz encendida']);
      expect(find.text('Abierta'), findsOneWidget);
      expect(find.text('Movimiento'), findsOneWidget);
      expect(find.text('Luz'), findsOneWidget);

      // Y salen en ese orden en pantalla, no sólo en el árbol.
      final xs = tester
          .widgetList<StatusBadge>(find.byType(StatusBadge))
          .map((b) => tester.getRect(find.byWidget(b)).left)
          .toList();
      expect(xs, orderedEquals([...xs]..sort()));
    });

    testWidgets('cada estado lleva SU color, el mismo que tenía el dot',
        (tester) async {
      await pumpRoom(tester, contactOpen: true, motion: true, anyOn: true);
      expect(badgesOf(tester).map((b) => b.color),
          [CceColors.contact, CceColors.motion, CceColors.amberHi]);
    });

    testWidgets('el latido es de los sensores, no de la luz', (tester) async {
      // Contacto y movimiento están PASANDO; la luz encendida es un estado.
      await pumpRoom(tester, contactOpen: true, motion: true, anyOn: true);
      expect(badgesOf(tester).map((b) => b.live), [true, true, false]);
    });

    testWidgets('sin ningún estado: la fila queda como antes', (tester) async {
      await pumpRoom(tester);
      expect(find.byType(StatusBadge), findsNothing);
      // Sin nada que decir, el nombre se centra en la card.
      final card = tester.getRect(find.byType(RoomCard));
      expect(tester.getRect(find.text('Living')).center.dy,
          closeTo(card.center.dy, 1.0));

      // Con un estado, en cambio, el nombre sube para dejarle sitio.
      await pumpRoom(tester, motion: true);
      expect(tester.getRect(find.text('Living')).center.dy,
          lessThan(card.center.dy));
    });

    testWidgets('subtitleOverride: la frase manda y no hay badges',
        (tester) async {
      // La fila "Toda la casa" del sidebar de tablet: anyOn es true (hay luces
      // prendidas en la casa) pero lo que se muestra es su resumen.
      await pumpRoom(tester,
          anyOn: true, subtitleOverride: '12/31 · 2 con movimiento');
      expect(find.text('12/31 · 2 con movimiento'), findsOneWidget);
      expect(find.byType(StatusBadge), findsNothing);
    });

    testWidgets('la card mide 88 con badges y sin ellos', (tester) async {
      Future<double> height({
        bool contactOpen = false,
        bool motion = false,
        bool anyOn = false,
        double? brightness,
        double? temperature,
        double width = 700,
      }) async {
        await pumpRoom(tester,
            contactOpen: contactOpen,
            motion: motion,
            anyOn: anyOn,
            brightness: brightness,
            temperature: temperature,
            width: width);
        return tester.getSize(find.byType(RoomCard)).height;
      }

      expect(await height(), 88);
      expect(await height(anyOn: true), 88);
      expect(await height(contactOpen: true, motion: true), 88);
      expect(await height(contactOpen: true, motion: true, anyOn: true), 88);
      // El caso apretado: tres badges + slider + badge de temperatura, que es
      // cuando la fila de contenido baja a 44px. Si el badge fuera más alto,
      // acá reventaría con un overflow.
      expect(
        await height(
            contactOpen: true,
            motion: true,
            anyOn: true,
            brightness: 0.5,
            temperature: 22.5),
        88,
      );
      // Y en un teléfono angosto, donde además hay que repartir el ancho.
      expect(
        await height(
            contactOpen: true,
            motion: true,
            anyOn: true,
            brightness: 0.5,
            temperature: 22.5,
            width: 361),
        88,
      );
    });

    testWidgets('nombre largo: se trunca el nombre, los badges no desbordan',
        (tester) async {
      await pumpRoom(
        tester,
        title: 'Habitación de huéspedes del fondo a la derecha',
        contactOpen: true,
        motion: true,
        anyOn: true,
        temperature: 22.5,
        width: 361, // teléfono angosto
      );
      final card = tester.getRect(find.byType(RoomCard));
      final title = tester.getRect(find.text(
          'Habitación de huéspedes del fondo a la derecha'));
      final badges = tester.getRect(find.byType(StatusBadgeRow));

      // El nombre cede (se trunca) dentro de la card...
      expect(title.right, lessThanOrEqualTo(card.right));
      // ...y la fila de badges tampoco se sale.
      expect(badges.right, lessThanOrEqualTo(card.right));
      // Nombre y badges viven en líneas distintas: ninguno le come ancho al
      // otro, así que el nombre dispone de toda la columna.
      expect(badges.top, greaterThanOrEqualTo(title.bottom - 1));
      // Los tres estados siguen presentes aunque el ancho no alcance para las
      // tres palabras (ver la regla de reparto).
      expect(find.byType(StatusBadge), findsNWidgets(3));
    });
  });

  group('reparto del ancho (StatusBadgeRow.labelsThatFit)', () {
    const puerta = StatusBadgeData(
      glyph: '',
      label: 'Abierta',
      color: CceColors.contact,
      semanticLabel: 'Puerta abierta',
    );
    const movimiento = StatusBadgeData(
      glyph: '',
      label: 'Movimiento',
      color: CceColors.motion,
      semanticLabel: 'Movimiento detectado',
    );
    const luz = StatusBadgeData(
      glyph: '',
      label: 'Luz',
      color: CceColors.amberHi,
      semanticLabel: 'Luz encendida',
    );
    const todos = [puerta, movimiento, luz];

    /// Ancho de la fila con las palabras que dice [showLabel].
    double widthOf(List<bool> showLabel) {
      var total = StatusBadgeRow.gap * (todos.length - 1);
      for (var i = 0; i < todos.length; i++) {
        total += showLabel[i]
            ? StatusBadge.widthOf(todos[i].label)
            : StatusBadge.glyphOnlyWidth;
      }
      return total;
    }

    test('si entran las tres palabras, van las tres', () {
      expect(
        StatusBadgeRow.labelsThatFit(todos, widthOf([true, true, true])),
        [true, true, true],
      );
    });

    test('el último es el primero en quedarse sin palabra', () {
      // Un pelo menos de lo que necesitan las tres.
      expect(
        StatusBadgeRow.labelsThatFit(todos, widthOf([true, true, true]) - 1),
        [true, true, false],
      );
    });

    test('después cede el del medio, y al final el primero', () {
      expect(
        StatusBadgeRow.labelsThatFit(todos, widthOf([true, true, false]) - 1),
        [true, false, false],
      );
      // Con el ancho del sidebar de tablet no entra ni la primera palabra: se
      // van los tres a glifo. Media palabra ("Abie…") no se lee, y leerse es
      // todo el punto del cambio; el dibujo de la puerta abierta sí se lee.
      expect(
        StatusBadgeRow.labelsThatFit(todos, widthOf([true, false, false]) - 1),
        [false, false, false],
      );
      expect(StatusBadgeRow.labelsThatFit(todos, 10), [false, false, false]);
    });

    test('un badge solo conserva su palabra mientras entre', () {
      expect(StatusBadgeRow.labelsThatFit([luz], StatusBadge.widthOf('Luz')),
          [true]);
      expect(StatusBadgeRow.labelsThatFit([luz], 0), [false]);
    });

    test('el texto agrandado por accesibilidad achica lo que entra', () {
      final ancho = widthOf([true, true, true]);
      expect(
        StatusBadgeRow.labelsThatFit(todos, ancho,
            textScaler: const TextScaler.linear(1.6)),
        isNot([true, true, true]),
      );
    });
  });
}
