import 'package:flutter/material.dart';

import 'cce_tokens.dart';

/// ThemeData global de CCE Home.
///
/// Fija el contrato del sistema para todo lo que Material dibuja por su cuenta
/// (switches, sliders, chips, sheets): un solo acento, una sola familia de
/// superficies, sin relieve. Ver [CceColors] para la dirección de diseño.
abstract final class CceTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CceColors.accent,
      brightness: Brightness.dark,
      surface: CceColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: CceColors.bg,
      canvasColor: CceColors.bg,
      // Sin sombras: un ícono se distingue por color y trazo. El relieve
      // app-wide era lo que ensuciaba cada glyph (ver CceEmboss).
      iconTheme: const IconThemeData(
        color: CceColors.textSecondary,
        size: 22,
      ),
      dividerTheme: const DividerThemeData(
        color: CceColors.strokeSoft,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: CceColors.textPrimary,
        titleTextStyle: CceText.title,
        iconTheme: IconThemeData(
          color: CceColors.textSecondary,
          size: 22,
        ),
      ),
      // Nav y rail comparten el fondo del lienzo. Pintarlos de otro color
      // partía la pantalla en "mundo de la barra" y "mundo del contenido"; un
      // hairline alcanza para separarlos.
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: CceColors.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: CceColors.accentWash,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: const WidgetStatePropertyAll(CceText.label),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? CceColors.accent
                : CceColors.textTertiary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: CceColors.bg,
        useIndicator: true,
        indicatorColor: CceColors.accentWash,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: const IconThemeData(color: CceColors.accent),
        unselectedIconTheme: const IconThemeData(color: CceColors.textTertiary),
        selectedLabelTextStyle: CceText.label.copyWith(
          color: CceColors.textPrimary,
        ),
        unselectedLabelTextStyle: CceText.label.copyWith(
          color: CceColors.textTertiary,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: CceColors.accent,
        // El track vacío es un HUECO, no una superficie elevada.
        inactiveTrackColor: CceColors.surfaceSunken,
        thumbColor: CceColors.textPrimary,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        overlayColor: CceColors.accentWash,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CceColors.surface,
        modalBackgroundColor: CceColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CceRadii.sheet),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        // Apagado: thumb atenuado sobre hueco. Encendido: thumb claro sobre
        // ámbar. El estado se lee por VALOR (claro/oscuro), no sólo por color
        // — sirve igual con poca luz y con daltonismo.
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CceColors.textPrimary
              : CceColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CceColors.accent
              : CceColors.surfaceSunken,
        ),
        // Un switch apagado DEBE verse: sin este borde se funde con la card y
        // parece que no hay control.
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : CceColors.strokeStrong,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CceColors.surfaceHigh,
        selectedColor: CceColors.accentWash,
        labelStyle: CceText.label,
        side: const BorderSide(color: CceColors.stroke),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CceColors.surfaceHigh,
        contentTextStyle: CceText.body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CceRadii.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CceColors.surfaceHigh,
        labelStyle: const TextStyle(color: CceColors.textTertiary),
        hintStyle: const TextStyle(color: Color(0x3DFFFFFF)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CceRadii.control),
          borderSide: BorderSide.none,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CceColors.accent,
      ),
    );
  }
}
