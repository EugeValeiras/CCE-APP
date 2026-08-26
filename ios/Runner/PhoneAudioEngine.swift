import AVFoundation
import Foundation
import os

/// Audio full-duplex de la llamada del HAT 4G, en el celular (CCE#12).
///
/// Este archivo NO sabe nada de Flutter ni de WebSockets: recibe PCM de la
/// línea, entrega PCM del micrófono y avisa cuando el sistema le mueve el piso.
/// El puente vive en `PhoneAudioPlugin.swift`.
///
/// ## El formato es el del módem, sin transcodificar
///
/// **PCM 8 kHz, 16-bit little-endian, mono**, 320 bytes cada 20 ms (medido
/// sobre el SIM7600G-H en `EugeValeiras/CCE#5`). El hardware del iPhone trabaja
/// a 48 kHz: la conversión de subida la hace `AVAudioConverter` y la de bajada
/// se hace a mano en el render block, por las razones de abajo.
///
/// ## Lo que resuelve el eco, que es EL riesgo de esta tarea
///
/// En el navegador el eco lo cancela `echoCancellation` de `getUserMedia`. Acá
/// hay que pedirlo explícitamente, y son **dos** cosas distintas que se hacen
/// las dos:
///
///  1. `AVAudioSession` en `.playAndRecord` con modo **`.voiceChat`**, que le
///     dice al sistema que esto es una conversación (rutea al auricular por
///     defecto, ajusta el procesamiento de la señal y baja la latencia).
///  2. **`inputNode.setVoiceProcessingEnabled(true)`** en el `AVAudioEngine`,
///     que es lo que realmente pone el **Voice-Processing I/O** debajo del
///     grafo — cancelación de eco y supresión de ruido nativas. Sin esto, el
///     modo de la sesión por sí solo no le cambia el I/O unit al engine, y con
///     el altavoz encendido el interlocutor se escucha a sí mismo.
///
/// Con auriculares el eco no aparece igual, así que **esto sólo se puede dar
/// por bueno probando con el altavoz**.
///
/// ## Por qué el downlink se resamplea a mano
///
/// La subida (micrófono → línea) va con `AVAudioConverter`: es un decimado con
/// filtro de verdad y hacerlo a mano sería aliasing puro. La bajada, en cambio,
/// se interpola en el render block con el mismo criterio que el worklet del
/// dashboard (lineal, que para voz de banda angosta alcanza) para no depender
/// de que el `mainMixerNode` acepte una conexión a 8 kHz: declarar el nodo en
/// la tasa del mixer y resamplear adentro es una variable menos en un camino
/// que no se puede probar sin hardware.
final class PhoneAudioEngine {
  /// Muestras por segundo de la línea. `AT+CPCMFRM=0` ⇒ 8 kHz (narrowband).
  static let lineRate: Double = 8000
  /// 20 ms de línea: 160 muestras, 320 bytes. Mismo frame que el pacer del backend.
  static let frameSamples = 160

  /// Por dónde está saliendo el audio ahora mismo.
  enum Output: String {
    case receiver   // el auricular de arriba del teléfono (el default)
    case speaker    // manos libres
    case headphones // auriculares con cable
    case bluetooth
    case other
  }

  /// Lo que este motor le cuenta al mundo. Todo llega en el hilo principal.
  struct Callbacks {
    /// Un frame de 320 bytes del micrófono, listo para mandar a la línea.
    var onUplinkFrame: (Data) -> Void
    /// Cambió la salida (enchufaron auriculares, se conectó un manos libres).
    var onOutputChanged: (Output) -> Void
    /// El sistema interrumpió el audio. `resumed` dice si se pudo recuperar.
    var onInterruption: (_ began: Bool, _ resumed: Bool) -> Void
    /// Diagnóstico del jitter buffer, cada ~1 s.
    var onStats: (_ bufferedMs: Int, _ dropped: Int) -> Void
    /// Algo se rompió y el audio no va a volver solo.
    var onFailure: (String) -> Void
  }

  // ── Jitter buffer de reproducción ─────────────────────────────────────────
  //
  // Mismo compromiso que en la web: más buffer es más tolerancia a la red y más
  // retardo en la conversación. Pasado el techo se tira lo VIEJO — descartar lo
  // nuevo dejaría la cola llena para siempre y la conversación quedaría corrida
  // hacia atrás de forma permanente; saltar hacia adelante duele una vez y
  // recupera el vivo.
  //
  // Los valores son los que el dashboard tiene medidos (80 / 200 ms). Sobre
  // datos móviles el jitter es peor que en una LAN: si en el teléfono se
  // escuchan cortes, es el primer número a subir.
  private let targetMs: Double
  private let maxMs: Double

