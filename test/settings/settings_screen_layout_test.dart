import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';
import 'package:iptv_player/ui/content_width.dart';

import '../sync/fake_passwords.dart';

void main() {
  testWidgets('a setting row keeps label and control close when maximized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1300);
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
    await tester.pump();
    final label = tester.getRect(find.text('Decodificación por hardware'));
    final control = tester.getRect(find.byType(Switch).first);
    expect(
      control.right - label.left,
      lessThanOrEqualTo(ContentWidths.reading),
    );
    expect((label.left + control.right) / 2, closeTo(1280, 100));
  });

  testWidgets('the app bar sits over the app background, not the bare window', (
    tester,
  ) async {
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
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byType(AppBar),
        matching: find.byType(AppBackground),
      ),
      findsOneWidget,
    );
  });
  testWidgets('the mouse wheel scrolls the list over the side margins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 900);
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
    await tester.pump();
    final before = tester.getTopLeft(find.text('Reproducción')).dy;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(40, 450)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Reproducción')).dy, lessThan(before));
  });
}
