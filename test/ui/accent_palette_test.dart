import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/ghostlime_logo.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

/// Colour of the pixel at ([x], [y]) of a 100 px logo drawn with [theme].
Future<Color> _logoPixel(
  WidgetTester tester,
  ThemeData theme,
  int x,
  int y,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Theme(
      data: theme,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: const GhostlimeLogo(size: 100),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final (image, bytes) = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return (image, await image.toByteData());
  }))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    bytes!.getUint8(i + 3),
    bytes.getUint8(i),
    bytes.getUint8(i + 1),
    bytes.getUint8(i + 2),
  );
}

void main() {
  test('there are 6 to 8 presets and lime is the brand palette', () {
    expect(AccentColor.values.length, inInclusiveRange(6, 8));
    expect(AccentColor.values.length, AccentPalette.presets.length);
    final lime = AccentPalette.presets[AccentColor.lime]!;
    expect(lime.accent, AppColors.accent);
    expect(lime.accentAlt, AppColors.accentAlt);
    expect(lime.onAccent, AppColors.onAccent);
    expect(lime.selected, AppColors.selected);
  });

  for (final entry in AccentPalette.presets.entries) {
    final palette = entry.value;
    test('${entry.key.name}: onAccent on accent is at least 4.5:1', () {
      expect(
        _contrast(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
    });
    test('${entry.key.name}: accent stands out on the dark surfaces', () {
      for (final surface in [
        AppColors.background,
        AppColors.surface,
        AppColors.surfaceHigh,
        palette.selected,
      ]) {
        expect(_contrast(palette.accent, surface), greaterThan(3));
      }
    });
  }

  test('the default theme is lime', () {
    final theme = buildAppTheme();
    expect(theme.colorScheme.primary, AppColors.accent);
    expect(theme.colorScheme.onPrimary, AppColors.onAccent);
    expect(
      theme.extension<AccentPalette>(),
      AccentPalette.presets[AccentColor.lime],
    );
  });

  test('the chosen accent drives the colour scheme and buttons', () {
    final violet = AccentPalette.presets[AccentColor.violet]!;
    final theme = buildAppTheme(accent: AccentColor.violet);
    expect(theme.colorScheme.primary, violet.accent);
    expect(theme.colorScheme.onPrimary, violet.onAccent);
    expect(theme.colorScheme.primaryContainer, violet.selected);
    expect(theme.extension<AccentPalette>(), violet);
    final button = theme.filledButtonTheme.style!;
    expect(button.backgroundColor!.resolve({}), violet.accent);
    expect(button.foregroundColor!.resolve({}), violet.onAccent);
  });

  testWidgets('the logo follows the accent of the theme', (tester) async {
    final cyan = AccentPalette.presets[AccentColor.cyan]!;
    // Body left of the play, inside the ghost.
    expect(
      await _logoPixel(tester, buildAppTheme(accent: AccentColor.cyan), 32, 48),
      cyan.accent,
    );
    expect(await _logoPixel(tester, buildAppTheme(), 32, 48), AppColors.accent);
  });
}
