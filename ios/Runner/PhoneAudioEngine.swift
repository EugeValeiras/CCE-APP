import AVFoundation
import Foundation
import os

/// Audio full-duplex de la llamada del HAT 4G, en el celular (CCE#12, CCE#18).
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
/// ## El motor se puede parar solo, y hay que ENTERARSE (CCE#18)
///
/// `engine.start()` que vuelve sin tirar NO garantiza audio. Apple documenta
/// (`AVAudioEngine.h`, `AVAudioEngineConfigurationChangeNotification`) que
/// "cuando el I/O unit del engine observa un cambio en el número de canales o
/// la tasa del hardware de entrada o salida, **el engine se detiene solo** y
/// emite esta notificación". Habilitar el Voice-Processing I/O es justamente
/// un cambio de hardware (otro I/O unit, otra tasa y latencia), y hay
/// reproducciones documentadas de `start()` seguido de un engine parado. A eso
/// se suman las interrupciones (llamada al celular, Siri, alarma) que a veces
/// llegan sin su `.ended`, y dispositivos (iPhone 16e, iOS 18.x) donde el tap
/// del micrófono deja de entregar con el engine "corriendo".
///
/// En el #12 nada de esto se miraba: `running` se ponía en `true` después de
/// `start()` y no se volvía a verificar nunca. Resultado: la app afirmaba
/// "Hablás por el celular" con el motor muerto, sin parlante ni micrófono.
///
/// Desde el #18 el estado del motor se **mide**, no se supone:
///
///  - se observa `AVAudioEngineConfigurationChange` y se rearma el grafo;
///  - un **watchdog** en el hilo principal mira `engine.isRunning` y, sobre
///    todo, si el tap del micrófono sigue entregando: sin taps no hay audio,
///    diga lo que diga `isRunning`;
///  - toda parada se intenta recuperar sola, acotado (`maxAutoRestarts`), y
///    se **cuenta** arriba con `onEngine(running:reason:)` para que la UI no
///    mienta y ofrezca reintentar;
///  - se cuentan los frames que el `AVAudioSourceNode` reprodujo de verdad,
///    para distinguir "llegan bytes" de "suenan".
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

  /// Sin taps del micrófono durante este tiempo, el motor está muerto aunque
  /// `isRunning` diga otra cosa. El tap entrega cada ~20 ms: 1,5 s es 75 taps
  /// de margen, que es imposible de confundir con un hipo del scheduler.
  static let captureStallSeconds: TimeInterval = 1.5

  /// Reinicios automáticos SEGUIDOS que se intentan antes de rendirse y dejar
  /// la decisión al usuario. Un motor que arranca y muere tres veces al hilo
  /// no se va a arreglar con la cuarta: se avisa.
  static let maxAutoRestarts = 3

  /// Entre un reinicio automático y el siguiente. Rearmar el grafo tres veces
  /// en un segundo contra un sistema que todavía no soltó el audio es gastar
  /// los tres intentos en nada.
  static let restartSpacingSeconds: TimeInterval = 1.0

  /// Por dónde está saliendo el audio ahora mismo.
  enum Output: String {
    case receiver   // el auricular de arriba del teléfono (el default)
    case speaker    // manos libres
    case headphones // auriculares con cable
    case bluetooth
    case other
  }

  /// Foto del motor para el panel de diagnóstico.
  struct Stats {
    var bufferedMs: Int
    var dropped: Int
    /// Veces que el `AVAudioSourceNode` pidió audio (el render block corrió).
    var renderCalls: Int
    /// Muestras de LÍNEA (a 8 kHz) que se reprodujeron de verdad, sin contar
    /// el silencio de cebado ni de underrun. Esto es lo que distingue "llegan
    /// bytes" de "suenan".
    var renderedSamples: Int
    /// Taps del micrófono que entregaron audio.
    var captureCalls: Int
    var engineRunning: Bool
    var restarts: Int
  }

  /// Lo que este motor le cuenta al mundo. Todo llega en el hilo principal.
  struct Callbacks {
    /// Un frame de 320 bytes del micrófono, listo para mandar a la línea.
    var onUplinkFrame: (Data) -> Void
    /// Cambió la salida (enchufaron auriculares, se conectó un manos libres).
    var onOutputChanged: (Output) -> Void
    /// El sistema interrumpió el audio. `resumed` dice si se pudo recuperar.
    var onInterruption: (_ began: Bool, _ resumed: Bool) -> Void
    /// La verdad sobre el motor: `running` es que el engine corre Y entrega
    /// audio. Con `false`, `reason` dice por qué, para el usuario.
    var onEngine: (_ running: Bool, _ reason: String?) -> Void
    /// Diagnóstico, cada ~1 s. Sale del watchdog y no del tap, para que siga
    /// llegando aunque el tap haya muerto — que es cuando más hace falta.
    var onStats: (Stats) -> Void
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
  /// locks caros ahí adentro. `os_unfair_lock` tomado UNA vez por render sobre
  /// unas decenas de muestras es lo más barato que hay disponible sin escribir
  /// un lock-free a mano.
  ///
  /// Vive en un puntero y no en una propiedad porque `&self.lock` sobre una
  /// propiedad de clase viola la exclusividad de acceso de Swift.
  private let lock: UnsafeMutablePointer<os_unfair_lock> = {
    let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    p.initialize(to: os_unfair_lock())
    return p
  }()

  // ── Contadores (protegidos por `lock`) ────────────────────────────────────

  private var renderCalls = 0
  private var renderedSamples = 0
  private var captureCalls = 0
  /// `systemUptime` del último tap del micrófono. Es el pulso del motor.
  private var lastCaptureAt: TimeInterval = 0
  /// Cuándo arrancó (o rearrancó) el engine por última vez: el watchdog le da
  /// ese margen antes de reclamar taps.
  private var startedAt: TimeInterval = 0

  // ── Grafo ─────────────────────────────────────────────────────────────────

  private let engine = AVAudioEngine()
  private var sourceNode: AVAudioSourceNode?
  private var converter: AVAudioConverter?
  private var callbacks: Callbacks
  /// Hay una sesión tomada: el usuario pidió el audio y no lo soltó. NO dice
  /// que el motor esté corriendo — para eso está `engineRunning`.
  private var running = false
  /// El grafo está armado (aunque el engine esté parado por una interrupción o
  /// por un reset del sistema). Es lo que hace que `stop()` limpie SIEMPRE.
  private var configured = false
  /// Lo último que se le contó a la capa de arriba sobre el motor. Se emite
  /// sólo en los bordes (cambió el estado o el motivo), no en cada tick.
  private var reportedRunning = false
  private var reportedReason: String?
  private var lastRestartAt: TimeInterval = 0
  /// Entre `.began` y `.ended` de una interrupción: el sistema tiene el audio y
  /// el watchdog no debe pelearle la sesión.
  private var interrupted = false
  /// `mediaServicesWereReset`: TODO el engine quedó inválido y hay que crear
  /// otro (`PhoneAudioPlugin` lo hace en el reintento). Acá ya no se rearma.
  private var dead = false
  private var restarts = 0
  private var consecutiveFailures = 0
  private var muted = false
  private var speakerWanted = false
  private var watchdog: Timer?
  private var statsTick = 0

  /// Tasa de salida del mixer. Se lee al armar el grafo.
  private var renderRate: Double = 48000
  /// Paso del resampleo de bajada (8000 / renderRate) y posición fraccional.
  private var step: Double = PhoneAudioEngine.lineRate / 48000
  private var frac: Double = 0
  private var prevSample: Float = 0
  private var currSample: Float = 0

  /// Acumulador del uplink: el converter entrega bloques de tamaño arbitrario y
  /// la línea quiere frames exactos de 160 muestras.
  private var uplinkAcc = [Int16]()

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
  ///
  /// Que vuelva sin tirar significa que el engine ACEPTÓ arrancar; si iOS lo
  /// para en el acto (ver el encabezado del archivo), el watchdog lo ve en
  /// menos de dos segundos, lo rearma y lo cuenta.
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

    try buildGraph()
    try startEngine()

    running = true
    configured = true
    interrupted = false
    dead = false
    observeSystem()
    startWatchdog()
    applyOutputOverride()
    callbacks.onOutputChanged(currentOutput())
    report(running: true, reason: nil)
  }

  /// Arma el grafo sobre el `AVAudioEngine`. Idempotente: tira lo que hubiera.
  private func buildGraph() throws {
    tearDownGraph()

    let input = engine.inputNode
    // ESTO es lo que pone el Voice-Processing I/O debajo del grafo (iOS 13+):
    // cancelación de eco y supresión de ruido. Va ANTES de leer formatos y de
    // conectar nada, porque habilitarlo reinicializa el I/O y le cambia el
    // formato al nodo de entrada. Sólo se puede tocar con el engine parado.
    if !input.isVoiceProcessingEnabled {
      do {
        try input.setVoiceProcessingEnabled(true)
      } catch {
        // Sin AEC la llamada igual funciona con auriculares, así que no se
        // aborta: se avisa, y quien esté con el altavoz va a escuchar el eco y
        // va a saber por qué.
        callbacks.onFailure(
          "iOS no pudo activar la cancelación de eco: con el altavoz vas a escuchar eco."
        )
      }
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
  }

  private func tearDownGraph() {
    engine.inputNode.removeTap(onBus: 0)
    if let node = sourceNode {
      engine.detach(node)
      sourceNode = nil
    }
    converter = nil
  }

  private func startEngine() throws {
    engine.prepare()
    do {
      try engine.start()
    } catch {
      throw PhoneAudioError.message("No se pudo arrancar el audio: \(error.localizedDescription)")
    }
    let now = ProcessInfo.processInfo.systemUptime
    os_unfair_lock_lock(lock)
    startedAt = now
    lastCaptureAt = 0
    os_unfair_lock_unlock(lock)
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
    watchdog?.invalidate()
    watchdog = nil
    NotificationCenter.default.removeObserver(self)
    engine.stop()
    tearDownGraph()
    resetBuffer()
    // `.notifyOthersOnDeactivation` devuelve el audio a quien lo tenía antes
    // (la música que estaba sonando, por ejemplo). Sin esto, el resto del
    // sistema se queda mudo hasta que algo más reclame la sesión.
    try? AVAudioSession.sharedInstance().setActive(
      false, options: [.notifyOthersOnDeactivation])
  }

  // ── Recuperación ──────────────────────────────────────────────────────────

  /// ¿El motor está entregando audio AHORA? `isRunning` solo no alcanza: hay
  /// hardware donde el tap muere con el engine "corriendo". Recién arrancado
  /// se le da el margen de `captureStallSeconds` para el primer tap.
  var engineRunning: Bool {
    guard running, !dead, !interrupted, engine.isRunning else { return false }
    let now = ProcessInfo.processInfo.systemUptime
    os_unfair_lock_lock(lock)
    let last = lastCaptureAt
    let started = startedAt
    os_unfair_lock_unlock(lock)
    let since = now - max(last, started)
    return since < PhoneAudioEngine.captureStallSeconds
  }

  /// Rearma el grafo y vuelve a arrancar sobre la misma sesión. Es lo que hay
  /// que hacer tras un `AVAudioEngineConfigurationChange` (Apple: "los nodos
  /// siguen conectados con los formatos anteriores; la app debe rehacer las
  /// conexiones si los formatos cambiaron"), tras una interrupción, o cuando
  /// el tap dejó de entregar.
  ///
  /// Devuelve si arrancó. NO decide si vale la pena: eso lo hace quien llama.
  @discardableResult
  func restart(reason: String, manual: Bool = false) -> Bool {
    guard running, !dead else { return false }
    if manual { consecutiveFailures = 0 }
    engine.stop()
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: [])
      try buildGraph()
      try startEngine()
    } catch {
      consecutiveFailures += 1
      let text = (error as? PhoneAudioError)?.text ?? error.localizedDescription
      report(running: false, reason: "\(reason) \(text)")
      return false
    }
    restarts += 1
    interrupted = false
    applyOutputOverride()
    callbacks.onOutputChanged(currentOutput())
    // Se cuenta como recuperado recién cuando el watchdog vea taps: hasta
    // entonces `engineRunning` es true por el margen de arranque, y si el
    // motor vuelve a morir el próximo tick lo dice.
    report(running: true, reason: nil)
    return true
  }

  private func report(running isRunning: Bool, reason: String?) {
    if isRunning == reportedRunning && reason == reportedReason { return }
    reportedRunning = isRunning
    reportedReason = reason
    callbacks.onEngine(isRunning, reason)
  }

  // ── Watchdog ──────────────────────────────────────────────────────────────

  private func startWatchdog() {
    watchdog?.invalidate()
    statsTick = 0
    // 250 ms: seis ticks por `captureStallSeconds`, para que una parada se vea
    // en menos de dos segundos sin gastar CPU mirando un contador.
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.tick()
    }
    RunLoop.main.add(timer, forMode: .common)
    watchdog = timer
  }

  private func tick() {
    guard running else { return }
    statsTick += 1
    if statsTick >= 4 {
      statsTick = 0
      callbacks.onStats(snapshot())
    }
    guard !dead, !interrupted else { return }

    if engineRunning {
      // Un motor que entrega audio limpia la racha de fallas: los reinicios
      // acotados son por episodio, no por sesión.
      consecutiveFailures = 0
      report(running: true, reason: nil)
      return
    }

    let why = engine.isRunning
      ? "El micrófono del celular dejó de entregar audio."
      : "iOS detuvo el audio del celular."
    guard consecutiveFailures < PhoneAudioEngine.maxAutoRestarts else {
      report(running: false, reason: "\(why) Se reintentó \(consecutiveFailures) veces sin éxito.")
      return
    }
    report(running: false, reason: why)
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastRestartAt >= PhoneAudioEngine.restartSpacingSeconds else { return }
    lastRestartAt = now
    consecutiveFailures += 1
    restart(reason: why)
  }

  private func snapshot() -> Stats {
    os_unfair_lock_lock(lock)
    let stats = Stats(
      bufferedMs: Int(bufferedMsLocked()),
      dropped: droppedSamples,
      renderCalls: renderCalls,
      renderedSamples: renderedSamples,
      captureCalls: captureCalls,
      engineRunning: false,
      restarts: restarts)
    os_unfair_lock_unlock(lock)
    var out = stats
    out.engineRunning = engineRunning
    return out
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
  ///
  /// Toma el lock UNA vez por llamada (no por muestra): son unas decenas de
  /// muestras de línea por render y el otro lado del lock es un `memcpy` de
  /// 320 bytes, así que la espera es despreciable y el hilo de audio no
  /// martilla el lock 48.000 veces por segundo.
  private func render(frameCount: AVAudioFrameCount, into abl: UnsafeMutablePointer<AudioBufferList>) {
    let buffers = UnsafeMutableAudioBufferListPointer(abl)
    guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
    let frames = Int(frameCount)

    os_unfair_lock_lock(lock)
    renderCalls += 1
    if priming {
      os_unfair_lock_unlock(lock)
      // Todavía cebando: silencio. Un buffer a medio llenar se escucha peor que
      // un momento de nada.
      for i in 0..<frames { out[i] = 0 }
      fillSilence(buffers: buffers, frames: frames)
      return
    }

    var consumed = 0
    var i = 0
    while i < frames {
      var starved = false
      while frac >= 1 {
        guard queued > 0 else {
          starved = true
          break
        }
        prevSample = currSample
        currSample = Float(ring[readIndex]) / 32768.0
        readIndex = (readIndex + 1) % ring.count
        queued -= 1
        consumed += 1
        frac -= 1
      }
      if starved {
        // Underrun: se vuelve a cebar y lo que sale es silencio. Un hueco se
        // escucha mejor que un chasquido.
        priming = true
        break
      }
      out[i] = prevSample + (currSample - prevSample) * Float(frac)
      frac += step
      i += 1
    }
    renderedSamples += consumed
    os_unfair_lock_unlock(lock)

    if i < frames {
      for j in i..<frames { out[j] = 0 }
      fillSilence(buffers: buffers, frames: frames, from: i)
      return
    }
    // Mono a un grafo que puede pedir estéreo: se copia el mismo canal.
    mirrorChannels(buffers: buffers, frames: frames)
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

    // El pulso del motor: el watchdog mira esto, no `isRunning`.
    let now = ProcessInfo.processInfo.systemUptime
    os_unfair_lock_lock(lock)
    captureCalls += 1
    lastCaptureAt = now
    os_unfair_lock_unlock(lock)

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
    // "Cuando el I/O unit observa un cambio de canales o de tasa del hardware,
    // el engine se detiene solo y emite esta notificación" (AVAudioEngine.h).
    // Es LA forma en que el #12 quedaba mudo sin que nadie se enterara.
    center.addObserver(
      self, selector: #selector(handleConfigurationChange(_:)),
      name: .AVAudioEngineConfigurationChange, object: engine)
  }

  /// Llega en una cola interna del engine, y Apple advierte que ahí no se
  /// puede tumbar el engine. Se salta al hilo principal, donde vive todo lo
  /// demás, y se rearma el grafo con los formatos nuevos.
  @objc private func handleConfigurationChange(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.running, !self.dead, !self.interrupted else { return }
      self.report(running: false, reason: "iOS cambió la configuración del audio.")
      self.restart(reason: "iOS cambió la configuración del audio.")
    }
  }

  /// Una llamada telefónica DE VERDAD al celular, o Siri, o una alarma.
  ///
  /// En `.began` el sistema ya paró el engine: no hay nada que apagar, sólo que
  /// contarlo. En `.ended` se intenta volver SIEMPRE, mande o no el sistema
  /// `shouldResume`: es una llamada en curso y el usuario la quiere de vuelta;
  /// si iOS no deja, `setActive` tira y se cuenta como no recuperado, con la
  /// sesión viva para que un toque lo reintente. Lo que no puede pasar es
  /// quedar "prendido" sin audio.
  @objc private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.running else { return }
      if type == .began {
        self.interrupted = true
        self.resetBuffer()
        self.callbacks.onInterruption(true, false)
        self.report(running: false, reason: "El celular interrumpió el audio.")
        return
      }
      self.interrupted = false
      let resumed = self.restart(reason: "Al volver de la interrupción,", manual: true)
      self.callbacks.onInterruption(false, resumed)
    }
  }

  @objc private func handleRouteChange(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.running else { return }
      // Enchufar auriculares en medio de la llamada tiene que verse en la UI, y
      // desenchufarlos no puede dejar el override del altavoz colgado.
      self.applyOutputOverride()
      self.callbacks.onOutputChanged(self.currentOutput())
    }
  }

  /// El servidor de audio del sistema se reinició: TODO lo que hay armado quedó
  /// inválido, incluido este `AVAudioEngine`. No se rearma acá — se avisa, y el
  /// reintento (`PhoneAudioPlugin.restart`) crea un motor nuevo.
  @objc private func handleReset(_ note: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.dead = true
      self.report(running: false, reason: "El audio del sistema se reinició.")
    }
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
