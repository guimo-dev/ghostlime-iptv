import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/google_device_flow.dart';
import 'package:iptv_player/sync/google_sign_in.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/tv_device.dart';

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

  /// How many times the browser sign-in ran.
  int browserSignIns = 0;

  @override
  Future<void> signInWithGoogle() async => browserSignIns++;
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

  testWidgets('on a TV it opens the code dialog, not the browser', (
    tester,
  ) async {
    debugTvDevice = true;
    debugGoogleTvFlow = () => GoogleDeviceFlow(
      client: MockClient((_) async => throw http.ClientException('off')),
      clientId: 'test-client',
      clientSecret: 'test-secret',
    );
    addTearDown(() {
      debugTvDevice = null;
      debugGoogleTvFlow = null;
    });
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final account = _StubAccount(db, AccountStatus.signedIn);
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

    expect(account.browserSignIns, 0);
    expect(find.text('Entrar con Google'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(signedIn, 0);
  });
}
