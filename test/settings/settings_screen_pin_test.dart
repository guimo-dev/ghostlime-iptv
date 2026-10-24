import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/parental_session.dart';
import 'package:iptv_player/settings/pin_scope.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/sync/account_scope.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';

import '../sync/account_service_test.dart' show FakeAuthGateway, FakeKeyStore;
import '../sync/fake_passwords.dart';

const _lockTitle = 'Control parental con PIN';
const _forgot = '¿Olvidaste el PIN?';

void main() {
  late CatalogDb db;
  late MemoryPinStore pins;
  late SettingsController settings;
  late FakeAuthGateway auth;
  late AccountService account;

  setUp(() {
    db = CatalogDb.inMemory();
    pins = MemoryPinStore();
    settings = SettingsController(db);
    auth = FakeAuthGateway({});
    account = AccountService(
      db: db,
      auth: auth,
      backend: InMemorySyncBackend(),
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
    );
    ParentalSession.unlocked.value = false;
  });

  tearDown(() {
    account.dispose();
    db.close();
  });

  /// Pumps the settings page; [withAccount] `false` is a build without
  /// Supabase.
  Future<void> pump(WidgetTester tester, {bool withAccount = true}) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountScope(
        service: withAccount ? account : null,
        child: SettingsScope(
          controller: settings,
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

  Future<void> signIn(WidgetTester tester) =>
      tester.runAsync(() => account.signUp('ana@example.com', 'correct horse'));

  Finder lockSwitch() => find.descendant(
    of: find
        .ancestor(of: find.text(_lockTitle), matching: find.byType(Row))
        .first,
    matching: find.byType(Switch),
  );

  Finder dialogField(int index) => find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      )
      .at(index);

  Future<void> tapLockSwitch(WidgetTester tester) async {
    await tester.ensureVisible(lockSwitch());
    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();
  }

  /// Types [pin] in every field of the open PIN dialog and accepts it.
  Future<void> enterPin(
    WidgetTester tester,
    String pin, {
    int fields = 1,
  }) async {
    for (var i = 0; i < fields; i++) {
      await tester.enterText(dialogField(i), pin);
    }
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
  }

  /// Turns the lock on with [pin] already stored, as a previous session left.
  void lockWith(String pin) {
    pins.setPin(pin);
    settings.update(settings.value.copyWith(parentalLock: true));
  }

  testWidgets('signed out, the lock switch is disabled and explains why', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.widget<Switch>(lockSwitch()).onChanged, isNull);
    expect(
      find.text('Inicia sesión para usar el control parental.'),
      findsOneWidget,
    );
  });

  testWidgets('without Supabase, the lock switch is disabled', (tester) async {
    await pump(tester, withAccount: false);
    expect(tester.widget<Switch>(lockSwitch()).onChanged, isNull);
    expect(
      find.text('Inicia sesión para usar el control parental.'),
      findsOneWidget,
    );
  });

  testWidgets('turning it on always creates a new PIN', (tester) async {
    await pins.setPin('9999');
    await signIn(tester);
    await pump(tester);

    await tapLockSwitch(tester);
    expect(find.text('Repite el PIN'), findsOneWidget);
    await enterPin(tester, '1234', fields: 2);

    expect(settings.value.parentalLock, isTrue);
    expect(await pins.verify('1234'), isTrue);
    expect(await pins.verify('9999'), isFalse);
  });

  testWidgets('cancelling the new PIN leaves the lock off', (tester) async {
    await signIn(tester);
    await pump(tester);

    await tapLockSwitch(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(settings.value.parentalLock, isFalse);
    expect(await pins.hasPin(), isFalse);
  });

  testWidgets('turning it off asks for the PIN and deletes it', (tester) async {
    await signIn(tester);
    lockWith('1234');
    await pump(tester);

    await tapLockSwitch(tester);
    expect(find.text('Introduce el PIN'), findsOneWidget);
    await enterPin(tester, '1234');

    expect(settings.value.parentalLock, isFalse);
    expect(await pins.hasPin(), isFalse);
  });

  testWidgets('a wrong PIN keeps the lock on', (tester) async {
    await signIn(tester);
    lockWith('1234');
    await pump(tester);

    await tapLockSwitch(tester);
    await enterPin(tester, '0000');

    expect(find.text('PIN incorrecto.'), findsOneWidget);
    expect(settings.value.parentalLock, isTrue);
    expect(await pins.verify('1234'), isTrue);
  });

  testWidgets('a forgotten PIN is replaced with the emailed code', (
    tester,
  ) async {
    await signIn(tester);
    lockWith('1234');
    await pump(tester);

    await tapLockSwitch(tester);
    await tester.tap(find.text(_forgot));
    await tester.pumpAndSettle();
    expect(auth.emailCodesSent, 1);

    await tester.enterText(dialogField(0), '000000');
    await tester.tap(find.text('Comprobar'));
    await tester.pumpAndSettle();
    expect(
      find.text('El código no es correcto o ha caducado.'),
      findsOneWidget,
    );
    expect(await pins.verify('1234'), isTrue);

    await tapLockSwitch(tester);
    await tester.tap(find.text(_forgot));
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(0), FakeAuthGateway.validCode);
    await tester.tap(find.text('Comprobar'));
    await tester.pumpAndSettle();
    await enterPin(tester, '5678', fields: 2);

    expect(await pins.verify('5678'), isTrue);
    expect(settings.value.parentalLock, isTrue);
  });

  testWidgets('without a session the PIN dialog offers no reset', (
    tester,
  ) async {
    lockWith('1234');
    await pump(tester);

    await tapLockSwitch(tester);
    expect(find.text('Introduce el PIN'), findsOneWidget);
    expect(find.text(_forgot), findsNothing);
  });

  group('signing out with the lock on', () {
    Future<void> signOut(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
    }

    testWidgets('the right PIN turns the lock off and signs out', (
      tester,
    ) async {
      await signIn(tester);
      lockWith('1234');
      await pump(tester);

      await signOut(tester);
      expect(find.text('Introduce el PIN'), findsOneWidget);
      await enterPin(tester, '1234');

      expect(account.status, AccountStatus.signedOut);
      expect(settings.value.parentalLock, isFalse);
      expect(await pins.hasPin(), isFalse);
    });

    testWidgets('cancelling the PIN keeps the session', (tester) async {
      await signIn(tester);
      lockWith('1234');
      await pump(tester);

      await signOut(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(account.status, AccountStatus.signedIn);
      expect(settings.value.parentalLock, isTrue);
      expect(await pins.verify('1234'), isTrue);
    });
  });
}
