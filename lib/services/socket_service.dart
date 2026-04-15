import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/alarm_event.dart';
import '../models/server_config.dart';

class SocketService {
  io.Socket? _socket;
  StreamController<AlarmEvent> _alarmController = StreamController<AlarmEvent>.broadcast();
  StreamController<bool> _armedController = StreamController<bool>.broadcast();
  StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  bool _isConnected = false;
  bool _disposed = false;

  Stream<AlarmEvent> get onAlarm => _alarmController.stream;
  Stream<bool> get onArmedChanged => _armedController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  bool get isConnected => _isConnected;

  void connect(ServerConfig config) {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    // Recreate controllers if they were closed
    if (_alarmController.isClosed) {
      _alarmController = StreamController<AlarmEvent>.broadcast();
    }
    if (_armedController.isClosed) {
      _armedController = StreamController<bool>.broadcast();
    }
    if (_connectionController.isClosed) {
      _connectionController = StreamController<bool>.broadcast();
    }
    _disposed = false;

    _socket = io.io(
      config.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      if (!_connectionController.isClosed) _connectionController.add(true);
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
    });

    _socket!.onConnectError((_) {
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
    });

    _socket!.on('alarm:triggered', (data) {
      if (_alarmController.isClosed) return;
      if (data is Map<String, dynamic>) {
        _alarmController.add(AlarmEvent.fromJson(data));
      } else if (data is Map) {
        _alarmController.add(AlarmEvent.fromJson(Map<String, dynamic>.from(data)));
      }
    });

    _socket!.on('alarm:armed-changed', (data) {
      if (_armedController.isClosed) return;
      if (data is Map) {
        final armed = data['armed'] == true;
        _armedController.add(armed);
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _disposed = true;
    _alarmController.close();
    _armedController.close();
    _connectionController.close();
  }
}
