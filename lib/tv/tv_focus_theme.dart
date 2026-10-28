import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

/// Width of the focus ring, like the border of a focused `FocusCard`.
const _ringWidth = 3.0;

/// Strong tint for the focus where a widget only has an overlay (the halo
/// of a slider or checkbox, a list tile).
const _strongFocusAlpha = 0.35;

/// [theme] with a clear focus on every Material control, for a TV driven
/// with a remote: an accent ring on buttons (a light one on the accent
/// filled buttons, where an accent ring would not show), a ring on chips,
/// switches and checkboxes, and a strong tint where only an overlay exists
/// (sliders, list tiles). Other devices keep [theme] as it is.
ThemeData withTvFocus(ThemeData theme) {
  final accent = theme.colorScheme.primary;
  final strong = accent.withValues(alpha: _strongFocusAlpha);
  final accentRing = BorderSide(color: accent, width: _ringWidth);
  const lightRing = BorderSide(color: AppColors.text, width: _ringWidth);
  return theme.copyWith(
    // Used by list tiles and plain InkWells (FocusCard sets its own).
    focusColor: strong,
    filledButtonTheme: FilledButtonThemeData(
      style: _withFocusRing(theme.filledButtonTheme.style, lightRing),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _withFocusRing(theme.outlinedButtonTheme.style, accentRing),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _withFocusRing(theme.textButtonTheme.style, accentRing),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _withFocusRing(theme.iconButtonTheme.style, accentRing),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _withFocusRing(theme.segmentedButtonTheme.style, lightRing),
      selectedIcon: theme.segmentedButtonTheme.selectedIcon,
    ),
    chipTheme: theme.chipTheme.copyWith(
      side: _focusedSide(
        theme.chipTheme.side,
        const BorderSide(
          color: AppColors.text,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        // A flat chip's own border when unselected.
        idle: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    ),
    switchTheme: theme.switchTheme.copyWith(
      trackOutlineColor: _whenFocused(
        AppColors.text,
        theme.switchTheme.trackOutlineColor,
      ),
      trackOutlineWidth: _whenFocused(
        _ringWidth,
        theme.switchTheme.trackOutlineWidth,
      ),
      overlayColor: _whenFocused(strong, theme.switchTheme.overlayColor),
    ),
    checkboxTheme: theme.checkboxTheme.copyWith(
      side: _focusedSide(
        theme.checkboxTheme.side,
        accentRing,
        // An unchecked checkbox's own border.
        idle: BorderSide(width: 2, color: theme.colorScheme.onSurfaceVariant),
      ),
      overlayColor: _whenFocused(strong, theme.checkboxTheme.overlayColor),
    ),
    sliderTheme: theme.sliderTheme.copyWith(overlayColor: strong),
  );
}

/// [style] (or an empty one) whose border is [ring] while focused, and
/// whose focus overlay is a light tint over the usual one.
ButtonStyle _withFocusRing(ButtonStyle? style, BorderSide ring) {
  final base = style ?? const ButtonStyle();
  return base.copyWith(
    side: _whenFocused(ring, base.side),
    overlayColor: _whenFocused(
      Colors.white.withValues(alpha: 0.12),
      base.overlayColor,
    ),
  );
}

/// [focused] while focused, [base] (resolved) otherwise; `null` falls back to
/// the widget's default.
WidgetStateProperty<T?> _whenFocused<T>(
  T focused,
  WidgetStateProperty<T?>? base,
) => WidgetStateProperty.resolveWith(
  (states) =>
      states.contains(WidgetState.focused) ? focused : base?.resolve(states),
);

/// A border that is [focused] while focused and [base] (resolved when it
/// depends on the state) otherwise. Where [base] gives none and there is no
/// state at all it is [idle], the control's own default border then:
/// `ThemeData.lerp` (a change of accent) resolves the border with no state and
/// fails on a null from both themes.
WidgetStateBorderSide _focusedSide(
  BorderSide? base,
  BorderSide focused, {
  required BorderSide idle,
}) => WidgetStateBorderSide.resolveWith((states) {
  if (states.contains(WidgetState.focused)) return focused;
  final resolved = base is WidgetStateBorderSide ? base.resolve(states) : base;
  return resolved ?? (states.isEmpty ? idle : null);
});
