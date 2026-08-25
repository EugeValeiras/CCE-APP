// Estado de la línea y libreta de la telefonía 4G (`GET /api/phone/status` y
// `/phone/contacts`), más el rechazo de los comandos.
//
// Lo que protege:
//
//  1. EL AVISO DEL AUDIO. La app no lleva audio: la llamada sale y el destino
//     suena, pero la voz se queda en el HAT o en el navegador. Que la pantalla
//     lo diga es criterio de aceptación del issue #10 — si `audioRoute` se
//     parsea mal, el aviso desaparece o dice cualquier cosa y el usuario
//     concluye que la app está rota.
//  2. El motivo REAL de un rechazo. Los POST de `/phone/*` contestan 201 con
//     `{ success: false, reason }`: si el reason se perdiera, "rate limit
//     alcanzado" se leería como "algo falló" y el usuario reintentaría contra
//     un límite que no va a ceder.
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/phone_call.dart';

void main() {
  group('PhoneStatus.fromJson', () {
    test('respuesta real de la línea, con el audio en el navegador', () {
      final st = PhoneStatus.fromJson({
        'enabled': true,
        'online': true,
        'registered': true,
        'operator': 'AR PERSONAL Personal',
        'tech': 'WCDMA',
        'signal': {'rssi': 15, 'dbm': -83, 'bars': 4},
        'lineActive': 'unknown',
        'balance': null,
        'ownNumber': '+5492616260811',
        'call': {'state': 'idle', 'elapsedMs': 0},
        'audioRoute': 'web',
        'callsLastHour': 1,
        'maxCallsPerHour': 100,
      });

      expect(st.enabled, isTrue);
      expect(st.signalBars, 4);
      expect(st.audioRoute, AudioRoute.web);
      expect(st.callState, 'idle');
      expect(st.balance, isNull);
      // Registrado NO es operativo: mientras no se haya hecho el USSD, la app
      // no puede decir "línea activa".
      expect(st.lineActive, 'unknown');
      expect(st.lineLabel, 'AR PERSONAL Personal');
    });

    test('un status vacío no inventa un ruteo de audio', () {
      final st = PhoneStatus.fromJson({});
      expect(st.audioRoute, AudioRoute.unknown);
      expect(st.callState, 'idle');
      expect(st.signalBars, 0);
      // Aun sin saber por dónde sale, lo que la app SÍ sabe es que no sale por
      // el celular, y eso es lo que tiene que decir.
      expect(st.audioNotice, contains('no vas a escuchar ni hablar'));
    });

    test('cada ruteo dice dónde suena, mientras el audio no esté en esta app',
        () {
      // El aviso vale mientras el audio NO lo tenga esta app (CCE#12): cuando
      // lo tiene, la pantalla muestra lo contrario y este texto no se usa.
      for (final raw in ['headset', 'speaker', 'web', null, 'marciano']) {
        final st = PhoneStatus.fromJson({'audioRoute': raw});
        expect(st.audioRouteLabel, isNotEmpty);
        expect(st.audioNotice, contains('no vas a escuchar ni hablar'));
        expect(st.audioNotice.toLowerCase(), isNot(contains('celular vas')));
      }

      expect(
        PhoneStatus.fromJson({'audioRoute': 'headset'}).audioRouteLabel,
        contains('en la casa'),
      );
      expect(
        PhoneStatus.fromJson({'audioRoute': 'speaker'}).audioRouteLabel,
        contains('en la casa'),
      );
    });

    test('con audioRoute=web dice QUIÉN tiene el audio, no "el dashboard"', () {
      // Hasta CCE#12 'web' significaba el navegador y punto. Ahora significa
      // "PCM sobre USB" y del otro lado puede haber un dashboard, un celular o
      // nadie: decir siempre "dashboard" mandaría al usuario a buscar el audio
      // donde no está.
      PhoneStatus withClient(String? client, {bool active = true}) =>
          PhoneStatus.fromJson({
            'audioRoute': 'web',
            'webAudio': {'client': client, 'sessionActive': active},
          });

      expect(withClient('dashboard').audioClient, AudioClient.dashboard);
      expect(withClient('dashboard').audioRouteLabel, contains('dashboard'));

      expect(withClient('app').audioClient, AudioClient.app);
      expect(withClient('app').audioRouteLabel, contains('app'));
      expect(withClient('app').audioNotice, contains('otro dispositivo'));

      expect(withClient('desconocido').audioClient, AudioClient.other);
      expect(withClient('desconocido').audioRouteLabel, contains('otro'));

      // Ruteo en 'web' pero sin nadie conectado: la voz sale igual por el jack.
      final nobody = withClient(null, active: false);
      expect(nobody.audioClient, isNull);
      expect(nobody.audioSessionActive, isFalse);
      expect(nobody.audioRouteLabel, contains('Nadie tomó el audio'));
      expect(nobody.audioNotice, contains('no vas a escuchar ni hablar'));

      // Y el aviso sigue estando en todos los casos.
      for (final client in ['dashboard', 'app', 'desconocido', null]) {
        expect(
          withClient(client).audioNotice,
          contains('no vas a escuchar ni hablar'),
        );
      }
    });

    test('el saldo llega del operador, no de un schema nuestro', () {
      // Texto ya armado, número suelto y objeto: las tres formas se normalizan
      // a algo mostrable, y lo vacío se trata como no tenerlo.
      expect(PhoneStatus.fromJson({'balance': r'$1.234,50'}).balance,
          r'$1.234,50');
      expect(PhoneStatus.fromJson({'balance': 1234.5}).balance, '1234.5');
      expect(
        PhoneStatus.fromJson({
          'balance': {'text': r'$980'}
        }).balance,
        r'$980',
      );
      expect(PhoneStatus.fromJson({'balance': '   '}).balance, isNull);
      expect(PhoneStatus.fromJson({'balance': null}).balance, isNull);
    });

    test('el aviso de rate limit aparece antes de que corte, no después', () {
      PhoneStatus at(int used) => PhoneStatus.fromJson({
            'callsLastHour': used,
            'maxCallsPerHour': 100,
          });

      expect(at(1).rateLimitNear, isFalse);
      expect(at(79).rateLimitNear, isFalse);
      expect(at(80).rateLimitNear, isTrue);
      expect(at(100).rateLimitNear, isTrue);
      expect(at(80).rateLimitLabel, '80 de 100 llamadas en la última hora');

      // Sin tope informado no hay nada que avisar (no se asume uno).
      expect(PhoneStatus.fromJson({'callsLastHour': 5}).rateLimitNear, isFalse);
    });
  });

  group('PhoneContact', () {
    test('parsea la libreta del backend', () {
      final c = PhoneContact.fromJson({
        'id': 'cmt90vmxu',
        'name': 'Cual es mi número',
        'number': '*2447',
      });
      expect(c.id, 'cmt90vmxu');
      expect(c.displayName, 'Cual es mi número');
      expect(c.number, '*2447');
    });

    test('un contacto sin nombre se muestra por su número, no en blanco', () {
      final c = PhoneContact.fromJson({'id': 'x', 'number': '+5492616260811'});
      expect(c.displayName, '+5492616260811');
    });
  });

  group('PhoneCommandException', () {
    test('lleva el motivo del backend tal cual', () {
      // Estos textos son los que el usuario necesita LEER: uno dice esperar a
      // que termine la llamada y el otro dice esperar una hora.
      const enCurso = PhoneCommandException('hay una llamada en curso');
      const limite =
          PhoneCommandException('rate limit de llamadas por hora alcanzado');
      expect(enCurso.reason, 'hay una llamada en curso');
      expect('$limite', 'rate limit de llamadas por hora alcanzado');
    });
  });
}
