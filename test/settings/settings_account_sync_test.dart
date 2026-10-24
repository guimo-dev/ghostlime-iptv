import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/sync/account_scope.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../sync/account_service_test.dart' show FakeAuthGateway, FakeKeyStore;
import '../sync/fake_passwords.dart';

const _switchTitle = 'Sincronizar ajustes en este dispositivo';

/// Pumps the settings page with [service] as the account.
Future<void> _pump(
  WidgetTester tester,
  CatalogDb db,
  AccountService service,
) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AccountScope(
      service: service,
      child: SettingsScope(
        controller: SettingsController(db),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SettingsScreen(db: db, passwords: FakePasswords()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// An account service on [db] with no session yet.
AccountService _service(CatalogDb db) {
  final service = AccountService(
    db: db,
    auth: FakeAuthGateway({}),
    backend: InMemorySyncBackend(),
    keys: FakeKeyStore(),
    passwords: FakePasswords(),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  testWidgets('signed out, there is no settings sync switch', (tester) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pump(tester, db, _service(db));
    expect(find.text(_switchTitle), findsNothing);
  });

  testWidgets('signed in, the switch turns settings sync off on this device', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final service = _service(db);
    await tester.runAsync(
      () => service.signUp('ana@example.com', 'correct horse'),
    );
    await _pump(tester, db, service);

    final row = find.ancestor(
      of: find.text(_switchTitle),
      matching: find.byType(Row),
    );
    final toggle = find.descendant(
      of: row.first,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump();

    expect(db.syncSettingsEnabled(), isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);
  });
}
