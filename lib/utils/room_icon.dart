import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/room_ref.dart';
import '../services/devices_service.dart';
import '../theme/cce_icons.dart';
import 'icon_resolver.dart';

/// Glyph de la habitación, resuelto con la MISMA lógica que el dashboard:
/// respeta el `iconName` configurado sea emoji (`💻`), id `icons0:<prefix>:<name>`
/// con SVG vendoreado, o nombre MDI; si no hay icono configurado (o la sala no
/// tiene un device representativo) cae al genérico de sala.
///
/// Devuelve un *builder por color* — no un Widget fijo — porque el glyph se
/// tinta según el estado de la card (`EmbossedGlyph` recolorea vía IconTheme,
/// pero un `SvgPicture` de icons0 NO lee IconTheme: hay que hornearle el color).
/// Mismo patrón que las light tiles (`iconBuilder`). Para headers planos se
/// invoca con un color fijo: `roomGlyphBuilder(room, service)(CceColors.textPrimary)`.
Widget Function(Color) roomGlyphBuilder(
  RoomRef room,
  DevicesService service, {
  double size = 32,
}) {
  final cfg = room.iconName;
  final rep =
      room.deviceIds.map(service.byId).whereType<Device>().firstOrNull;
  if (cfg != null && cfg.isNotEmpty && rep != null) {
    return (Color color) => IconResolver.widget(
          rep,
          configuredIcon: cfg,
          customIcons: service.customIcons,
          displayName: room.name,
          size: size,
          color: color,
        );
  }
  // Sin icono configurado → genérico de sala (sofá), idéntico al fallback previo.
  return (Color _) => CceIcon(CceIcons.room, size: size);
}
