import 'package:flutter/material.dart';

import 'cce_icons.dart'; // CceEmboss: tokens del relieve neumorfico
import 'cce_tokens.dart';

/// ThemeData global del rebranding estilo Hue.
abstract final class CceTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CceColors.accent,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: CceColors.bg,
      canvasColor: CceColors.bg,
      // Relieve neumorfico app-wide para TODO Icon(Icons.*)/Icon(Mdi.*)
      // que no fije shadows propios (Icon usa `widget.shadows ?? iconTheme`).
      // Mismos tokens que el ghost de CceIcon -> Material y SVG convergen.
      iconTheme: const IconThemeData(
        color: CceColors.textSecondary,
        shadows: CceEmboss.iconShadows,
      ),
      dividerTheme: const DividerThemeData(
        color: CceColors.stroke,
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
          shadows: CceEmboss.iconShadows,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: CceColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: CceColors.accent.withValues(alpha: 0.24),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: const WidgetStatePropertyAll(CceText.caption),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? CceColors.textPrimary
                : CceColors.textTertiary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: CceColors.surface,
        useIndicator: true,
        indicatorColor: CceColors.accent.withValues(alpha: 0.24),
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: const IconThemeData(color: CceColors.textPrimary),
        unselectedIconTheme: const IconThemeData(color: CceColors.textTertiary),
        selectedLabelTextStyle: CceText.caption.copyWith(
          color: CceColors.textPrimary,
        ),
        unselectedLabelTextStyle: CceText.caption.copyWith(
          color: CceColors.textTertiary,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: CceColors.accent,
        inactiveTrackColor: CceColors.surfaceHigh,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        overlayColor: CceColors.accent.withValues(alpha: 0.12),
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
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CceColors.accent
              : CceColors.surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CceColors.surfaceHigh,
        selectedColor: CceColors.accent.withValues(alpha: 0.28),
        labelStyle: CceText.caption,
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
