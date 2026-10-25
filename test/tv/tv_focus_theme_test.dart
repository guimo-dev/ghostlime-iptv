import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/tv/exit_dialog.dart';
import 'package:iptv_player/tv/tv_focus_theme.dart';
import 'package:iptv_player/ui/app_theme.dart';

import 'tv_harness.dart';

const _focused = {WidgetState.focused};
const _idle = <WidgetState>{};

/// The border a button style draws in [states] (null: none).
BorderSide? _side(ButtonStyle? style, Set<WidgetState> states) =>
    style?.side?.resolve(states);

void main() {
  final theme = withTvFocus(buildAppTheme());

  test('every button type draws a ring when focused', () {
    final styles = {
      'filled': theme.filledButtonTheme.style,
      'outlined': theme.outlinedButtonTheme.style,
      'text': theme.textButtonTheme.style,
      'icon': theme.iconButtonTheme.style,
      'segmented': theme.segmentedButtonTheme.style,
    };
    for (final MapEntry(:key, :value) in styles.entries) {
      final ring = _side(value, _focused);
      expect(ring?.width, greaterThanOrEqualTo(2), reason: key);
      expect(ring, isNot(_side(value, _idle)), reason: key);
    }
    // On the accent fill an accent ring would not show.
    final palette = theme.extension<AccentPalette>()!;
    expect(
      _side(theme.filledButtonTheme.style, _focused)!.color,
      AppColors.text,
    );
    expect(
      _side(theme.outlinedButtonTheme.style, _focused)!.color,
      palette.accent,
    );
  });

  test('the outlined button keeps its border when not focused', () {
    final idle = _side(theme.outlinedButtonTheme.style, _idle);
    expect(idle, const BorderSide(color: AppColors.border));
  });

  test(
    'chips, switches, checkboxes, sliders and list tiles show the focus',
    () {
      final chipSide = theme.chipTheme.side! as WidgetStateBorderSide;
      expect(chipSide.resolve(_focused)!.width, greaterThanOrEqualTo(2));
      expect(
        chipSide.resolve(_idle),
        const BorderSide(color: AppColors.border),
      );

      final switches = theme.switchTheme;
      expect(
        switches.trackOutlineWidth!.resolve(_focused),
        greaterThanOrEqualTo(2),
      );
      expect(switches.trackOutlineColor!.resolve(_focused), AppColors.text);
      expect(switches.trackOutlineColor!.resolve(_idle), Colors.transparent);

      final checkSide = theme.checkboxTheme.side! as WidgetStateBorderSide;
      expect(checkSide.resolve(_focused)!.width, greaterThanOrEqualTo(2));
      expect(
        theme.checkboxTheme.overlayColor!.resolve(_focused)!.a,
        greaterThan(0.3),
      );

      expect(theme.sliderTheme.overlayColor!.a, greaterThan(0.3));
      // List tiles only have the theme's focus colour: a strong one.
      expect(theme.focusColor.a, greaterThan(0.3));
    },
  );

  testWidgets('the exit dialog tells the focused Cancelar apart', (
    tester,
  ) async {
    useTvView(tester);
    final demo = TvDemo();
    addTearDown(demo.db.close);
    await pumpTvApp(
      tester,
      demo.db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmExit(context),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    BorderSide sideOf(Type button, String label) {
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.widgetWithText(button, label),
              matching: find.byType(Material),
            )
            .first,
      );
      return (material.shape! as OutlinedBorder).side;
    }

    expect(sideOf(TextButton, 'Cancelar').width, greaterThanOrEqualTo(2));
    expect(sideOf(TextButton, 'Cancelar').style, BorderStyle.solid);
    expect(sideOf(FilledButton, 'Salir').style, BorderStyle.none);
  });
}
