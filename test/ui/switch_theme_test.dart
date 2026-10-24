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
  final theme = buildAppTheme().switchTheme;
  final surfaces = {
    'background': AppColors.background,
    'surface': AppColors.surface,
    'surfaceHigh': AppColors.surfaceHigh,
  };

  for (final MapEntry(key: name, value: surface) in surfaces.entries) {
    test('an off switch track is at least 3:1 against $name', () {
      expect(
        _contrast(theme.trackColor!.resolve({})!, surface),
        greaterThan(3),
      );
    });
  }

  test('an off switch thumb stands out from its track and has no outline', () {
    final track = theme.trackColor!.resolve({})!;
    expect(_contrast(theme.thumbColor!.resolve({})!, track), greaterThan(3));
    expect(theme.trackOutlineColor!.resolve({}), Colors.transparent);
  });

  test('an on switch is lime with a dark thumb', () {
    expect(
      theme.trackColor!.resolve({WidgetState.selected})!,
      AppColors.accent,
    );
    expect(
      theme.thumbColor!.resolve({WidgetState.selected})!,
      AppColors.onAccent,
    );
  });
}
