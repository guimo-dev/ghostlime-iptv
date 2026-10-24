import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/settings/settings_controller.dart';

import 'sync/fake_passwords.dart';

void main() {
  testWidgets('Material strings (licenses page, dialogs) are in Spanish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      IptvApp(
        db: db,
        passwords: FakePasswords(),
        settings: SettingsController(db),
      ),
    );
    await tester.pump();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context).languageCode, 'es');
    expect(MaterialLocalizations.of(context).okButtonLabel, 'ACEPTAR');
    expect(MaterialLocalizations.of(context).licensesPageTitle, 'Licencias');
  });
}
