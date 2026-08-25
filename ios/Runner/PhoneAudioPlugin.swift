import AVFoundation
import Flutter
import Foundation

/// Puente entre Dart y `PhoneAudioEngine` para el audio de la llamada (CCE#12).
///
/// Tres canales, y cada uno existe por un motivo:
///
///  - **`com.cce.phoneaudio`** (`MethodChannel`): control. Permiso, arrancar,
///    parar, altavoz, mudo. Poquitos mensajes y con respuesta.
///  - **`com.cce.phoneaudio/events`** (`EventChannel`): lo que sube. Van los
///    frames del micrófono (50 por segundo) y los avisos del sistema. Un
///    `MethodChannel` por frame a 50 fps sería pagar un round-trip con respuesta
///    cincuenta veces por segundo para nada.
///  - **`com.cce.phoneaudio/downlink`** (`BasicMessageChannel` con
///    `FlutterBinaryCodec`): lo que baja. El PCM de la línea se pasa **crudo**,
///    sin el envoltorio del codec estándar, que a este ritmo es puro costo.
///
/// Un frame del micrófono llega a Dart como `Uint8List` y todo lo demás como
/// `Map`: el mismo canal transporta las dos cosas y Dart discrimina por tipo.
/// Dos `EventChannel` serían dos suscripciones para un solo productor.
///
/// **Nada de esto puede tumbar la app.** La app es la que controla la alarma de
/// la casa: cualquier falla del audio se contesta con un error legible y la
/// llamada sigue por el jack del HAT.
final class PhoneAudioPlugin: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.cce.phoneaudio"
  static let eventsChannelName = "com.cce.phoneaudio/events"
  static let downlinkChannelName = "com.cce.phoneaudio/downlink"

  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let downlink: FlutterBasicMessageChannel

  private var engine: PhoneAudioEngine?
  private var sink: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: PhoneAudioPlugin.methodChannelName, binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: PhoneAudioPlugin.eventsChannelName, binaryMessenger: messenger)
    downlink = FlutterBasicMessageChannel(
      name: PhoneAudioPlugin.downlinkChannelName,
      binaryMessenger: messenger,
      codec: FlutterBinaryCodec.sharedInstance())
    super.init()

    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    events.setStreamHandler(self)
    downlink.setMessageHandler { [weak self] message, reply in
      // El PCM de la línea, tal cual salió del WebSocket.
      if let data = message as? Data { self?.engine?.enqueueDownlink(data) }
      reply(nil)
    }
  }

  // ── Control ───────────────────────────────────────────────────────────────

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStatus":
      result(PhoneAudioEngine.permissionStatus())

    case "start":
      start(args: call.arguments as? [String: Any] ?? [:], result: result)

    case "stop":
      engine?.stop()
      engine = nil
      result(nil)

    case "setSpeaker":
      let on = (call.arguments as? [String: Any])?["speaker"] as? Bool ?? false
      engine?.setSpeaker(on)
      result(engine?.currentOutput().rawValue ?? PhoneAudioEngine.Output.other.rawValue)

    case "setMuted":
      let on = (call.arguments as? [String: Any])?["muted"] as? Bool ?? false
      engine?.setMuted(on)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Pide el permiso si hace falta y arranca el motor.
  ///
  /// Negar el micrófono **no es un error**: se contesta `granted: false` y la
  /// app deja la llamada viva con el audio en la casa. Un `FlutterError` acá
  /// haría que la pantalla mostrara "falló" cuando lo que pasó es que el
  /// usuario dijo que no.
  private func start(args: [String: Any], result: @escaping FlutterResult) {
    let status = PhoneAudioEngine.permissionStatus()
    if status == "denied" {
      result(["granted": false, "permission": status])
      return
    }
    if status == "undetermined" {
      PhoneAudioEngine.requestPermission { [weak self] granted in
        guard granted else {
          result(["granted": false, "permission": "denied"])
          return
        }
        self?.startEngine(args: args, result: result)
      }
      return
    }
    startEngine(args: args, result: result)
  }

  private func startEngine(args: [String: Any], result: @escaping FlutterResult) {
    // Un arranque sobre otro (la app reintenta, o el usuario tocó dos veces)
    // deja el grafo anterior colgado y el segundo tap revienta: se suelta antes.
    engine?.stop()

    let engine = PhoneAudioEngine(
      targetMs: args["targetMs"] as? Double ?? 80,
      maxMs: args["maxMs"] as? Double ?? 200,
      callbacks: PhoneAudioEngine.Callbacks(
        onUplinkFrame: { [weak self] data in
          self?.sink?(FlutterStandardTypedData(bytes: data))
        },
        onOutputChanged: { [weak self] output in
          self?.emit(["type": "output", "value": output.rawValue])
        },
        onInterruption: { [weak self] began, resumed in
          self?.emit(["type": "interruption", "began": began, "resumed": resumed])
        },
        onStats: { [weak self] bufferedMs, dropped in
          self?.emit(["type": "stats", "bufferedMs": bufferedMs, "dropped": dropped])
        },
        onFailure: { [weak self] message in
          self?.emit(["type": "failure", "message": message])
        }
      ))

    do {
      try engine.start()
    } catch let error as PhoneAudioError {
      result(FlutterError(code: "audio-start", message: error.text, details: nil))
      return
    } catch {
      result(
        FlutterError(
          code: "audio-start", message: error.localizedDescription, details: nil))
      return
    }

    self.engine = engine
    result([
      "granted": true,
      "permission": "granted",
      "output": engine.currentOutput().rawValue,
    ])
  }

  private func emit(_ payload: [String: Any]) {
    sink?(payload)
  }

  // ── FlutterStreamHandler ──────────────────────────────────────────────────

  func onListen(
    withArguments arguments: Any?, eventSink: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
