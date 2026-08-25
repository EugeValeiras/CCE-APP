/// Modelos de la telefonía 4G (HAT SIM7600G-H). Modelo PURO (sin Flutter) para
/// poder testear el parseo standalone, como featured_item.dart.
///
/// Espejo del backend: `GET /api/phone/calls` y el socket `phone:call-state`.
library;

/// Cómo terminó una llamada.
///
/// `notConnected` es el caso delicado: el módem NO distingue una llamada
/// rechazada por la red (que manda su anuncio como early media, sin conectar
/// formalmente) de una que nadie atendió — las dos llegan como `NO CARRIER`
/// sin `VOICE CALL: BEGIN`. La app tampoco lo afirma: dice "No contestaron".
enum CallResult { answered, missed, rejected, notConnected, failed }

CallResult _parseResult(String? raw) {
  switch (raw) {
    case 'answered':
      return CallResult.answered;
    case 'missed':
      return CallResult.missed;
    case 'rejected':
      return CallResult.rejected;
    case 'not-connected':
      return CallResult.notConnected;
    default:
      return CallResult.failed;
  }
}

/// Una llamada del historial.
class PhoneCall {
  /// true = entrante.
  final bool incoming;
  final String number;
  final String? contactId;
  final String? contactName;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final Duration duration;
  final CallResult result;

  /// Causa cruda del módem cuando no prosperó (`+CEER` o el URC).
  final String? cause;

  /// Quién cortó: 'local' = lo hizo la casa (rechazo, o ring-and-hangup de una
  /// automatización). Es lo que distingue "sonó y se cortó" de "no contestaron".
  final String? hangupBy;

  const PhoneCall({
    required this.incoming,
    required this.number,
    required this.startedAt,
    required this.duration,
    required this.result,
    this.contactId,
    this.contactName,
    this.connectedAt,
    this.cause,
    this.hangupBy,
  });

  /// Quién es del otro lado: el nombre del contacto si se conoce, el número si
  /// no, y un texto explícito si la llamada llegó SIN caller ID (que no es lo
  /// mismo que un número que no está en la libreta).
  String get displayName {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return number.trim().isEmpty ? 'Número desconocido' : number;
  }

  bool get isMissed => result == CallResult.missed;

  factory PhoneCall.fromJson(Map<String, dynamic> json) {
    final started = (json['startedAt'] as num?)?.toInt();
    final connected = (json['connectedAt'] as num?)?.toInt();
    return PhoneCall(
      incoming: json['direction'] == 'in',
      number: (json['number'] ?? '').toString(),
      contactId: json['contactId'] as String?,
      contactName: json['contactName'] as String?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started ?? 0),
      connectedAt: connected == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(connected),
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      result: _parseResult(json['result'] as String?),
      cause: json['cause'] as String?,
      hangupBy: json['hangupBy'] as String?,
    );
  }

  /// Etiqueta del resultado, en el idioma de la app.
  String get resultLabel {
    switch (result) {
      case CallResult.answered:
        return incoming ? 'Atendida' : 'Contestaron';
      case CallResult.missed:
        return 'Perdida';
      case CallResult.rejected:
        return 'Rechazada';
      case CallResult.notConnected:
        // Cortada por nosotros = el ring-and-hangup de una automatización: la
        // llamada perdida ERA el aviso, no un fracaso.
        return hangupBy == 'local' ? 'Sonó y se cortó' : 'No contestaron';
      case CallResult.failed:
        return cause != null && cause!.isNotEmpty ? 'Falló ($cause)' : 'Falló';
    }
  }
}

/// Por dónde sale la voz de una llamada.
///
/// Hasta el issue #10 la respuesta era siempre "en la casa". Desde el #12 el
/// celular también puede llevarla: `web` dejó de significar "el navegador" y
/// pasa a significar **PCM sobre USB**, con el cliente que lo tomó del otro
/// lado — el dashboard o la app. Quién lo tiene lo dice [PhoneStatus.audioClient].
///
/// Sigue siendo la aclaración central de la pantalla del teléfono: mientras el
/// audio NO esté en este celular, hay que decirlo, o el usuario que disca y no
/// escucha nada asume que la app está rota.
enum AudioRoute {
  /// Jack del HAT: se escucha por el parlante/auricular enchufado en la casa.
  headset,

  /// Parlante del HAT (manos libres), también en la casa.
  speaker,

  /// PCM sobre USB: se lo lleva quien haya tomado la sesión de audio.
  web,

  /// El backend no lo informó.
  unknown,
}

/// Quién tiene tomado el audio remoto (`webAudio.client` de `/phone/status`).
enum AudioClient {
  /// Una pestaña del dashboard.
  dashboard,

  /// La app de un celular. Puede ser ESTE o puede ser otro.
  app,

  /// Alguien que no se identificó en el handshake del WebSocket.
  other,
}

