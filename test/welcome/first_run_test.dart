import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/playlists/playlists_screen.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/welcome/first_run.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';

import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

/// Pumps the whole app on [db] (with [account], if any) at a desktop size.
Future<void> _pumpApp(
  WidgetTester tester,
  CatalogDb db, {
  AccountService? account,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    IptvApp(
      db: db,
      passwords: FakePasswords(),
      settings: SettingsController(db),
      account: account,
    ),
  );
  await tester.pumpAndSettle();
}

/// An account service on [db] over [backend], with the fake [accounts].
AccountService _service(
  CatalogDb db,
  Map<String, String> accounts,
  SyncBackend backend,
) {
  final service = AccountService(
    db: db,
    auth: FakeAuthGateway(accounts),
    backend: backend,
    keys: FakeKeyStore(),
    passwords: FakePasswords(),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  test('a new installation shows the welcome', () {
    expect(
      firstRunStep(
        welcomeDone: false,
        acceptedTerms: 0,
        hasPlaylists: false,
        usedAccount: false,
      ),
      FirstRunStep.welcome,
    );
  });

  test('an installation with playlists or an account only accepts terms', () {
    for (final (hasPlaylists, usedAccount) in [(true, false), (false, true)]) {
      expect(
        firstRunStep(
          welcomeDone: false,
          acceptedTerms: 0,
          hasPlaylists: hasPlaylists,
          usedAccount: usedAccount,
        ),
        FirstRunStep.acceptTerms,
      );
    }
  });

  test('terms accepted in an older version are asked again', () {
    expect(
      firstRunStep(
        welcomeDone: true,
        acceptedTerms: termsVersion - 1,
        hasPlaylists: true,
        usedAccount: false,
      ),
      FirstRunStep.acceptTerms,
    );
  });

  test('with the welcome done and current terms nothing is shown', () {
    expect(
      firstRunStep(
        welcomeDone: true,
        acceptedTerms: termsVersion,
        hasPlaylists: false,
        usedAccount: false,
      ),
      FirstRunStep.none,
    );
  });

  test('the welcome and the accepted terms are kept in local prefs', () {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    expect(db.welcomeDone(), isFalse);
    expect(db.acceptedTermsVersion(), 0);
    db.saveWelcomeDone();
    db.saveAcceptedTermsVersion(termsVersion);
    expect(db.welcomeDone(), isTrue);
    expect(db.acceptedTermsVersion(), termsVersion);
  });

  testWidgets('the app opens with the welcome over the playlists, once', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pumpApp(tester, db);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(PlaylistsScreen), findsOneWidget);
    expect(db.welcomeDone(), isTrue);
    expect(db.acceptedTermsVersion(), termsVersion);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpApp(tester, db);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(PlaylistsScreen), findsOneWidget);
  });

  testWidgets('a welcome after the current terms skips the legal notice', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    db.saveAcceptedTermsVersion(termsVersion);
    await _pumpApp(tester, db);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Aceptar'), findsNothing);

    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(db.welcomeDone(), isTrue);
  });

  testWidgets('an installation that used an account only accepts the terms', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    db.saveSyncUserId('user-ana');
    await _pumpApp(tester, db);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(AcceptTermsScreen), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.byType(AcceptTermsScreen), findsNothing);
    expect(db.acceptedTermsVersion(), termsVersion);
  });

  testWidgets('the last playlist opens only after the terms are accepted', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final unsaved = Playlist(
      name: 'Lista',
      type: PlaylistType.m3uFile,
      source: 'no-existe.m3u',
      refreshedAt: DateTime.now(),
    );
    final id = db.savePlaylist(unsaved);
    // An error panel instead of the sections, so nothing loads in the shell.
    db.saveSyncError(id, 'Error de prueba.');
    db.saveSettings(
      const AppSettings(openLastPlaylist: true)
          .copyWith(lastPlaylistId: id)
          .toJson(),
    );
    await _pumpApp(tester, db);
    expect(find.byType(AcceptTermsScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.byType(AcceptTermsScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('an account that needs a decision ends the welcome in Ajustes', (
    tester,
  ) async {
    final backend = InMemorySyncBackend();
    final accounts = <String, String>{};
    // Another device created the account; then the password was reset
    // there, so the cloud key no longer opens with the new password.
    final otherDb = CatalogDb.inMemory();
    addTearDown(otherDb.close);
    await tester.runAsync(
      () => _service(
        otherDb,
        accounts,
        backend,
      ).signUp('ana@example.com', 'old password'),
    );
    accounts['ana@example.com'] = 'new password';

    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final account = _service(db, accounts, backend);
    await _pumpApp(tester, db, account: account);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar con email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Contraseña'),
      'new password',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Entrar'));
      for (
        var i = 0;
        i < 100 && account.status != AccountStatus.needsReset;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    expect(account.status, AccountStatus.needsReset);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.text('Los datos de la nube no se pueden abrir'),
      findsOneWidget,
    );
    expect(db.welcomeDone(), isTrue);
  });
}
