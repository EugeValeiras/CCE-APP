/// Modelos de la cerradura EZVIZ (provider ezviz). Espejo fiel de los DTOs del
/// backend que consume el dashboard (ezviz-api.service.ts):
///   GET  /ezviz/devices/:serial/status -> EzvizLockStatus
///   GET  /ezviz/devices/:serial/events -> EzvizLockEvent[]
///   POST /ezviz/devices/:serial/unlock -> EzvizUnlockResponse (501 -> supported:false)
///
/// Igual que jbl_status / tv_status, NO dependen de Flutter (solo dart:core):
/// la vista convierte battery/colores; estos modelos son data pura con fromJson.

/// Estado vivo de la cerradura (← GET /ezviz/devices/:serial/status,
/// EzvizDeviceStatusDto del backend). Convención de estado del diseño:
/// `isLocked` = trabada, `online` = alcanzable, `battery` = porcentaje string.
class EzvizLockStatus {
  /// true = online (alcanzable).
  final bool online;

  /// true = trabada (locked). Default trabada por seguridad si no se sabe.
  final bool isLocked;

  /// Porcentaje de batería como string crudo del backend (ej. '85' o '85%');
  /// la vista lo parsea/normaliza. Puede venir null.
  final String? battery;

  const EzvizLockStatus({
    this.online = false,
    this.isLocked = true,
    this.battery,
  });

  factory EzvizLockStatus.fromJson(Map<String, dynamic> json) {
    // El backend manda `isOnline`; toleramos también `online` por las dudas.
    final onlineRaw = json['isOnline'] ?? json['online'];
    final batteryRaw = json['battery'];
    return EzvizLockStatus(
      online: onlineRaw == true,
      isLocked: json['isLocked'] == true,
      battery: batteryRaw == null ? null : batteryRaw.toString(),
    );
  }
}

/// Un evento de historial de la cerradura (← items de GET
/// /ezviz/devices/:serial/events, EzvizEventDto del backend). `at` es el
/// timestamp del evento (ms epoch); `kind` es la categoría normalizada por el
/// backend ('open' | 'unlock' | 'lock' | 'doorbell' | 'attempt' | 'ajar' |
/// 'other'); `message`/`actor` son el texto humano y quién lo disparó.
class EzvizLockEvent {
  /// Id único del evento (track / dedupe).
  final String id;

  /// Timestamp del evento (ms epoch). 0 si el backend no lo informó.
  final int at;

  /// Categoría normalizada del evento ('open'/'unlock'/'lock'/'doorbell'/...).
  final String kind;

  /// Mensaje humano completo de EZVIZ (ej. "X unlocked the door with
  /// fingerprint"); la vista lo prioriza para el label.
  final String? message;

  /// Quién disparó el evento (showHumanName), ej. "Eugenio Valeiras".
  final String? actor;

  const EzvizLockEvent({
    required this.id,
    required this.at,
    required this.kind,
    this.message,
    this.actor,
  });

  factory EzvizLockEvent.fromJson(Map<String, dynamic> json) {
    return EzvizLockEvent(
      id: (json['alarmId'] ?? json['id'] ?? '').toString(),
      at: (json['alarmTime'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] ?? 'other').toString(),
      message: json['message'] as String?,
      actor: json['actor'] as String?,
    );
  }
}

/// Respuesta de POST /ezviz/devices/:serial/unlock. 200 -> {success, ts};
/// 501 (modelo sin apertura remota) -> mapeado por ApiService a
/// `supported:false`. `reason` trae el motivo legible cuando no se pudo.
class EzvizUnlockResponse {
  final bool success;

  /// false cuando el modelo de cerradura no soporta apertura remota (501).
  /// null = soportado/no informado (asumimos soportado).
  final bool? supported;

  /// Motivo legible del fallo / del no-soportado.
  final String? reason;

  /// ISO timestamp del intento exitoso (devuelto por el backend en éxito).
  final String? ts;

  const EzvizUnlockResponse({
    required this.success,
    this.supported,
    this.reason,
    this.ts,
  });

  factory EzvizUnlockResponse.fromJson(Map<String, dynamic> json) {
    return EzvizUnlockResponse(
      success: json['success'] == true,
      supported: json['supported'] is bool ? json['supported'] as bool : null,
      reason: (json['reason'] ?? json['error']) as String?,
      ts: json['ts'] as String?,
    );
  }
}
