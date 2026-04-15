import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const initSettings = InitializationSettings(iOS: iosSettings);

    await _plugin.initialize(initSettings);
  }

  Future<bool> requestPermissions() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      return granted ?? false;
    }
    return false;
  }

  Future<void> showAlarmNotification({
    required String title,
    required String body,
    bool critical = true,
  }) async {
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'alarm_siren.caf',
      interruptionLevel: InterruptionLevel.critical,
    );

    const details = NotificationDetails(iOS: iosDetails);

    await _plugin.show(
      0,
      title,
      body,
      details,
    );
  }
}
