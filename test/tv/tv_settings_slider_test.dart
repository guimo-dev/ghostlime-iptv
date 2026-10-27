import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_screen.dart';

import 'tv_harness.dart';

/// The slider in the settings row titled [title].
Finder _sliderOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
  matching: find.byType(Slider),
);

/// The values the settings sliders show: network cache and guide offset.
(int, int) _values(TvDemo demo) {
  final settings = SettingsController(demo.db).value;
  return (settings.networkCacheSecs, settings.epgOffsetMinutes);
}

void main() {
  late TvDemo demo;
  setUp(() => demo = TvDemo());
  tearDown(() => demo.db.close());

  Future<void> pumpSettings(WidgetTester tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      SettingsScreen(db: demo.db, passwords: MemoryPasswordStore()),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls to the slider titled [title] and focuses it; returns its node.
  Future<FocusNode> focusSlider(WidgetTester tester, String title) async {
    // The list builds its rows lazily.
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final slider = _sliderOf(title);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final node = tester
        .widgetList<Focus>(
          find.descendant(of: slider, matching: find.byType(Focus)),
        )
        .firstWhere((focus) => focus.focusNode != null)
        .focusNode!;
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    return node;
  }

  for (final title in ['Búfer de red', 'Corrección horaria']) {
    // One test per key: the directional focus remembers where it came from,
    // so Up right after Down would go back to the slider.
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      testWidgets('$title: ${key.keyLabel} moves the focus on', (tester) async {
        await pumpSettings(tester);
        final node = await focusSlider(tester, title);
        final before = _values(demo);

        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(node.hasFocus, isFalse, reason: 'it stays on the slider');
        expect(_values(demo), before);
      });
    }

    testWidgets('$title: Right changes the value', (tester) async {
      await pumpSettings(tester);
      final node = await focusSlider(tester, title);
      final before = _values(demo);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      expect(_values(demo), isNot(before));
    });
  }
}
