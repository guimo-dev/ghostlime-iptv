import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// App palette (dark, TV-friendly). See the redesign spec.
abstract final class AppColors {
  static const background = Color(0xFF0D0E15);
  static const surface = Color(0xFF14151F);
  static const surfaceHigh = Color(0xFF1C1E2A);
  static const surfaceHighest = Color(0xFF282B38);
  static const accent = Color(0xFFC6F432);
  static const accentAlt = Color(0xFF8FD400);
  static const onAccent = Color(0xFF14151F);
  static const text = Color(0xFFF2F3F7);
  static const textMuted = Color(0xFF9AA0B4);
  static const danger = Color(0xFFFF6B6B);
  static const live = Color(0xFFFF4D5E);
  static const selected = Color(0xFF2A3122);
  static const border = Color(0x14FFFFFF);

  /// Off-state switch track: at least 3:1 against every surface.
  static const switchTrackOff = Color(0xFF656A80);
}

/// Shared gradients and shadows.
abstract final class AppStyle {
  /// Lime → dark lime accent, for highlights and progress.
  static const accentGradient = LinearGradient(
    colors: [AppColors.accent, AppColors.accentAlt],
  );

  /// Soft glow under a focused card.
  static final List<BoxShadow> focusGlow = [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.45),
      blurRadius: 24,
      spreadRadius: 1,
    ),
  ];

  /// Depth for resting cards and posters.
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Windows ships a modern variable font; elsewhere use the platform default.
String? get _fontFamily =>
    Platform.isWindows ? 'Segoe UI Variable Display' : null;

/// Fonts tried when [_fontFamily] lacks a glyph: Windows' colour emoji, so
/// channel names with emoji do not show empty boxes.
List<String>? get _fontFamilyFallback =>
    Platform.isWindows ? const ['Segoe UI Emoji'] : null;

/// Builds the app-wide dark theme.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHighest,
    primaryContainer: AppColors.selected,
    onPrimaryContainer: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.surfaceHighest,
    outlineVariant: AppColors.surfaceHighest,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFamilyFallback,
  );
  final text = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    focusColor: AppColors.accent.withValues(alpha: 0.18),
    hoverColor: Colors.white.withValues(alpha: 0.05),
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      selectedColor: AppColors.accent,
      // Dark text on the lime selected chip, light text otherwise. The chip
      // only resolves states through the colour, not the whole style.
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.text,
        ),
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: AppColors.onAccent,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.04),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.text,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      ),
    ),
    // Primary actions are lime pills, like modern TV apps; focus adds glow.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: const BorderSide(color: AppColors.border),
        foregroundColor: AppColors.text,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHighest,
      isDense: true,
      // Underline borders have no notch, so the floating label sits inside
      // the filled box instead of straddling its top edge.
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHighest,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      selectedColor: AppColors.text,
      selectedTileColor: AppColors.selected,
      iconColor: AppColors.textMuted,
    ),
    // The default off switch is dark on dark; give track and thumb contrast.
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.switchTrackOff,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.onAccent
            : AppColors.text,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.surfaceHighest,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.surfaceHighest),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: AppColors.text),
    ),
  );
}