AudioClient? _parseAudioClient(dynamic raw) {
  switch (raw) {
    case 'dashboard':
      return AudioClient.dashboard;
    case 'app':
      return AudioClient.app;
    case 'desconocido':
      return AudioClient.other;
    default:
      return null;
  }
}

AudioRoute _parseAudioRoute(String? raw) {
  switch (raw) {
    case 'headset':
      return AudioRoute.headset;
    case 'speaker':
      return AudioRoute.speaker;
    case 'web':
      return AudioRoute.web;
    default:
      return AudioRoute.unknown;
  }
}

/// Un contacto de la libreta del backend (`GET /api/phone/contacts`). El ABM es
/// del dashboard: acá sólo se disca desde la libreta.
class PhoneContact {
  final String id;
  final String name;
  final String number;

  const PhoneContact({
    required this.id,
    required this.name,
    required this.number,
  });

  /// Qué mostrar cuando el contacto vino sin nombre (no debería, pero el
  /// backend no lo garantiza): antes el número que una fila en blanco.
  String get displayName => name.trim().isEmpty ? number : name;

  factory PhoneContact.fromJson(Map<String, dynamic> json) => PhoneContact(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        number: (json['number'] ?? '').toString(),
      );
}

/// Rechazo del backend a un comando de telefonía.
///
/// Los POST de `/phone/*` contestan **201 con `{ success: false, reason }`**:
/// el código HTTP no alcanza para saber si salió. El `reason` viene redactado
/// para leerse tal cual ("hay una llamada en curso", "rate limit de llamadas
/// por hora alcanzado") y la app lo muestra sin reemplazarlo por un genérico:
/// es la diferencia entre "no funciona" y "no podés llamar hasta dentro de un
/// rato".
class PhoneCommandException implements Exception {
  final String reason;
  const PhoneCommandException(this.reason);

  @override
  String toString() => reason;
}

/// Estado de la línea (`GET /api/phone/status`), recortado a lo que muestra la
/// app.
class PhoneStatus {
  final bool enabled;

  /// El módem responde por el puerto AT.
  final bool online;

  /// Registrado en la red. OJO: registrado ≠ operativo, ver [lineActive].
  final bool registered;
  final String? operator;
  final String? tech;

  /// 0-5.
  final int signalBars;

  /// 'active' | 'inactive' | 'unknown'. Vale 'unknown' hasta que el backend
  /// haga la consulta USSD: una línea sin habilitar se registra igual y
  /// reporta todo en verde, así que esto NO se deriva del registro.
  final String lineActive;

  /// Número propio, en E.164. Se carga a mano en el backend: el chip no lo
  /// sabe (`AT+CNUM` vuelve vacío). Es el número que aparece en tu celular
  /// cuando la casa te llama.
  final String? ownNumber;

  /// Saldo de la línea, ya formateado por el backend a partir de la respuesta
  /// USSD del operador. `null` mientras no se haya consultado — que es el
  /// estado normal al abrir la app, porque consultarlo es tráfico de red.
  final String? balance;

  /// Por dónde sale la voz. Ver [AudioRoute].
  final AudioRoute audioRoute;

  /// Quién tiene tomado el audio remoto, o `null` si no lo tiene nadie.
  ///
  /// Con `audioRoute == web` y esto en `null`, el ruteo es una PREFERENCIA sin
  /// nadie del otro lado: la voz sale igual por el jack de la casa. Es la
  /// diferencia entre "el audio está en el dashboard" y "el audio no está en
  /// ningún lado", que desde afuera se veían iguales.
  final AudioClient? audioClient;

  /// ¿Hay una sesión de audio remoto tomada ahora mismo?
  final bool audioSessionActive;

  /// Estado de la llamada en curso según `/status` ('idle' | 'dialing' |
  /// 'ringing' | 'active' | 'ended'). El estado EN VIVO llega por
  /// `device:state-changed`; esto es sólo el seed.
  final String callState;

  /// Llamadas cursadas en la última hora y tope del backend. Discar cuesta
  /// plata: cuando el margen se achica la pantalla lo dice ANTES de que el
  /// rate limit corte.
  final int callsLastHour;
  final int maxCallsPerHour;

  const PhoneStatus({
    this.enabled = false,
    this.online = false,
    this.registered = false,
    this.operator,
    this.tech,
    this.signalBars = 0,
    this.lineActive = 'unknown',
    this.ownNumber,
    this.balance,
    this.audioRoute = AudioRoute.unknown,
    this.audioClient,
    this.audioSessionActive = false,
    this.callState = 'idle',
    this.callsLastHour = 0,
    this.maxCallsPerHour = 0,
  });

