import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/parental_session.dart';
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
  late MemoryPinStore pins;

  setUp(() {
    db = CatalogDb.inMemory();
    auth = FakeAuthGateway({});
    pins = MemoryPinStore();
    ParentalSession.unlocked.value = true;
    account = AccountService(
      db: db,
      auth: auth,
      backend: InMemorySyncBackend(),
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
      pins: pins,
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
            store: pins,
            child: MaterialApp(
              home: SettingsScreen(db: db, passwords: FakePasswords()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets animations and async work run. Not pumpAndSettle: the section's
  /// progress bar keeps animating while the dialog is open.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Taps "Borrar mi cuenta" and waits for the code dialog.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Borrar mi cuenta'));
    await settle(tester);
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
    await settle(tester);

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
    await pins.setPin('1234');
    await pump(tester);
    await openDialog(tester);

    await tester.enterText(
      find.byType(TextField).last,
      FakeAuthGateway.validCode,
    );
    await tester.tap(find.text('Borrar también de este dispositivo'));
    await tester.pump();
    await tester.tap(find.text('Borrar cuenta'));
    await settle(tester);

    expect(auth.accountsDeleted, 1);
    expect(account.status, AccountStatus.signedOut);
    expect(db.playlists(), isEmpty);
    expect(await pins.hasPin(), isFalse);
    expect(ParentalSession.unlocked.value, isFalse);
    expect(find.text('Cuenta borrada.'), findsOneWidget);
  });
}
