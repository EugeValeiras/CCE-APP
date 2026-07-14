import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/alarm_event.dart';
import '../models/server_config.dart';

class DeviceStateEvent {
  final String deviceId;
  final Map<String, dynamic>? state;
  final Map<String, dynamic>? sensor;
  DeviceStateEvent({required this.deviceId, this.state, this.sensor});
}

class LiveEvent {
  final String eventName;
  final Map<String, dynamic> payload;
  final DateTime time;
  LiveEvent({required this.eventName, required this.payload, required this.time});
}

class SocketService {
  io.Socket? _socket;
  StreamController<AlarmEvent> _alarmController = StreamController<AlarmEvent>.broadcast();
  StreamController<bool> _armedController = StreamController<bool>.broadcast();
  StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  StreamController<DeviceStateEvent> _deviceController = StreamController<DeviceStateEvent>.broadcast();
  StreamController<LiveEvent> _liveController = StreamController<LiveEvent>.broadcast();
  bool _isConnected = false;

  Stream<AlarmEvent> get onAlarm => _alarmController.stream;
  Stream<bool> get onArmedChanged => _armedController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  Stream<DeviceStateEvent> get onDeviceChanged => _deviceController.stream;
  Stream<LiveEvent> get onLiveEvent => _liveController.stream;
  bool get isConnected => _isConnected;

  void _emitLive(String name, dynamic data) {
    if (_liveController.isClosed) return;
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    _liveController.add(LiveEvent(eventName: name, payload: map, time: DateTime.now()));
  }

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
    if (_deviceController.isClosed) {
      _deviceController = StreamController<DeviceStateEvent>.broadcast();
    }
    if (_liveController.isClosed) {
      _liveController = StreamController<LiveEvent>.broadcast();
    }

    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(30000);
    // Auth del handshake Socket.IO: solo si hay token configurado (si no, el
    // handshake queda EXACTAMENTE como antes).
    if (ServerConfig.apiToken.isNotEmpty) {
      options.setAuth({'token': ServerConfig.apiToken});
    }
    _socket = io.io(config.socketUrl, options.build());

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
      _emitLive('alarm:triggered', data);
      if (_alarmController.isClosed) return;
      if (data is Map<String, dynamic>) {
        _alarmController.add(AlarmEvent.fromJson(data));
      } else if (data is Map) {
        _alarmController.add(AlarmEvent.fromJson(Map<String, dynamic>.from(data)));
      }
    });

    _socket!.on('alarm:armed-changed', (data) {
      _emitLive('alarm:armed-changed', data);
      if (_armedController.isClosed) return;
      if (data is Map) {
        final armed = data['armed'] == true;
        _armedController.add(armed);
      }
    });

    void handleDeviceEvent(String eventName, dynamic data) {
      _emitLive(eventName, data);
      if (_deviceController.isClosed) return;
      if (data is! Map) return;
      final m = Map<String, dynamic>.from(data);
      final did = (m['deviceId'] ?? m['lightId'] ?? '').toString();
      if (did.isEmpty) return;
      _deviceController.add(DeviceStateEvent(
        deviceId: did,
        state: m['state'] is Map ? Map<String, dynamic>.from(m['state'] as Map) : null,
        sensor: m['sensor'] is Map ? Map<String, dynamic>.from(m['sensor'] as Map) : null,
      ));
    }

    _socket!.on('device:state-changed', (d) => handleDeviceEvent('device:state-changed', d));
    _socket!.on('light:changed', (d) => handleDeviceEvent('light:changed', d));
    _socket!.on('automation:executed', (d) => _emitLive('automation:executed', d));
    _socket!.on('config:changed', (d) => _emitLive('config:changed', d));

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
    _alarmController.close();
    _armedController.close();
    _connectionController.close();
    _deviceController.close();
    _liveController.close();
  }
}