  factory PhoneStatus.fromJson(Map<String, dynamic> json) {
    final signal = json['signal'];
    final call = json['call'];
    final webAudio = json['webAudio'];
    return PhoneStatus(
      enabled: json['enabled'] == true,
      online: json['online'] == true,
      registered: json['registered'] == true,
      operator: json['operator'] as String?,
      tech: json['tech'] as String?,
      signalBars: signal is Map ? ((signal['bars'] as num?)?.toInt() ?? 0) : 0,
      lineActive: (json['lineActive'] ?? 'unknown').toString(),
      ownNumber: json['ownNumber'] as String?,
      balance: _balanceText(json['balance']),
      audioRoute: _parseAudioRoute(json['audioRoute'] as String?),
      audioClient:
          webAudio is Map ? _parseAudioClient(webAudio['client']) : null,
      audioSessionActive:
          webAudio is Map && webAudio['sessionActive'] == true,
      callState: call is Map ? (call['state'] ?? 'idle').toString() : 'idle',
      callsLastHour: (json['callsLastHour'] as num?)?.toInt() ?? 0,
      maxCallsPerHour: (json['maxCallsPerHour'] as num?)?.toInt() ?? 0,
    );
  }

  /// El saldo llega del operador, no de un schema nuestro: puede venir como
  /// texto ya armado, como número, o como objeto con el texto adentro. Se
  /// normaliza a String y se descarta lo vacío, que es lo mismo que no tenerlo.
  static String? _balanceText(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw.trim().isEmpty ? null : raw.trim();
    if (raw is num) return raw.toString();
    if (raw is Map) {
      final text = raw['text'] ?? raw['formatted'] ?? raw['amount'];
      return text == null ? null : _balanceText(text.toString());
    }
    return null;
  }

  /// Texto corto del estado de la línea para la card y el header.
  String get lineLabel {
    if (!enabled) return 'Deshabilitado';
    if (!online) return 'Módem no disponible';
    if (!registered) return 'Sin red';
    switch (lineActive) {
      case 'active':
        return operator ?? 'Línea activa';
      case 'inactive':
        return 'Línea inactiva';
      default:
        // Registrado pero sin confirmar que curse tráfico. No se dice "OK":
        // ese es exactamente el error que costó un diagnóstico entero.
        return operator ?? 'Registrado';
    }
  }

  /// Dónde suena la voz, en una línea. Va SIEMPRE acompañado de
  /// [audioNotice] mientras el audio no esté en este celular: sin la
  /// aclaración, decir "parlante" invita a pensar que es el del celular.
  String get audioRouteLabel {
    switch (audioRoute) {
      case AudioRoute.headset:
        return 'Auricular del teléfono, en la casa';
      case AudioRoute.speaker:
        return 'Parlante del teléfono, en la casa';
      case AudioRoute.web:
        switch (audioClient) {
          case AudioClient.app:
            return 'Lo tomó la app de un celular';
          case AudioClient.dashboard:
            return 'Navegador: lo tomó el dashboard';
          case AudioClient.other:
            return 'Lo tomó otro dispositivo';
          case null:
            // El ruteo 'web' es una preferencia: sin nadie conectado la voz
            // sale igual por el jack. Decir "lo tomó el dashboard" acá sería
            // mandar al usuario a buscar un audio que no está en ningún lado.
            return 'Nadie tomó el audio: suena en el teléfono de la casa';
        }
      case AudioRoute.unknown:
        return 'Ruteo de audio sin determinar';
    }
  }

  /// El aviso, sin letra chica: por este celular no se escucha ni se habla.
  ///
  /// Vale mientras el audio **no** esté tomado por esta app. Cuando sí lo está,
  /// la pantalla muestra lo contrario (ver `AudioRouteNotice.onThisPhone`): el
  /// aviso dejaría de ser cierto y sería el peor de los mensajes posibles.
  String get audioNotice {
    switch (audioRoute) {
      case AudioRoute.headset:
      case AudioRoute.speaker:
        return 'Por el celular no vas a escuchar ni hablar: el audio sale por '
            'el teléfono de la casa.';
      case AudioRoute.web:
        switch (audioClient) {
          case AudioClient.app:
            return 'Por el celular no vas a escuchar ni hablar: el audio lo '
                'tiene la app en otro dispositivo.';
          case AudioClient.dashboard:
            return 'Por el celular no vas a escuchar ni hablar: el audio lo '
                'tiene el dashboard en el navegador.';
          case AudioClient.other:
            return 'Por el celular no vas a escuchar ni hablar: el audio lo '
                'tomó otro dispositivo.';
          case null:
            return 'Por el celular no vas a escuchar ni hablar: el audio se '
                'queda en la casa.';
        }
      case AudioRoute.unknown:
        return 'Por el celular no vas a escuchar ni hablar: el audio se queda '
            'en la casa.';
    }
  }

  /// ¿Conviene avisar del rate limit? Recién cuando queda poco margen: un
  /// contador permanente es ruido, y uno que aparece a los 80 es un aviso.
  bool get rateLimitNear =>
      maxCallsPerHour > 0 && callsLastHour >= (maxCallsPerHour * 0.8).floor();

  String get rateLimitLabel =>
      '$callsLastHour de $maxCallsPerHour llamadas en la última hora';
}
