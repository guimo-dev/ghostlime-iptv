import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/google_sign_in.dart';
import 'package:iptv_player/sync/sync_backend.dart';

import 'fake_account.dart';
import 'fake_passwords.dart';

/// An account whose Google sign-in ends in a fixed [endStatus].
class _StubAccount extends AccountService {
  _StubAccount(CatalogDb db, this.endStatus)
    : super(
        db: db,
        auth: FakeAuthGateway({}),
        backend: InMemorySyncBackend(),
        keys: FakeKeyStore(),
        passwords: FakePasswords(),
      );

  final AccountStatus endStatus;

  @override
  AccountStatus get status => endStatus;

  @override
  Future<void> signInWithGoogle() async {}
}

void main() {
  /// Taps the button of an account that ends in [status]; returns how many
  /// times `onSignedIn` ran.
  Future<int> tapWith(WidgetTester tester, AccountStatus status) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final account = _StubAccount(db, status);
    addTearDown(account.dispose);
    var signedIn = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoogleSignInButton(
            account: account,
            onSignedIn: () => signedIn++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();
    return signedIn;
  }

  testWidgets('onSignedIn runs when the user is in', (tester) async {
    expect(await tapWith(tester, AccountStatus.signedIn), 1);
  });

  testWidgets('onSignedIn runs for a state to settle in Ajustes', (
    tester,
  ) async {
    expect(await tapWith(tester, AccountStatus.needsPassword), 1);
  });

  for (final status in [
    AccountStatus.signedOut,
    AccountStatus.awaitingConfirmation,
  ]) {
    testWidgets('onSignedIn does not run when the status is $status', (
      tester,
    ) async {
      expect(await tapWith(tester, status), 0);
    });
  }
}
