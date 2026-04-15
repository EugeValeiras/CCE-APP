import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'models/server_config.dart';
import 'views/alarm_view.dart';
import 'views/settings_view.dart';
import 'views/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Never show red error screen - just log errors
  FlutterError.onError = (details) {
    debugPrint('Flutter error: ${details.exceptionAsString()}');
  };

  runApp(const CCEApp());
}

class CCEApp extends StatelessWidget {
  const CCEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCE Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F3460),
          brightness: Brightness.dark,
        ),
      ),
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

enum _AppState { splash, settings, alarm }

class _AppEntryState extends State<_AppEntry> {
  _AppState _state = _AppState.splash;
  ServerConfig? _config;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _config = await ServerConfig.load();
  }

  void _onSplashComplete() {
    setState(() {
      if (_config != null && _config!.isConfigured) {
        _state = _AppState.alarm;
      } else {
        _state = _AppState.settings;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AppState.splash:
        return SplashView(onComplete: _onSplashComplete);
      case _AppState.settings:
        return SettingsView(
          config: _config ?? ServerConfig(),
          onSaved: () async {
            // Reload the saved config so AlarmView gets the latest
            _config = await ServerConfig.load();
            setState(() => _state = _AppState.alarm);
          },
        );
      case _AppState.alarm:
        return AlarmView(initialConfig: _config);
    }
  }
}
