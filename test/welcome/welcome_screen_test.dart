import 'dart:async';

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

/// The welcome options with an account, top to bottom.
const _optionsWithAccount = [
  'Entrar con email',
  'Continuar con Google',
  'Continuar sin cuenta',
  'Crear cuenta',
];

/// Pumps [screen] in the app theme at [size] (a desktop one by default) and
/// lets the legal notice come up.
Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh tree, so a second pump in a test starts over.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  await tester.pumpAndSettle();
}

/// Taps [label] in the legal notice and waits for it to close.
Future<void> _answerNotice(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
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

/// An account service on [db] whose fake backend knows [accounts]; [auth]
/// replaces its fake gateway (e.g. one with Google).
AccountService _service(
  CatalogDb db,
  Map<String, String> accounts, {
  FakeAuthGateway? auth,
}) {
  final service = AccountService(
    db: db,
    auth: auth ?? FakeAuthGateway(accounts),
    backend: InMemorySyncBackend(),
    keys: FakeKeyStore(),
    passwords: FakePasswords(),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  testWidgets(
    'without an account only "Continuar sin cuenta", after "Aceptar"',
    (tester) async {
      var done = 0;
      await _pump(tester, WelcomeScreen(onDone: () => done++));

      expect(find.text('Ghostlime IPTV'), findsOneWidget);
      expect(find.text('Reproductor para tus listas IPTV'), findsOneWidget);
      // The column stretches its children; the logo keeps its size.
      expect(tester.getSize(find.byType(GhostlimeLogo)), const Size(96, 96));
      for (final label in [
        'Entrar con email',
        'Continuar con Google',
        'Crear cuenta',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(_button(tester, 'Continuar sin cuenta').enabled, isFalse);

      await _answerNotice(tester, 'Aceptar');
      expect(_button(tester, 'Continuar sin cuenta').enabled, isTrue);

      await tester.tap(find.text('Continuar sin cuenta'));
      await tester.pump();
      expect(done, 1);
    },
  );

  testWidgets(
    'with an account every option is there, disabled until "Aceptar"',
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
      await _answerNotice(tester, 'Aceptar');
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

  testWidgets('"Continuar con Google" signs in and ends the welcome', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final auth = FakeAuthGateway({})..supportsGoogle = true;
    final account = _service(db, {}, auth: auth);
    var done = 0;
    await _pump(tester, WelcomeScreen(account: account, onDone: () => done++));
    expect(_button(tester, 'Continuar con Google').enabled, isFalse);
    expect(find.byTooltip('Disponible pronto'), findsNothing);
    await _answerNotice(tester, 'Aceptar');
    expect(_button(tester, 'Continuar con Google').enabled, isTrue);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(account.status, AccountStatus.signedIn);
    expect(auth.escrowStores, 1);
    expect(done, 1);
    expect(find.text('Continúa en el navegador'), findsNothing);
    // Stops the periodic sync before the test ends.
    await account.signOut();
  });

  testWidgets('"Cancelar" while in the browser stays with its message', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final auth = FakeAuthGateway({})
      ..supportsGoogle = true
      ..browser = Completer<void>();
    final account = _service(db, {}, auth: auth);
    var done = 0;
    await _pump(tester, WelcomeScreen(account: account, onDone: () => done++));
    await _answerNotice(tester, 'Aceptar');

    await tester.tap(find.text('Continuar con Google'));
    // The dialog's progress bar never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Continúa en el navegador'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(auth.oauthCancels, 1);

    expect(account.status, AccountStatus.signedOut);
    expect(done, 0);
    expect(find.text('Se ha cancelado el acceso con Google.'), findsOneWidget);
    expect(find.text('Continúa en el navegador'), findsNothing);
    expect(_button(tester, 'Continuar con Google').enabled, isTrue);
  });

  testWidgets('"Entrar con email" opens the account form; signing in ends', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    final account = _service(db, {'ana@example.com': 'correct horse'});
    var done = 0;
    await _pump(tester, WelcomeScreen(account: account, onDone: () => done++));
    await _answerNotice(tester, 'Aceptar');
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

  testWidgets('the notice opens unless the current terms are accepted', (
    tester,
  ) async {
    await _pump(tester, WelcomeScreen(onDone: () {}));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('es solo un reproductor'), findsOneWidget);

    await _pump(tester, WelcomeScreen(termsAccepted: true, onDone: () {}));
    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining('es solo un reproductor'), findsNothing);
    expect(_button(tester, 'Continuar sin cuenta').enabled, isTrue);
  });

  testWidgets('a dialog at 1280x800, a bottom sheet at 390x844', (
    tester,
  ) async {
    await _pump(
      tester,
      WelcomeScreen(onDone: () {}),
      size: const Size(1280, 800),
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await _pump(
      tester,
      WelcomeScreen(onDone: () {}),
      size: const Size(390, 844),
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    // Right-handed thumb: "Aceptar" bottom right, below the text.
    final accept = tester.getRect(find.text('Aceptar'));
    final reject = tester.getRect(find.text('Rechazar'));
    final more = tester.getRect(find.text('Leer más'));
    final notice = tester.getRect(
      find.textContaining('es solo un reproductor'),
    );
    expect(more.top, greaterThan(notice.bottom));
    expect(accept.top, greaterThan(more.bottom));
    expect(accept.left, greaterThan(reject.right));
    expect(accept.center.dy, closeTo(reject.center.dy, 1));
    expect(accept.right, greaterThan(390 - 60));
  });

  for (final size in [const Size(1280, 800), const Size(390, 844)]) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('"Rechazar" locks the welcome until accepted at $at', (
      tester,
    ) async {
      final db = CatalogDb.inMemory();
      addTearDown(db.close);
      await _pump(
        tester,
        WelcomeScreen(account: _service(db, {}), onDone: () {}),
        size: size,
      );
      await _answerNotice(tester, 'Rechazar');

      expect(find.textContaining('es solo un reproductor'), findsNothing);
      for (final label in _optionsWithAccount) {
        expect(_button(tester, label).enabled, isFalse, reason: label);
      }
      await tester.tap(find.text('Revisar términos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('es solo un reproductor'), findsOneWidget);

      await _answerNotice(tester, 'Aceptar');
      expect(find.text('Revisar términos'), findsNothing);
      expect(_button(tester, 'Continuar sin cuenta').enabled, isTrue);
    });

    testWidgets('"Leer más" opens each document and comes back at $at', (
      tester,
    ) async {
      await _pump(tester, WelcomeScreen(onDone: () {}), size: size);
      await tester.tap(find.text('Leer más'));
      await tester.pumpAndSettle();
      for (final doc in LegalDoc.values) {
        await tester.tap(find.text(doc.title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.widget<LegalScreen>(find.byType(LegalScreen)).doc, doc);
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(LegalScreen), findsNothing);
        expect(find.text('Aceptar'), findsOneWidget);
      }
    });
  }

  testWidgets('going back from the notice is the same as "Rechazar"', (
    tester,
  ) async {
    await _pump(tester, WelcomeScreen(onDone: () {}));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('es solo un reproductor'), findsNothing);
    expect(find.text('Revisar términos'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('the welcome buttons in order, "Crear cuenta" apart', (
    tester,
  ) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pump(
      tester,
      WelcomeScreen(account: _service(db, {}), onDone: () {}),
    );
    await _answerNotice(tester, 'Aceptar');

    final tops = [
      for (final label in _optionsWithAccount)
        tester.getRect(find.text(label)).top,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: _optionsWithAccount[i]);
    }
    expect(
      tester.widget(
        find
            .ancestor(
              of: find.text('Entrar con email'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      ),
      isA<FilledButton>(),
    );
    expect(
      find.ancestor(
        of: find.text('Crear cuenta'),
        matching: find.byType(TextButton),
      ),
      findsOneWidget,
    );
    final question = tester.getRect(find.text('¿No tienes cuenta?'));
    final withoutAccount = tester.getRect(
      find
          .ancestor(
            of: find.text('Continuar sin cuenta'),
            matching: find.byType(OutlinedButton),
          )
          .first,
    );
    expect(question.top - withoutAccount.bottom, greaterThanOrEqualTo(24));
    expect(
      (tester.getCenter(find.text('Crear cuenta')).dy -
              tester.getCenter(find.text('¿No tienes cuenta?')).dy)
          .abs(),
      lessThan(4),
    );
  });

  testWidgets('AcceptTermsScreen shows the notice; "Aceptar" goes on', (
    tester,
  ) async {
    var accepted = 0;
    await _pump(tester, AcceptTermsScreen(onAccepted: () => accepted++));
    expect(find.text('Continuar sin cuenta'), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    await _answerNotice(tester, 'Aceptar');
    expect(accepted, 1);
  });

  testWidgets('AcceptTermsScreen after "Rechazar" offers "Revisar términos"', (
    tester,
  ) async {
    var accepted = 0;
    await _pump(
      tester,
      AcceptTermsScreen(onAccepted: () => accepted++),
      size: const Size(390, 844),
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    await _answerNotice(tester, 'Rechazar');
    expect(accepted, 0);
    expect(find.byType(AcceptTermsScreen), findsOneWidget);

    await tester.tap(find.text('Revisar términos'));
    await tester.pumpAndSettle();
    await _answerNotice(tester, 'Aceptar');
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
    await _answerNotice(tester, 'Aceptar');
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
