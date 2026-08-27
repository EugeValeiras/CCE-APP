/// Un SMS recibido en la línea de la casa (CCE#23). Modelo PURO, como
/// [PhoneCall]: espejo de `GET /api/phone/sms` y del socket `phone:sms`.
///
/// El backend ya lo entrega decodificado (modo PDU: tildes, ñ y emoji vienen
/// bien) y reensamblado si era largo (`parts` > 1). Acá no se parsea nada
/// del módem: sólo se lee el JSON.
library;

class PhoneSms {
  /// Id del backend (UUID). Es la clave para no duplicar un mensaje que llega
  /// por el socket y después otra vez por el `GET` tras reconectar.
  final String id;

  /// Remitente: `+549...`, dígitos pelados, o un NOMBRE cuando el remitente
  /// es alfanumérico ("Personal"). En ese caso no es discable.
  final String number;
  final String? contactId;
  final String? contactName;
  final String text;

  /// Hora de la RED (la del centro de mensajes). Es la buena para ordenar:
  /// la Pi no tiene reloj propio y al arrancar cree que es 1970.
  final DateTime? sentAt;

  /// Cuándo lo leyó la casa del módem.
  final DateTime receivedAt;

  /// Segmentos que lo componen: 1 para un SMS común, N si era largo.
  final int parts;

  const PhoneSms({
    required this.id,
    required this.number,
    required this.text,
    required this.receivedAt,
    this.contactId,
    this.contactName,
    this.sentAt,
    this.parts = 1,
  });

  /// Quién lo mandó: el nombre del contacto si el backend lo resolvió, si no
  /// el número (o el nombre alfanumérico), y un texto explícito si no vino.
  String get displayName {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return number.trim().isEmpty ? 'Remitente desconocido' : number;
  }

  /// Un remitente que parece un número de teléfono (y no "Personal").
  bool get hasDialableNumber => RegExp(r'^\+?\d{4,}$').hasMatch(number.trim());

  /// La fecha que se muestra y por la que se ordena.
  DateTime get when => sentAt ?? receivedAt;

  factory PhoneSms.fromJson(Map<String, dynamic> json) {
    final sent = (json['sentAt'] as num?)?.toInt();
    final received = (json['receivedAt'] as num?)?.toInt();
    return PhoneSms(
      id: (json['id'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      contactId: json['contactId'] as String?,
      contactName: json['contactName'] as String?,
      text: (json['text'] ?? '').toString(),
      sentAt: sent == null ? null : DateTime.fromMillisecondsSinceEpoch(sent),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(received ?? sent ?? 0),
      parts: (json['parts'] as num?)?.toInt() ?? 1,
    );
  }
}
