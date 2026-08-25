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

/// Estado de la línea (`GET /api/phone/status`), recortado a lo que muestra la
/// app: sin dial pad, no necesita volumen ni ruteo de audio.
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

  const PhoneStatus({
    this.enabled = false,
    this.online = false,
    this.registered = false,
    this.operator,
    this.tech,
    this.signalBars = 0,
    this.lineActive = 'unknown',
    this.ownNumber,
  });

  factory PhoneStatus.fromJson(Map<String, dynamic> json) {
    final signal = json['signal'];
    return PhoneStatus(
      enabled: json['enabled'] == true,
      online: json['online'] == true,
      registered: json['registered'] == true,
      operator: json['operator'] as String?,
      tech: json['tech'] as String?,
      signalBars: signal is Map ? ((signal['bars'] as num?)?.toInt() ?? 0) : 0,
      lineActive: (json['lineActive'] ?? 'unknown').toString(),
      ownNumber: json['ownNumber'] as String?,
    );
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
}
