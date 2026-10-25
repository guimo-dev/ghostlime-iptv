import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  const black = Color(0xFF000000);

  for (final MapEntry(key: name, value: palette)
      in AccentPalette.presets.entries) {
    test('desktop controls (${name.name}): icons and seek bar are at least '
        '3:1 on black', () {
      final theme = desktopControlsTheme(palette.accent);
      expect(_contrast(theme.buttonBarButtonColor, black), 21);
      expect(theme.seekBarPositionColor, palette.accent);
      for (final color in [
        Color.alphaBlend(theme.seekBarColor, black),
        theme.seekBarPositionColor,
        theme.seekBarThumbColor,
      ]) {
        expect(_contrast(color, black), greaterThan(3));
      }
    });

    test('touch controls (${name.name}): icons and seek bar are at least '
        '3:1 on black', () {
      final theme = mobileControlsTheme(palette.accent);
      expect(_contrast(theme.buttonBarButtonColor, black), 21);
      expect(theme.seekBarThumbColor, palette.accent);
      for (final color in [
        Color.alphaBlend(theme.seekBarColor, black),
        theme.seekBarPositionColor,
        theme.seekBarThumbColor,
      ]) {
        expect(_contrast(color, black), greaterThan(3));
      }
    });
  }
}
