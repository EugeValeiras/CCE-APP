import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var pendingToken: String?

  /// Audio de la llamada del HAT 4G en el celular (CCE#12). Se crea junto con el
  /// canal de APNs porque necesita lo mismo: el `binaryMessenger` del
  /// FlutterViewController, que no existe hasta que la escena montó.
  private var phoneAudio: PhoneAudioPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge, .criticalAlert]
    ) { granted, _ in
      print("📱 Push permission granted: \(granted)")
      if granted {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }
    }

    setupMethodChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // When push arrives while app is in FOREGROUND: forward to Flutter, suppress system banner
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("📱 Push received, app state: \(UIApplication.shared.applicationState.rawValue)")

    var payload: [String: Any] = [:]
    payload["title"] = notification.request.content.title
    payload["body"] = notification.request.content.body
    for (key, value) in userInfo {
      if let key = key as? String, key != "aps" {
        payload[key] = value
      }
    }

    if UIApplication.shared.applicationState == .active {
      // App is truly in foreground → show in-app, suppress system banner
      methodChannel?.invokeMethod("onPushReceived", arguments: payload)
      completionHandler([])
    } else {
      // App is in background/inactive → show system notification
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .sound, .badge])
      } else {
        completionHandler([.alert, .sound, .badge])
      }
    }
  }

  // When user taps a notification (app was in background)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("📱 Notification tapped: \(userInfo)")

    var payload: [String: Any] = [:]
    payload["title"] = response.notification.request.content.title
    payload["body"] = response.notification.request.content.body
    for (key, value) in userInfo {
      if let key = key as? String, key != "aps" {
        payload[key] = value
      }
    }

    methodChannel?.invokeMethod("onPushTapped", arguments: payload)

    completionHandler()
  }

  private func setupMethodChannel() {
    guard let controller = findFlutterViewController() else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.setupMethodChannel()
      }
      return
    }

    methodChannel = FlutterMethodChannel(
      name: "com.cce.apns",
      binaryMessenger: controller.binaryMessenger
    )
    if phoneAudio == nil {
      phoneAudio = PhoneAudioPlugin(messenger: controller.binaryMessenger)
    }
    print("📱 MethodChannel setup OK")

    if let token = pendingToken {
      methodChannel?.invokeMethod("onToken", arguments: token)
      pendingToken = nil
    }
  }

  private func findFlutterViewController() -> FlutterViewController? {
    if let vc = window?.rootViewController as? FlutterViewController {
      return vc
    }
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let vc = scene.windows.first?.rootViewController as? FlutterViewController {
      return vc
    }
    return nil
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("📱 APNs device token: \(token)")

    if let channel = methodChannel {
      channel.invokeMethod("onToken", arguments: token)
    } else {
      pendingToken = token
    }

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("📱 APNs registration failed: \(error.localizedDescription)")
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
