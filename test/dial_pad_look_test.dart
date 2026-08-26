// LA PINTA del teclado del teléfono (issue #11). Es una pantalla que se usa a
// oscuras y apurado: lo que acá se verifica no es estética, es que el teclado
// siga siendo usable.
//
//  1. GEOMETRÍA. Teclas redondas, del mismo diámetro y separadas entre sí. Un
//     teclado sin aire se toca mal: el dedo tapa tres teclas.
//  2. LETRAS ITU E.161. `2 ABC`, `7 PQRS`… Se leen para discar un número que
//     alguien dictó por letras, y para reconocer el teclado de un vistazo.
//  3. FEEDBACK. Háptico liviano y realce visible al tocar: sin acuse, el que
//     disca no sabe si la tecla entró y repite el dígito.
//  4. EL NÚMERO ENTERO. Un número largo achica la tipografía; cortarlo con
//     puntos suspensivos dejaría a la vista un número que no se puede discar.
//  5. LA BOTONERA. Llamar es lo más grande de la pantalla y no se mueve;
//     borrar sólo existe cuando hay algo que borrar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/theme/cce_tokens.dart';
import 'package:cce_app/views/telephony/dial_actions.dart';
import 'package:cce_app/views/telephony/dial_display.dart';
import 'package:cce_app/views/telephony/dial_pad.dart';

Widget _host(Widget child, {double width = 380, double height = 640}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: width, height: height, child: child)),
      ),
    );

/// El círculo de la tecla [digit] (el Container más cercano a su dígito).
Finder _key(String digit) => find
    .ancestor(of: find.text(digit), matching: find.byType(Container))
    .first;

BoxDecoration _deco(WidgetTester t, Finder f) =>
    t.widget<Container>(f).decoration! as BoxDecoration;

