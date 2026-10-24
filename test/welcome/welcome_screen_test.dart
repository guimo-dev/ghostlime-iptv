import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/legal/legal_screen.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/ghostlime_logo.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';

import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

const _optionsWithAccount = [
  'Entrar con email',
  'Crear cuenta',
  'Continuar con Google',
  'Continuar sin cuenta',
];

/// Pumps [screen] in the app theme at a desktop size.
Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  await tester.pump();
}

/// The button showing [label].
ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );

/// An account service on [db] whose fake backend knows [accounts].
AccountService _service(CatalogDb db, Map<String, String> accounts) {
  final service = AccountService(
    db: db,
    auth: FakeAuthGateway(accounts),
    backend: InMemorySyncBackend(),
    keys: FakeKeyStore(),
    passwords: FakePasswords(),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  testWidgets(
    'without an account only "Continuar sin cuenta", after "Acepto"',
    (tester) async {
      var done = 0;
      await _pump(tester, WelcomeScreen(onDone: () => done++));

      expect(find.text('Ghostlime IPTV'), findsOneWidget);
      expect(find.text('Reproductor para tus listas IPTV'), findsOneWidget);
      // The column stretches its children; the logo keeps its size.
      expect(tester.getSize(find.byType(GhostlimeLogo)), const Size(96, 96));
      for (final label in _optionsWithAccount.take(3)) {
        expect(find.text(label), findsNothing);
      }
      expect(_button(tester, 'Continuar sin cuenta').enabled, isFalse);

      await tester.tap(find.text('Acepto y continúo'));
      await tester.pump();
      expect(_button(tester, 'Continuar sin cuenta').enabled, isTrue);

      await tester.tap(find.text('Continuar sin cuenta'));
      await tester.pump();
      expect(done, 1);
    },
  );

  testWidgets(
    'with an account every option is there, disabled until "Acepto"',
    (tester) async {
      final db = CatalogDb.inMemory();
      addTearDown(db.close);
      await _pump(
        tester,
        WelcomeScreen(account: _service(db, {}), onDone: () {}),
      );

      for (final label in _optionsWithAccount) {
        expect(_button(tester, label).enabled, isFalse, reason: label);
      }
      await tester.tap(find.text('Acepto y continúo'));
      await tester.pump();
      for (final label in _optionsWithAccount) {
        // Google sign-in is not available yet (no gateway support).
        expect(
          _button(tester, label).enabled,
          label != 'Continuar con Google',
          reason: label,
        );
      }
      expect(find.byTooltip('Disponible pronto'), findsOneWidget);
    },
  );

  testWidgets('the links open the terms and the privacy policy', (
    tester,
  ) async {
    await _pump(tester, WelcomeScreen(onDone: () {}));
    for (final doc in LegalDoc.values) {
      await tester.tap(find.text(doc.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<LegalScreen>(find.byType(LegalScreen)).doc, doc);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LegalScreen), findsNothing);
    }
  });

  testWidgets('"Entrar con email" opens the account form; signing in ends', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final account = _service(db, {'ana@example.com': 'correct horse'});
    var done = 0;
    await _pump(tester, WelcomeScreen(account: account, onDone: () => done++));
    await tester.tap(find.text('Acepto y continúo'));
    await tester.pump();
    await tester.tap(find.text('Entrar con email'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Contraseña'),
      'correct horse',
    );
    // Deriving the key runs in an isolate: tap and wait in real time.
    await tester.runAsync(() async {
      await tester.tap(find.text('Entrar'));
      for (
        var i = 0;
        i < 100 && account.status != AccountStatus.signedIn;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    expect(account.status, AccountStatus.signedIn);
    expect(done, 1);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
  });

  testWidgets('AcceptTermsScreen only asks to accept the terms', (
    tester,
  ) async {
    var accepted = 0;
    await _pump(tester, AcceptTermsScreen(onAccepted: () => accepted++));
    expect(find.text('Continuar sin cuenta'), findsNothing);
    await tester.tap(find.text('Acepto y continúo'));
    await tester.pump();
    expect(accepted, 1);
  });

  testWidgets('form hints show inside the dialog, not as a SnackBar', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pump(
      tester,
      WelcomeScreen(account: _service(db, {}), onDone: () {}),
    );
    await tester.tap(find.text('Acepto y continúo'));
    await tester.pump();
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('¿Olvidaste la contraseña?'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Escribe tu email y vuelve a pulsar.'),
      ),
      findsOneWidget,
    );
  });
}
