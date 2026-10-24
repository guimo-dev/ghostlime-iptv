import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  test('palette uses the Ghostlime brand colours', () {
    expect(AppColors.accent, const Color(0xFFC6F432));
    expect(AppColors.accentAlt, const Color(0xFF8FD400));
    expect(AppColors.onAccent, const Color(0xFF14151F));
  });

  test('onAccent text on accent is at least 4.5:1', () {
    expect(_contrast(AppColors.onAccent, AppColors.accent), greaterThan(4.5));
  });

  for (final entry in {
    'background': AppColors.background,
    'surface': AppColors.surface,
    'surfaceHigh': AppColors.surfaceHigh,
    'selected': AppColors.selected,
  }.entries) {
    test('accent on ${entry.key} is at least 3:1', () {
      expect(_contrast(AppColors.accent, entry.value), greaterThan(3));
    });
  }

  test('primary buttons are lime with dark text', () {
    final style = buildAppTheme().filledButtonTheme.style!;
    expect(style.backgroundColor!.resolve({}), AppColors.accent);
    expect(style.foregroundColor!.resolve({}), AppColors.onAccent);
  });
}