void main() {
  group('teclas', () {
    testWidgets('son círculos del mismo tamaño, con aire entre ellas',
        (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      final one = t.getRect(_key('1'));
      expect(one.width, one.height, reason: 'una tecla es redonda, no ovalada');
      expect(_deco(t, _key('1')).shape, BoxShape.circle);

      // Todas iguales: un teclado con teclas de distinto diámetro se lee roto.
      for (final d in ['5', '0', '#']) {
        final other = t.getRect(_key(d));
        expect(other.width, moreOrLessEquals(one.width, epsilon: 0.5),
            reason: 'la tecla $d desentona');
        expect(other.height, moreOrLessEquals(one.height, epsilon: 0.5),
            reason: 'la tecla $d desentona');
      }

      // Aire real entre teclas: ni pegadas ni superpuestas.
      final two = t.getRect(_key('2'));
      final four = t.getRect(_key('4'));
      expect(two.left - one.right, greaterThan(one.width * 0.25),
          reason: 'las teclas de una fila tienen que respirar');
      expect(four.top - one.bottom, greaterThan(one.height * 0.15),
          reason: 'las filas tienen que respirar');
    });

    testWidgets('cada tecla lleva sus letras de teléfono', (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      const letters = {
        '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL', //
        '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ',
      };
      letters.forEach((digit, legend) {
        expect(
          find.descendant(of: _key(digit), matching: find.text(legend)),
          findsOneWidget,
          reason: 'el $digit tiene que decir $legend',
        );
      });

      // El 1 no lleva letras (y el * y el # tampoco): sólo el glifo.
      for (final d in ['1', '*', '#']) {
        expect(find.descendant(of: _key(d), matching: find.byType(Text)),
            findsOneWidget,
            reason: 'la tecla $d no lleva leyenda');
      }
      // El 0 anuncia su segunda función.
      expect(find.descendant(of: _key('0'), matching: find.text('+')),
          findsOneWidget);
    });

    testWidgets('el dígito es lo grande de la tecla, la leyenda lo chico',
        (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      final digit = t.widget<Text>(find.text('2')).style!;
      final legend = t.widget<Text>(find.text('ABC')).style!;
      final side = t.getRect(_key('2')).width;

      expect(digit.fontSize, greaterThan(side * 0.3),
          reason: 'el número se tiene que ver de lejos');
      expect(legend.fontSize! * 2, lessThan(digit.fontSize!),
          reason: 'las letras son un pie de página del número');
      expect(digit.color, CceColors.textPrimary);
      expect(legend.color, CceColors.textTertiary);
    });

    testWidgets('el * y el # son teclas de función: más grandes, y solos',
        (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      final digit = t.widget<Text>(find.text('2')).style!.fontSize!;
      for (final d in ['*', '#']) {
        expect(t.widget<Text>(find.text(d)).style!.fontSize,
            greaterThan(digit * 1.3),
            reason: 'el $d tiene que leerse como tecla de función, no dígito');
        // Van centrados en su círculo, no alineados con el hueco de una
        // leyenda que no tienen: nada de columna dígito + leyenda.
        expect(find.descendant(of: _key(d), matching: find.byType(Column)),
            findsNothing,
            reason: 'el $d no reserva lugar para una leyenda');
        // Y el glifo se centra en el círculo, no en la mitad de arriba.
        final circle = t.getRect(_key(d));
        final glyph = t.getRect(find.text(d));
        expect(glyph.center.dx, moreOrLessEquals(circle.center.dx, epsilon: 0.5));
        expect(glyph.center.dy, greaterThan(circle.center.dy),
            reason: 'la línea base del $d queda por debajo del centro: '
                'es lo que baja el glifo hasta el medio');
      }
    });

    testWidgets('el 1 sigue a la altura del 2 y el 3 (no es tecla de función)',
        (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));
      final one = t.getRect(find.text('1'));
      for (final d in ['2', '3']) {
        expect(t.getRect(find.text(d)).top, moreOrLessEquals(one.top, epsilon: 0.5),
            reason: 'el 1 no tiene letras pero es un dígito: comparte fila');
      }
    });

    testWidgets('con poco alto, la tecla mínima no desborda ningún glifo',
        (t) async {
      // 120 de alto: las teclas caen al diámetro piso y el teclado entero se
      // achica para entrar. Ni así un glifo puede salirse de su círculo.
      await t.pumpWidget(_host(DialPad(onKey: (_) {}), height: 120));
      expect(t.takeException(), isNull, reason: 'sin franjas de overflow');

      final side = t.getRect(_key('5')).width;
      expect(side, lessThan(40), reason: 'si no topó el piso, no prueba nada');
      for (final d in ['1', '2', '0', '*', '#']) {
        final circle = t.getRect(_key(d));
        final glyph = t.getRect(find.text(d));
        expect(glyph.left, greaterThanOrEqualTo(circle.left),
            reason: 'el $d se sale del círculo por la izquierda');
        expect(glyph.right, lessThanOrEqualTo(circle.right),
            reason: 'el $d se sale del círculo por la derecha');
        expect(glyph.width, lessThan(circle.width * 0.8),
            reason: 'el $d no puede ocupar todo el ancho de su tecla');
      }
    });
  });

  group('feedback al tocar', () {
    testWidgets('el toque vibra liviano y el long-press más fuerte', (t) async {
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      await t.tap(find.text('5'));
      expect(haptics, ['HapticFeedbackType.lightImpact'],
          reason: 'discar son doce toques seguidos: el háptico va liviano');

      await t.longPress(find.text('0'));
      expect(haptics.last, 'HapticFeedbackType.mediumImpact',
          reason: 'el + es otro gesto, y se confirma más fuerte');
    });

    testWidgets('la tecla se realza mientras está apretada y vuelve', (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      final rest = _deco(t, _key('5')).color;
      final gesture = await t.startGesture(t.getCenter(find.text('5')));
      // El tap-down recién se confirma pasado kPressTimeout; después arranca
      // la animación del realce.
      await t.pump(const Duration(milliseconds: 120));
      await t.pump(const Duration(milliseconds: 90));
      expect(_deco(t, _key('5')).color, isNot(rest),
          reason: 'sin realce no se ve cuál tecla se tocó');

      await gesture.up();
      await t.pumpAndSettle();
      expect(_deco(t, _key('5')).color, rest,
          reason: 'el realce es un destello, no un estado');
    });
  });

  group('el número', () {
    Widget field(TextEditingController c, {double width = 260}) => _host(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: DialNumberField(
                controller: c,
                focusNode: FocusNode(),
                enabled: true,
              ),
            ),
          ),
        );

    double sizeOf(WidgetTester t) =>
        t.widget<TextField>(find.byType(TextField)).style!.fontSize!;

    testWidgets('uno corto va grande y uno largo se achica', (t) async {
      final c = TextEditingController(text: '911');
      await t.pumpWidget(field(c));
      final short = sizeOf(t);
      expect(short, DialNumberField.maxFontSize);

      c.text = '+549261626081199887';
      await t.pumpWidget(field(c));
      final long = sizeOf(t);
      expect(long, lessThan(short), reason: 'antes que cortarlo, se achica');
      expect(long, greaterThanOrEqualTo(DialNumberField.minFontSize));
      expect(t.takeException(), isNull);
    });

    testWidgets('achicado, el número entra entero en el ancho', (t) async {
      // Ancho generoso a propósito: en los tests la fuente de prueba dibuja
      // cada carácter tan ancho como alto, casi el doble que la real.
      const width = 420.0;
      const number = '+5492616260811998';
      final c = TextEditingController(text: number);
      await t.pumpWidget(field(c, width: width));
      expect(sizeOf(t), greaterThan(DialNumberField.minFontSize),
          reason: 'si topó el piso, este test no prueba el encaje');

      final painter = TextPainter(
        text: TextSpan(text: number, style: DialNumberField.styleAt(sizeOf(t))),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width, lessThanOrEqualTo(width),
          reason: 'un número cortado no se puede discar');
    });

    testWidgets('vacío no grita un placeholder', (t) async {
      await t.pumpWidget(field(TextEditingController()));
      expect(find.text('Número'), findsNothing);
      expect(t.widget<TextField>(find.byType(TextField)).decoration!.hintText,
          isNull);
    });
  });

  group('botonera', () {
    Widget actions({required bool hasNumber, VoidCallback? onBackspace}) => _host(
          Column(
            children: [
              Expanded(child: DialPad(onKey: (_) {})),
              DialActions(
                hasNumber: hasNumber,
                canDial: hasNumber,
                onContacts: () {},
                onCall: () {},
                onBackspace: onBackspace ?? () {},
                onClear: () {},
              ),
            ],
          ),
        );

    testWidgets('llamar es más grande que una tecla, verde y redondo',
        (t) async {
      await t.pumpWidget(actions(hasNumber: true));

      final call = find
          .descendant(
              of: find.byType(PhoneRoundButton), matching: find.byType(Container))
          .first;
      expect(t.getRect(call).width, greaterThan(t.getRect(_key('5')).width),
          reason: 'llamar es LA acción de esta pantalla');
      expect(_deco(t, call).shape, BoxShape.circle);
      expect(_deco(t, call).color, CceColors.ok);
    });

    testWidgets('el borrar aparece sólo con número, y no corre al de llamar',
        (t) async {
      await t.pumpWidget(actions(hasNumber: false));
      expect(find.byIcon(Icons.backspace_outlined), findsNothing,
          reason: 'un borrar apagado al lado de llamar es una trampa');
      final emptyCenter = t.getCenter(find.byType(PhoneRoundButton));

      final borrados = <int>[];
      await t.pumpWidget(actions(hasNumber: true, onBackspace: () => borrados.add(1)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
      expect(t.getCenter(find.byType(PhoneRoundButton)), emptyCenter,
          reason: 'el botón de llamar no se mueve cuando aparece el borrar');

      await t.tap(find.byIcon(Icons.backspace_outlined));
      expect(borrados, [1]);
    });

    testWidgets('sin número discable, llamar no dispara', (t) async {
      await t.pumpWidget(actions(hasNumber: false));
      // Deshabilitado: el fondo deja de ser el verde de llamar.
      final call = find
          .descendant(
              of: find.byType(PhoneRoundButton), matching: find.byType(Container))
          .first;
      expect(_deco(t, call).color, isNot(CceColors.ok));
    });
  });
}
