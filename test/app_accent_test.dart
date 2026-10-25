import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/ui/app_theme.dart';

import 'sync/fake_passwords.dart';

void main() {
  testWidgets('the app theme follows the accent colour setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final settings = SettingsController(db);
    await tester.pumpWidget(
      IptvApp(db: db, passwords: FakePasswords(), settings: settings),
    );
    await tester.pump();
    ColorScheme scheme() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
    expect(scheme().primary, AppColors.accent);

    settings.update(settings.value.copyWith(accentColor: AccentColor.pink));
    await tester.pumpAndSettle();
    final pink = AccentPalette.presets[AccentColor.pink]!;
    expect(scheme().primary, pink.accent);
    expect(scheme().onPrimary, pink.onAccent);
  });
}
