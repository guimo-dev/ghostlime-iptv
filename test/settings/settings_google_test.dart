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

import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

const _email = 'ana@example.com';
const _password = 'correct horse';

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

/// An account service on a new database of [backend] whose gateway is [auth].
AccountService _service(InMemorySyncBackend backend, FakeAuthGateway auth) {
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final service = AccountService(
    db: db,
    auth: auth,
    backend: backend,
    keys: FakeKeyStore(),
    passwords: FakePasswords(),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  testWidgets('without Google support the form has no Google button', (
    tester,
  ) async {
    final service = _service(InMemorySyncBackend(), FakeAuthGateway({}));
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pump(tester, db, service);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
  });

  testWidgets(
    'Google into a password account asks the password once and opens it',
    (tester) async {
      final backend = InMemorySyncBackend();
      final accounts = <String, String>{};
      final first = _service(backend, FakeAuthGateway(accounts));
      await tester.runAsync(() => first.signUp(_email, _password));
      await tester.runAsync(first.signOut);

      final auth = FakeAuthGateway(accounts)
        ..supportsGoogle = true
        ..googleEmail = _email;
      final service = _service(backend, auth);
      final db = CatalogDb.inMemory();
      addTearDown(db.close);
      await _pump(tester, db, service);

      await tester.tap(find.text('Continuar con Google'));
      await tester.pumpAndSettle();
      expect(service.status, AccountStatus.needsPassword);
      expect(find.text(_email), findsOneWidget);

      await tester.tap(find.text('Escribir la contraseña'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        _password,
      );
      await tester.tap(find.text('Abrir'));
      // The dialog's result arrives in fake time, the key derivation (an
      // isolate) in real time: alternate both until it opens.
      for (
        var i = 0;
        i < 100 && service.status != AccountStatus.signedIn;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pumpAndSettle();

      expect(service.status, AccountStatus.signedIn);
      expect(auth.escrowStores, 0);
      expect(auth.escrow, isEmpty);
      expect(find.text('Escribir la contraseña'), findsNothing);
      await tester.runAsync(service.signOut);
    },
  );
}