  /// Cola circular de muestras de la línea (Int16). Capacidad: 2 s.
  private var ring = [Int16](repeating: 0, count: Int(lineRate) * 2)
  private var readIndex = 0
  private var writeIndex = 0
  private var queued = 0
  /// Arranca callado hasta juntar `targetMs`: si no, el primer segundo tose.
  private var priming = true
  private var droppedSamples = 0

  /// El render block corre en un hilo de TIEMPO REAL: nada de allocations ni de
  /// locks caros ahí adentro. `os_unfair_lock` sobre un `memcpy` de 320 bytes
  /// es lo más barato que hay disponible sin escribir un lock-free a mano.
  ///
  /// Vive en un puntero y no en una propiedad porque `&self.lock` sobre una
  /// propiedad de clase viola la exclusividad de acceso de Swift.
  private let lock: UnsafeMutablePointer<os_unfair_lock> = {
    let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    p.initialize(to: os_unfair_lock())
    return p
  }()

  // ── Grafo ─────────────────────────────────────────────────────────────────

  private let engine = AVAudioEngine()
  private var sourceNode: AVAudioSourceNode?
  private var converter: AVAudioConverter?
  private var callbacks: Callbacks
  private var running = false
  /// El grafo está armado (aunque el engine esté parado por una interrupción o
  /// por un reset del sistema). Es lo que hace que `stop()` limpie SIEMPRE.
  private var configured = false
  private var muted = false
  private var speakerWanted = false

  /// Tasa de salida del mixer. Se lee una vez al armar el grafo.
  private var renderRate: Double = 48000
  /// Paso del resampleo de bajada (8000 / renderRate) y posición fraccional.
  private var step: Double = PhoneAudioEngine.lineRate / 48000
  private var frac: Double = 0
  private var prevSample: Float = 0
  private var currSample: Float = 0

  /// Acumulador del uplink: el converter entrega bloques de tamaño arbitrario y
  /// la línea quiere frames exactos de 160 muestras.
  private var uplinkAcc = [Int16]()
  private var statsTick = 0

  init(targetMs: Double = 80, maxMs: Double = 200, callbacks: Callbacks) {
    self.targetMs = targetMs
    self.maxMs = maxMs
    self.callbacks = callbacks
  }

  deinit {
    lock.deinitialize(count: 1)
    lock.deallocate()
  }

  // ── Permiso ───────────────────────────────────────────────────────────────

