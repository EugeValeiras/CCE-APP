import 'package:flutter/material.dart';

/// Messenger global de la app, SIN BuildContext: se cablea en el MaterialApp
/// raíz ([MaterialApp.scaffoldMessengerKey]) y los services muestran avisos
/// con [showAppError] desde cualquier capa (usa el snackBarTheme de CceTheme).
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Anti-spam: no repetir el MISMO mensaje en < 3s (p. ej. un slider de brillo
// que dispara varios comandos fallidos seguidos).
String? _lastMessage;
DateTime? _lastShownAt;

/// Muestra un SnackBar de error global. No hace nada si el MaterialApp todavía
/// no montó (currentState null) — el flujo OK nunca llama acá.
void showAppError(String message) {
  final now = DateTime.now();
  if (message == _lastMessage &&
      _lastShownAt != null &&
      now.difference(_lastShownAt!) < const Duration(seconds: 3)) {
    return;
  }
  _lastMessage = message;
  _lastShownAt = now;
  appMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
}
