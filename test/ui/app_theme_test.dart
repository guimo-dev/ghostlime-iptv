import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/app_theme.dart';

/// Pumps a [FilterChip] labelled "Solo con guía" with the app theme.
Future<void> _pumpChip(WidgetTester tester, {required bool selected}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: FilterChip(
          label: const Text('Solo con guía'),
          selected: selected,
          onSelected: (_) {},
        ),
      ),
    ),
  );
}

/// Colour of the chip's text as rendered.
Color _labelColor(WidgetTester tester) {
  final context = tester.element(find.text('Solo con guía'));
  return DefaultTextStyle.of(context).style.color!;
}

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  for (final selected in [true, false]) {
    testWidgets('filter chip text is readable (selected: $selected)', (
      tester,
    ) async {
      await _pumpChip(tester, selected: selected);
      final chipTheme = buildAppTheme().chipTheme;
      final background = selected
          ? chipTheme.selectedColor!
          : Color.alphaBlend(chipTheme.backgroundColor!, AppColors.background);
      expect(_contrast(background, _labelColor(tester)), greaterThan(4.5));
    });
  }

  test('Windows text falls back to an emoji font', () {
    final theme = buildAppTheme();
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('Segoe UI Emoji'),
    );
  }, skip: !Platform.isWindows);
}
