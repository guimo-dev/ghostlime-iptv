import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../sync/fake_passwords.dart';

/// Pumps the settings screen and scrolls to the accent colour row.
Future<SettingsController> _pumpAtAccentRow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1024, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final controller = SettingsController(db);
  await tester.pumpWidget(
    SettingsScope(
      controller: controller,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(db: db, passwords: FakePasswords()),
      ),
    ),
  );
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text('Color de acento'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('Interfaz offers one labelled swatch per preset, lime checked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpAtAccentRow(tester);
    for (final label in accentColorNames.values) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    final lime = tester.getSemantics(find.bySemanticsLabel('Lima'));
    expect(lime.flagsCollection.isSelected, Tristate.isTrue);
    final cyan = tester.getSemantics(find.bySemanticsLabel('Cian'));
    expect(cyan.flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('tapping a swatch saves the accent colour', (tester) async {
    final controller = await _pumpAtAccentRow(tester);
    await tester.tap(find.bySemanticsLabel('Cian'));
    await tester.pump();
    expect(controller.value.accentColor, AccentColor.cyan);
  });

  testWidgets('swatches take keyboard focus and Enter selects', (tester) async {
    final controller = await _pumpAtAccentRow(tester);
    Focus.of(tester.element(find.byKey(const ValueKey('accent-swatch-violet'))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.value.accentColor, AccentColor.violet);
  });
}
