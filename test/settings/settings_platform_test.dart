import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../sync/fake_passwords.dart';

/// Pumps the settings screen, runs [check], and restores the real platform.
Future<void> _checkOn(
  WidgetTester tester,
  TargetPlatform platform,
  void Function() check,
) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: SettingsScreen(db: db, passwords: FakePasswords()),
      ),
    ),
  );
  try {
    await tester.pump();
    check();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  const hardwareDecoding = 'Decodificación por hardware';

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('hardware decoding is hidden on $platform', (tester) async {
      await _checkOn(tester, platform, () {
        expect(find.text(hardwareDecoding), findsNothing);
        expect(find.text('Búfer de red'), findsOneWidget);
      });
    });
  }

  testWidgets('hardware decoding is shown on Windows', (tester) async {
    await _checkOn(tester, TargetPlatform.windows, () {
      expect(find.text(hardwareDecoding), findsOneWidget);
    });
  });
}
