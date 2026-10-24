import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/pin_scope.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/sync/account_scope.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';

import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

void main() {
  late CatalogDb db;
  late FakeAuthGateway auth;
  late AccountService account;

  setUp(() {
    db = CatalogDb.inMemory();
    auth = FakeAuthGateway({});
    account = AccountService(
      db: db,
      auth: auth,
      backend: InMemorySyncBackend(),
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
      pins: MemoryPinStore(),
    );
  });

  tearDown(() {
    account.dispose();
    db.close();
  });

  /// Signs in and pumps the settings page.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => account.signUp('ana@example.com', 'correct horse'),
    );
    await tester.pumpWidget(
      AccountScope(
        service: account,
        child: SettingsScope(
          controller: SettingsController(db),
          child: PinScope(
            store: MemoryPinStore(),
            child: MaterialApp(
              home: SettingsScreen(db: db, passwords: FakePasswords()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Taps "Borrar mi cuenta" and waits for the code dialog.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Borrar mi cuenta'));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog asks for the emailed code and the wipe choice', (
    tester,
  ) async {
    await pump(tester);
    await openDialog(tester);

    expect(auth.emailCodesSent, 1);
    expect(
      find.textContaining('ana@example.com con un código'),
      findsOneWidget,
    );
    expect(find.text('Código del correo'), findsOneWidget);
    expect(find.text('Borrar también de este dispositivo'), findsOneWidget);
    expect(auth.accountsDeleted, 0);
  });

  testWidgets('a wrong code is shown in the dialog and deletes nothing', (
    tester,
  ) async {
    await pump(tester);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('Borrar cuenta'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('El código no es correcto o ha caducado.'),
      ),
      findsOneWidget,
    );
    expect(auth.accountsDeleted, 0);
    expect(account.status, AccountStatus.signedIn);
  });

  testWidgets('the right code deletes the account and wipes the device', (
    tester,
  ) async {
    db.savePlaylist(
      const Playlist(name: 'A', type: PlaylistType.m3uUrl, source: 's'),
    );
    await pump(tester);
    await openDialog(tester);

    await tester.enterText(
      find.byType(TextField).last,
      FakeAuthGateway.validCode,
    );
    await tester.tap(find.text('Borrar también de este dispositivo'));
    await tester.pump();
    await tester.tap(find.text('Borrar cuenta'));
    await tester.pumpAndSettle();

    expect(auth.accountsDeleted, 1);
    expect(account.status, AccountStatus.signedOut);
    expect(db.playlists(), isEmpty);
    expect(find.text('Cuenta borrada.'), findsOneWidget);
  });
}
