import 'package:flutter/material.dart';

import '../cce_tokens.dart';

/// Encabezado de sección: título en mayúsculas con tracking ancho y un
/// trailing opcional a la derecha.
///
/// El espaciado es asimétrico A PROPÓSITO y es la única asimetría permitida
/// del sistema: un encabezado pertenece a lo que viene DEBAJO, así que respira
/// mucho arriba (xl) y poco abajo (md). Con padding simétrico, el título flota
/// entre dos grupos sin decir a cuál pertenece.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    // = (CceSpace.xs, CceSpace.xl, CceSpace.xs, CceSpace.md). Literal para
    // que el constructor siga siendo const en sus call sites.
    this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 12),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: CceText.section,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
