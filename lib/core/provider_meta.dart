import 'dart:ui' show Color;

/// Metadatos de proveedor (label + color de marca + naturaleza) en UN solo
/// lugar — espejo de `src/app/core/provider-meta.ts` del Dashboard.
///
/// Por qué existe: la app repetía la raíz del bug del Dashboard — la identidad
/// de cada proveedor (nombre visible, color, si es módulo dedicado) vivía
/// desperdigada en widgets sueltos, y un proveedor nuevo quedaba con badge
/// lindo en una pantalla y texto crudo en la de al lado. Labels y colores NO
/// son un rediseño: son los MISMOS que consolidó el Dashboard.
///
/// OJO: usar SIEMPRE [providerMeta], que trae fallback — por bindings llegan
/// providers que no están en el mapa y un lookup directo daría null.
enum ProviderKind {
  /// Sirve el device y rutea comandos.
  binding,

  /// Módulo dedicado de CCE (un solo aparato, panel propio: TV, JBL).
  module,

  /// NO sirve el device — le suma datos a uno que entra por otro proveedor.
  /// Nunca puede ser el binding preferido.
  enricher,
}

class ProviderMeta {
  /// Nombre para mostrar (el que ve el usuario, no el id).
  final String label;

  /// Color de marca, para chips/bordes/badges.
  final Color brand;

  final ProviderKind kind;

  const ProviderMeta({
    required this.label,
    required this.brand,
    required this.kind,
  });
}

/// provider id → metadatos. Para íconos NO hay assets nuevos: los vendoreados
/// ya cubren las marcas (CceIcons.samsung / CceIcons.jbl en theme/cce_icons.dart,
/// HueBadge en theme/components/hue_badge.dart, Mdi.television / Mdi.speaker).
const Map<String, ProviderMeta> kProviderMeta = {
  'hue': ProviderMeta(
      label: 'Philips Hue', brand: Color(0xFFFF6900), kind: ProviderKind.binding),
  'tuya': ProviderMeta(
      label: 'Tuya', brand: Color(0xFFFF4800), kind: ProviderKind.binding),
  'ewelink': ProviderMeta(
      label: 'Sonoff / eWeLink',
      brand: Color(0xFFFF9800),
      kind: ProviderKind.binding),
  'matter': ProviderMeta(
      label: 'Matter', brand: Color(0xFF00B0B9), kind: ProviderKind.binding),
  'z2m': ProviderMeta(
      label: 'Zigbee2MQTT', brand: Color(0xFF00897B), kind: ProviderKind.binding),
  'zigbee2mqtt': ProviderMeta(
      label: 'Zigbee2MQTT', brand: Color(0xFF00897B), kind: ProviderKind.binding),
  'ezviz': ProviderMeta(
      label: 'EZVIZ', brand: Color(0xFF0096FF), kind: ProviderKind.binding),
  'smartthings': ProviderMeta(
      label: 'SmartThings', brand: Color(0xFF15BFFF), kind: ProviderKind.binding),
  'alarm': ProviderMeta(
      label: 'Alarma', brand: Color(0xFFE53935), kind: ProviderKind.binding),
  'jbl': ProviderMeta(
      label: 'JBL', brand: Color(0xFFFF6A00), kind: ProviderKind.module),
  'tv': ProviderMeta(
      label: 'Samsung TV', brand: Color(0xFF1428A0), kind: ProviderKind.module),
  'samsung': ProviderMeta(
      label: 'Samsung TV', brand: Color(0xFF1428A0), kind: ProviderKind.module),
  // Roborock NO tiene binding: enriquece al robot que entra por Matter.
  'roborock': ProviderMeta(
      label: 'Roborock', brand: Color(0xFF00A0E9), kind: ProviderKind.enricher),
};

/// Metadatos con fallback: un provider desconocido se muestra por su id, con
/// gris neutro — no explota ni desaparece.
ProviderMeta providerMeta(String p) =>
    kProviderMeta[p] ??
    ProviderMeta(label: p, brand: const Color(0xFF9E9E9E), kind: ProviderKind.binding);

/// Label para mostrar. Atajo del caso más común.
String providerLabel(String p) => providerMeta(p).label;

/// ¿Es un enricher (no rutea comandos)? Decide si puede ofrecerse como binding.
bool isEnricherProvider(String p) => providerMeta(p).kind == ProviderKind.enricher;
