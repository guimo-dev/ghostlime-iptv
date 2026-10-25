import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/choice_selector.dart';

const _options = {1: 'Uno', 2: 'Dos', 3: 'Tres'};

/// Pumps a [ChoiceSelector] of [_options] with [value] selected on a screen
/// of [size]; every choice is added to [chosen].
Future<void> _pump(
  WidgetTester tester,
  Size size, {
  int value = 2,
  List<int>? chosen,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ChoiceSelector<int>(
          options: _options,
          value: value,
          onChanged: (v) => chosen?.add(v),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('phones get chips with the value selected', (tester) async {
    await _pump(tester, const Size(390, 844));
    expect(find.byType(SegmentedButton<int>), findsNothing);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect([for (final c in chips) c.selected], [false, true, false]);
  });

  testWidgets('the desktop gets segments with the value selected', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.byType(ChoiceChip), findsNothing);
    final segments = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(segments.selected, {2});
  });

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('tapping a choice reports it at ${size.width.toInt()}', (
      tester,
    ) async {
      final chosen = <int>[];
      await _pump(tester, size, chosen: chosen);
      await tester.tap(find.text('Tres'));
      await tester.pump();
      expect(chosen, [3]);
    });
  }

  testWidgets('a focused chip shows a ring, also when selected', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844));
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(1));
    final side = chip.side;
    expect(side, isA<WidgetStateBorderSide>());
    final resting = (side! as WidgetStateBorderSide).resolve({
      WidgetState.selected,
    });
    for (final states in [
      {WidgetState.focused},
      {WidgetState.focused, WidgetState.selected},
    ]) {
      final focused = (side as WidgetStateBorderSide).resolve(states)!;
      expect(focused.width, greaterThanOrEqualTo(2), reason: '$states');
      expect(focused.color, isNot(resting?.color), reason: '$states');
    }
  });
}