  /// 'granted' | 'denied' | 'undetermined'. Negarlo NO puede romper la llamada:
  /// el audio se queda en la casa y la app lo explica.
  static func permissionStatus() -> String {
    if #available(iOS 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: return "granted"
      case .denied: return "denied"
      default: return "undetermined"
      }
    }
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: return "granted"
    case .denied: return "denied"
    default: return "undetermined"
    }
  }

  static func requestPermission(_ done: @escaping (Bool) -> Void) {
    let reply: (Bool) -> Void = { granted in
      DispatchQueue.main.async { done(granted) }
    }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: reply)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(reply)
    }
  }

  // ── Arranque y parada ─────────────────────────────────────────────────────

  /// Configura la sesión, arma el grafo y arranca. Lanza con un motivo legible.
  func start() throws {
    guard !running else { return }

    let session = AVAudioSession.sharedInstance()
    // `.voiceChat` es lo que convierte esto en una llamada para iOS: ruteo al
    // auricular por defecto, procesamiento de voz y baja latencia.
    // `.allowBluetooth` habilita HFP, que es el perfil que tiene micrófono; A2DP
    // (auriculares de música) es sólo salida y no sirve para hablar.
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    // 20 ms: el mismo frame que la línea. Es una preferencia, no una garantía —
    // el sistema entrega lo que puede.
    try? session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: [])

    let input = engine.inputNode
    // ESTO es lo que pone el Voice-Processing I/O debajo del grafo (iOS 13+):
    // cancelación de eco y supresión de ruido. Va ANTES de leer formatos y de
    // conectar nada, porque habilitarlo reinicializa el I/O y le cambia el
    // formato al nodo de entrada.
    do {
      try input.setVoiceProcessingEnabled(true)
    } catch {
      // Sin AEC la llamada igual funciona con auriculares, así que no se aborta:
      // se avisa, y quien esté con el altavoz va a escuchar el eco y va a saber
      // por qué.
      callbacks.onFailure(
        "iOS no pudo activar la cancelación de eco: con el altavoz vas a escuchar eco."
      )
    }

    let mixer = engine.mainMixerNode
    renderRate = mixer.outputFormat(forBus: 0).sampleRate
    if renderRate <= 0 { renderRate = 48000 }
    step = PhoneAudioEngine.lineRate / renderRate
    frac = 0
    prevSample = 0
    currSample = 0
    resetBuffer()

    guard
      let renderFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: renderRate,
        channels: 1, interleaved: false)
    else {
      throw PhoneAudioError.message("No se pudo describir el formato de salida.")
    }

    let node = AVAudioSourceNode(format: renderFormat) { [weak self] _, _, frameCount, audioBufferList in
      guard let self = self else { return noErr }
      self.render(frameCount: frameCount, into: audioBufferList)
      return noErr
    }
    sourceNode = node
    engine.attach(node)
    engine.connect(node, to: mixer, format: renderFormat)

    // El tap va con el formato REAL del nodo de entrada, leído después de
    // habilitar el voice processing: pedirle otro al tap es la receta para un
    // crash en `installTap`.
    let tapFormat = input.outputFormat(forBus: 0)
    guard tapFormat.sampleRate > 0 else {
      throw PhoneAudioError.message("El micrófono no está disponible.")
    }
    guard
      let lineFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: PhoneAudioEngine.lineRate,
        channels: 1, interleaved: true),
      let conv = AVAudioConverter(from: tapFormat, to: lineFormat)
    else {
      throw PhoneAudioError.message("No se pudo preparar la conversión del micrófono.")
    }
    converter = conv
    uplinkAcc.removeAll(keepingCapacity: true)

    input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
      self?.captured(buffer, into: lineFormat)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw PhoneAudioError.message("No se pudo arrancar el audio: \(error.localizedDescription)")
    }

    running = true
    configured = true
    observeSystem()
    applyOutputOverride()
    callbacks.onOutputChanged(currentOutput())
  }

  /// Suelta todo y devuelve la sesión al sistema. Idempotente.
  ///
  /// No mira `running`: después de un reset del servidor de audio del sistema
  /// el motor queda parado pero con el tap y el nodo puestos, y ahí es
  /// justamente cuando hay que limpiar.
  func stop() {
    guard configured else { return }
    configured = false
    running = false
    NotificationCenter.default.removeObserver(self)
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    if let node = sourceNode {
      engine.detach(node)
      sourceNode = nil
    }
    converter = nil
    resetBuffer()
    // `.notifyOthersOnDeactivation` devuelve el audio a quien lo tenía antes
    // (la música que estaba sonando, por ejemplo). Sin esto, el resto del
    // sistema se queda mudo hasta que algo más reclame la sesión.
    try? AVAudioSession.sharedInstance().setActive(
      false, options: [.notifyOthersOnDeactivation])
  }

  // ── Downlink: de la línea al parlante ─────────────────────────────────────

  /// PCM 16-bit LE de la línea, tal como llegó del WebSocket.
  ///
  /// Un buffer de longitud impar rompería la alineación de las muestras y todo
  /// lo que siga suena a ruido blanco: el byte suelto se descarta (es medio
  /// sample, inaudible).
  func enqueueDownlink(_ data: Data) {
    guard running else { return }
    let count = data.count / 2
    guard count > 0 else { return }

    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      os_unfair_lock_lock(lock)
      defer { os_unfair_lock_unlock(lock) }
      for i in 0..<count {
        // Little-endian explícito: no se asume el orden del host aunque hoy
        // coincida. `loadUnaligned` no existe en iOS 13, así que se arma a mano.
        let lo = UInt16(raw[i * 2])
        let hi = UInt16(raw[i * 2 + 1])
        ring[writeIndex] = Int16(bitPattern: lo | (hi << 8))
        writeIndex = (writeIndex + 1) % ring.count
        if queued == ring.count {
          // Cola llena de verdad: se pisa lo más viejo.
          readIndex = (readIndex + 1) % ring.count
          droppedSamples += 1
        } else {
          queued += 1
        }
      }
      trimLocked()
      if priming && bufferedMsLocked() >= targetMs { priming = false }
    }
  }

  /// Tira lo VIEJO hasta volver bajo el techo. Con el lock tomado.
  private func trimLocked() {
    let maxSamples = Int(maxMs * PhoneAudioEngine.lineRate / 1000)
    while queued > maxSamples {
      readIndex = (readIndex + 1) % ring.count
      queued -= 1
      droppedSamples += 1
    }
  }

  private func bufferedMsLocked() -> Double {
    Double(queued) / PhoneAudioEngine.lineRate * 1000
  }

  private func resetBuffer() {
    os_unfair_lock_lock(lock)
    readIndex = 0
    writeIndex = 0
    queued = 0
    priming = true
    os_unfair_lock_unlock(lock)
  }

  /// Render de tiempo real: interpola de 8 kHz a la tasa del mixer.
  private func render(frameCount: AVAudioFrameCount, into abl: UnsafeMutablePointer<AudioBufferList>) {
    let buffers = UnsafeMutableAudioBufferListPointer(abl)
    guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
    let frames = Int(frameCount)

    os_unfair_lock_lock(lock)
    let starving = priming
    os_unfair_lock_unlock(lock)

    if starving {
      // Todavía cebando: silencio. Un buffer a medio llenar se escucha peor que
      // un momento de nada.
      for i in 0..<frames { out[i] = 0 }
      fillSilence(buffers: buffers, frames: frames)
      return
    }

    for i in 0..<frames {
      while frac >= 1 {
        guard let next = nextLineSample() else {
          // Underrun: se vuelve a cebar y lo que sale es silencio. Un hueco se
          // escucha mejor que un chasquido.
          for j in i..<frames { out[j] = 0 }
          os_unfair_lock_lock(lock)
          priming = true
          os_unfair_lock_unlock(lock)
          fillSilence(buffers: buffers, frames: frames, from: i)
          return
        }
        prevSample = currSample
        currSample = next
        frac -= 1
      }
      out[i] = prevSample + (currSample - prevSample) * Float(frac)
      frac += step
    }
    // Mono a un grafo que puede pedir estéreo: se copia el mismo canal.
    mirrorChannels(buffers: buffers, frames: frames)
  }

  /// Próxima muestra de la línea en float, o nil si no hay.
  private func nextLineSample() -> Float? {
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    guard queued > 0 else { return nil }
    let sample = ring[readIndex]
    readIndex = (readIndex + 1) % ring.count
    queued -= 1
    return Float(sample) / 32768.0
  }

  private func fillSilence(
    buffers: UnsafeMutableAudioBufferListPointer, frames: Int, from: Int = 0
  ) {
    for b in 1..<max(1, buffers.count) {
      guard let ch = buffers[b].mData?.assumingMemoryBound(to: Float.self) else { continue }
      for i in from..<frames { ch[i] = 0 }
    }
  }

  private func mirrorChannels(buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
    guard buffers.count > 1,
      let first = buffers[0].mData?.assumingMemoryBound(to: Float.self)
    else { return }
    for b in 1..<buffers.count {
      guard let ch = buffers[b].mData?.assumingMemoryBound(to: Float.self) else { continue }
      for i in 0..<frames { ch[i] = first[i] }
    }
  }

  // ── Uplink: del micrófono a la línea ──────────────────────────────────────

  private func captured(_ buffer: AVAudioPCMBuffer, into lineFormat: AVAudioFormat) {
    guard running, let conv = converter, buffer.frameLength > 0 else { return }

    let ratio = PhoneAudioEngine.lineRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
    guard let out = AVAudioPCMBuffer(pcmFormat: lineFormat, frameCapacity: capacity) else { return }

    var consumed = false
    var error: NSError?
    // `.noDataNow` y no `.endOfStream`: cerrar el converter en cada tap lo
    // obligaría a rearmar el filtro y perdería el estado entre bloques.
    let status = conv.convert(to: out, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, out.frameLength > 0,
      let samples = out.int16ChannelData?[0]
    else { return }

    let count = Int(out.frameLength)
    if muted {
      // Mudo NO es dejar de mandar: el módem espera flujo continuo y el backend
      // rellenaría con silencio igual. Mandar ceros mantiene el ritmo y el
      // medidor de entrada cae a cero, que es lo que hay que ver.
      uplinkAcc.append(contentsOf: repeatElement(0, count: count))
    } else {
      uplinkAcc.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
    }

    let frameSamples = PhoneAudioEngine.frameSamples
    while uplinkAcc.count >= frameSamples {
      let frame = Array(uplinkAcc.prefix(frameSamples))
      uplinkAcc.removeFirst(frameSamples)
      var data = Data(count: frameSamples * 2)
      data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
        for (i, sample) in frame.enumerated() {
          let bits = UInt16(bitPattern: sample)
          raw[i * 2] = UInt8(bits & 0xff)
          raw[i * 2 + 1] = UInt8(bits >> 8)
        }
      }
      // Los canales de Flutter no son thread-safe: el tap corre en el hilo de
      // audio y todo lo que cruza a Dart se despacha al principal.
      DispatchQueue.main.async { [weak self] in self?.callbacks.onUplinkFrame(data) }
    }

    statsTick += 1
    if statsTick >= 50 {  // ~1 s: el tap entrega bloques de ~20 ms
      statsTick = 0
      os_unfair_lock_lock(lock)
      let ms = Int(bufferedMsLocked())
      let dropped = droppedSamples
      os_unfair_lock_unlock(lock)
      DispatchQueue.main.async { [weak self] in self?.callbacks.onStats(ms, dropped) }
    }
  }

  // ── Controles ─────────────────────────────────────────────────────────────

  func setMuted(_ value: Bool) {
    muted = value
  }

  /// Altavoz o auricular. Con auriculares o manos libres conectados NO se toca
  /// nada: forzar el altavoz con los auriculares puestos es sacarle el audio al
  /// usuario de la oreja sin que lo haya pedido.
  func setSpeaker(_ value: Bool) {
    speakerWanted = value
    applyOutputOverride()
  }

  private func applyOutputOverride() {
    let session = AVAudioSession.sharedInstance()
    let current = currentOutput()
    guard current == .receiver || current == .speaker else { return }
    try? session.overrideOutputAudioPort(speakerWanted ? .speaker : .none)
  }

  func currentOutput() -> Output {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let port = outputs.first else { return .other }
    switch port.portType {
    case .builtInReceiver: return .receiver
    case .builtInSpeaker: return .speaker
    case .headphones, .usbAudio: return .headphones
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE: return .bluetooth
    default: return .other
    }
  }

  // ── El sistema mete la mano ───────────────────────────────────────────────

  private func observeSystem() {
    let center = NotificationCenter.default
    center.removeObserver(self)
    center.addObserver(
      self, selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
  }

  /// Una llamada telefónica DE VERDAD al celular, o Siri, o una alarma.
  ///
  /// En `.began` el sistema ya paró el engine: no hay nada que apagar, sólo que
  /// contarlo. En `.ended` se reactiva sólo si el sistema dice que se puede
  /// (`shouldResume`); si no, se suelta limpio y la llamada sigue por el jack de
  /// la casa. Lo que no puede pasar es quedar "prendido" sin audio.
  @objc private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }

    if type == .began {
      resetBuffer()
      callbacks.onInterruption(true, false)
      return
    }

    let options = AVAudioSession.InterruptionOptions(
      rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
    guard options.contains(.shouldResume) else {
      callbacks.onInterruption(false, false)
      return
    }
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: [])
      if !engine.isRunning { try engine.start() }
      resetBuffer()
      applyOutputOverride()
      callbacks.onInterruption(false, true)
    } catch {
      callbacks.onInterruption(false, false)
    }
  }

  @objc private func handleRouteChange(_ note: Notification) {
    guard running else { return }
    // Enchufar auriculares en medio de la llamada tiene que verse en la UI, y
    // desenchufarlos no puede dejar el override del altavoz colgado.
    applyOutputOverride()
    callbacks.onOutputChanged(currentOutput())
  }

  /// El servidor de audio del sistema se reinició: TODO lo que hay armado quedó
  /// inválido. No se intenta rearmar acá — se avisa y la capa de arriba decide.
  @objc private func handleReset(_ note: Notification) {
    running = false
    callbacks.onFailure("El audio del sistema se reinició. Volvé a tomar el audio.")
  }
}

/// Error con un motivo pensado para que lo lea el usuario, no para un log.
enum PhoneAudioError: Error {
  case message(String)

  var text: String {
    switch self {
    case .message(let m): return m
    }
  }
}
