import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/player_screen.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  const black = Color(0xFF000000);

  test('desktop controls: icons and seek bar are at least 3:1 on black', () {
    expect(_contrast(desktopControlsTheme.buttonBarButtonColor, black), 21);
    for (final color in [
      Color.alphaBlend(desktopControlsTheme.seekBarColor, black),
      desktopControlsTheme.seekBarPositionColor,
      desktopControlsTheme.seekBarThumbColor,
    ]) {
      expect(_contrast(color, black), greaterThan(3));
    }
  });

  test('touch controls: icons and seek bar are at least 3:1 on black', () {
    expect(_contrast(mobileControlsTheme.buttonBarButtonColor, black), 21);
    for (final color in [
      Color.alphaBlend(mobileControlsTheme.seekBarColor, black),
      mobileControlsTheme.seekBarPositionColor,
      mobileControlsTheme.seekBarThumbColor,
    ]) {
      expect(_contrast(color, black), greaterThan(3));
    }
  });
}
