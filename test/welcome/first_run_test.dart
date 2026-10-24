import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/playlists_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/welcome/first_run.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';

import '../sync/fake_passwords.dart';

/// Pumps the whole app on [db] (no account) at a desktop size.
Future<void> _pumpApp(WidgetTester tester, CatalogDb db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    IptvApp(
      db: db,
      passwords: FakePasswords(),
      settings: SettingsController(db),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a new installation shows the welcome', () {
    expect(
      firstRunStep(
        welcomeDone: false,
        acceptedTerms: 0,
        hasPlaylists: false,
        signedIn: false,
      ),
      FirstRunStep.welcome,
    );
  });

  test('an installation with playlists or an account only accepts terms', () {
    for (final (hasPlaylists, signedIn) in [(true, false), (false, true)]) {
      expect(
        firstRunStep(
          welcomeDone: false,
          acceptedTerms: 0,
          hasPlaylists: hasPlaylists,
          signedIn: signedIn,
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
        signedIn: false,
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
        signedIn: false,
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

    await tester.tap(find.text('Acepto y continúo'));
    await tester.pump();
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

  testWidgets('an installation that used an account only accepts the terms', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    db.saveSyncUserId('user-ana');
    await _pumpApp(tester, db);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(AcceptTermsScreen), findsOneWidget);

    await tester.tap(find.text('Acepto y continúo'));
    await tester.pumpAndSettle();
    expect(find.byType(AcceptTermsScreen), findsNothing);
    expect(db.acceptedTermsVersion(), termsVersion);
  });
}
