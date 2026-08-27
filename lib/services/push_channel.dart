import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dueño ÚNICO del MethodChannel `com.cce.apns` (CCE#23).
///
/// El AppDelegate manda por ese canal tres cosas: el token de APNs
/// (`onToken`), una push que llegó con la app en primer plano
/// (`onPushReceived`) y el toque sobre una push (`onPushTapped`). Un
/// MethodChannel admite UN handler, y hasta acá lo ponía [AlarmView] al
/// montarse — o sea, sólo cuando se abría la pantalla de la alarma. Con la
/// home del teléfono como raíz, tocar una push no le llegaba a nadie.
///
/// Ahora el handler se instala en `main()` y vive acá; quien quiera enterarse
/// se suscribe a los streams. El último token y el último toque se guardan
/// para el que llega tarde: el token porque [AlarmView] lo registra cuando se
/// monta, y el toque porque en un arranque en frío la pantalla que lo
/// atiende todavía no existe cuando iOS lo entrega.
class PushChannel {
  PushChannel._();

  static final PushChannel instance = PushChannel._();

  static const MethodChannel _channel = MethodChannel('com.cce.apns');

  final _tokens = StreamController<String>.broadcast();
  final _received = StreamController<Map<String, dynamic>>.broadcast();
  final _tapped = StreamController<Map<String, dynamic>>.broadcast();

  String? _lastToken;
  Map<String, dynamic>? _pendingTap;
  bool _installed = false;

  /// El último token que mandó iOS, para quien se suscribe después.
  String? get lastToken => _lastToken;

  Stream<String> get onToken => _tokens.stream;

  /// Push recibida con la app en primer plano. El AppDelegate suprime el
  /// banner del sistema: lo que se muestre, lo muestra la app.
  Stream<Map<String, dynamic>> get onPushReceived => _received.stream;

  /// El usuario tocó la push. `kind` (`phone-sms`, …) dice qué abrir.
  Stream<Map<String, dynamic>> get onPushTapped => _tapped.stream;

  /// Instala el handler. Idempotente: se llama en `main()` y no importa si
  /// alguien lo vuelve a llamar.
  void install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler(_handle);
  }

  /// Un toque que llegó SIN nadie escuchando (arranque en frío). Se entrega
  /// una sola vez, al primero que lo pide.
  Map<String, dynamic>? takePendingTap() {
    final tap = _pendingTap;
    _pendingTap = null;
    return tap;
  }

  Future<void> _handle(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onToken':
          _lastToken = call.arguments as String;
          _tokens.add(_lastToken!);
        case 'onPushReceived':
          _received.add(_payload(call.arguments));
        case 'onPushTapped':
          final data = _payload(call.arguments);
          if (_tapped.hasListener) {
            _tapped.add(data);
          } else {
            _pendingTap = data;
          }
      }
    } catch (e) {
      debugPrint('📱 [Flutter] Error en MethodChannel: $e');
    }
  }

  static Map<String, dynamic> _payload(Object? args) =>
      args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{};

  /// SÓLO TESTS: simula lo que mandaría el AppDelegate.
  @visibleForTesting
  Future<void> debugDeliver(String method, Object? arguments) =>
      _handle(MethodCall(method, arguments));
}
