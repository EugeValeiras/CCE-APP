// Los dos widgets de la pantalla del teléfono que NO pueden fallar.
//
//  1. EL AVISO DEL AUDIO. La app disca de verdad pero no lleva la voz: si este
//     bloque no se renderiza, el usuario que llama desde el celular no escucha
//     nada, no lee ninguna explicación y da la app por rota. Es criterio de
//     aceptación del issue #10.
//  2. EL DIAL PAD. Que estén las 12 teclas y que el long-press del `0` saque un
//     `+`: sin el `+` no se puede discar un número internacional, y sin `*`/`#`
//     no se navega un menú de voz ni se disca un código de operador (`*2447`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/phone_call.dart';
import 'package:cce_app/views/telephony/audio_notice.dart';
import 'package:cce_app/views/telephony/dial_pad.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 380, height: 640, child: child)),
    );

void main() {
  group('aviso del audio', () {
    testWidgets('en reposo dice que no se escucha por el celular', (t) async {
      final status = PhoneStatus.fromJson({'audioRoute': 'speaker'});
      await t.pumpWidget(_host(AudioRouteNotice(status: status)));

      expect(find.text('El audio se queda en la casa'), findsOneWidget);
      expect(
        find.textContaining('no vas a escuchar ni hablar'),
        findsOneWidget,
      );
      // Y dice POR DÓNDE sale, que es lo que evita que parezca un error.
      expect(find.textContaining('en la casa'), findsWidgets);
    });

    testWidgets('durante la llamada dice por dónde está saliendo el audio',
        (t) async {
      for (final route in ['headset', 'speaker', 'web']) {
        final status = PhoneStatus.fromJson({'audioRoute': route});
        await t.pumpWidget(_host(AudioRouteLine.forCall(status)));

        expect(
          find.textContaining('no vas a escuchar ni hablar'),
          findsOneWidget,
          reason: 'con audioRoute=$route el aviso tiene que estar',
        );
        expect(
          find.textContaining(status.audioRouteLabel),
          findsOneWidget,
          reason: 'con audioRoute=$route falta decir dónde suena',
        );
      }
    });

    testWidgets('sin ruteo informado sigue avisando', (t) async {
      // Que el backend no diga por dónde sale no cambia lo importante: por el
      // celular no se escucha igual.
      final status = PhoneStatus.fromJson({});
      await t.pumpWidget(_host(AudioRouteLine.forCall(status)));
      expect(find.textContaining('no vas a escuchar ni hablar'), findsOneWidget);
    });

    testWidgets('una entrante avisa antes de atender', (t) async {
      await t.pumpWidget(_host(const AudioRouteLine.forIncoming()));
      expect(find.textContaining('el celular no lleva el audio'), findsOneWidget);
    });
  });

  group('DialPad', () {
    testWidgets('están las 12 teclas de un teléfono', (t) async {
      await t.pumpWidget(_host(DialPad(onKey: (_) {})));

      for (final key in [
        '1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#', //
      ]) {
        expect(find.text(key), findsOneWidget, reason: 'falta la tecla $key');
      }
    });

    testWidgets('tocar una tecla la reporta tal cual', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(_host(DialPad(onKey: pressed.add)));

      await t.tap(find.text('2'));
      await t.tap(find.text('*'));
      await t.tap(find.text('#'));
      expect(pressed, ['2', '*', '#']);
    });

    testWidgets('mantener el 0 saca un +', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(_host(DialPad(onKey: pressed.add)));

      // La leyenda del 0 anuncia la segunda función, como en cualquier teléfono.
      expect(find.text('+'), findsOneWidget);
      await t.longPress(find.text('0'));
      expect(pressed, ['+']);
    });

    testWidgets('en modo DTMF el 0 es sólo 0', (t) async {
      // Un '+' no es un tono: mandarlo a una llamada no significa nada.
      final pressed = <String>[];
      await t.pumpWidget(
        _host(DialPad(onKey: pressed.add, plusOnZero: false)),
      );

      expect(find.text('+'), findsNothing);
      await t.tap(find.text('0'));
      expect(pressed, ['0']);
      // Sin segunda función, mantenerla apretada manda el mismo tono: en un
      // menú de voz, un long-press que no hace nada se lee como tecla trabada.
      await t.longPress(find.text('0'));
      expect(pressed, ['0', '0']);
    });

    testWidgets('en una pantalla chica se achica en vez de desbordar', (t) async {
      // Con una entrante, un error del backend y una llamada arriba, al teclado
      // le puede quedar muy poco alto. Un RenderFlex desbordado se ve como una
      // franja de rayas amarillas y negras sobre el teclado: inaceptable en la
      // pantalla desde la que se llama.
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 280, height: 150, child: DialPad(onKey: (_) {})),
          ),
        ),
      );

      expect(t.takeException(), isNull);
      expect(find.text('5'), findsOneWidget);
      // Y sigue siendo un teclado: se puede tocar.
      await t.tap(find.text('5'));
    });

    testWidgets('deshabilitado no disca', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(
        _host(DialPad(onKey: pressed.add, enabled: false)),
      );

      await t.tap(find.text('5'));
      expect(pressed, isEmpty);
    });
  });
}
