import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/google_device_dialog.dart';
import 'package:iptv_player/sync/google_device_flow.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fake_account.dart';
import 'fake_passwords.dart';

/// Google's two endpoints, simulated: the device code always works (unless
/// [offline]) and the token endpoint answers [tokenReplies] in order, then
/// `authorization_pending` forever.
class _FakeGoogle {
  final tokenReplies = <http.Response>[];
  int codeRequests = 0;
  int tokenRequests = 0;
  bool offline = false;

  /// When set, every request throws it (an error no one expected).
  Object? unexpected;

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    if (unexpected case final error?) throw error;
    if (request.url.path == '/device/code') {
      codeRequests++;
      return http.Response(
        jsonEncode({
          'device_code': 'device-123',
          'user_code': 'ABCD-EFGH',
          'verification_url': 'https://www.google.com/device',
          'expires_in': 1800,
          'interval': 5,
        }),
        200,
      );
    }
    tokenRequests++;
    if (tokenReplies.isNotEmpty) return tokenReplies.removeAt(0);
    return error('authorization_pending');
  });

  /// A token endpoint error reply.
  static http.Response error(String code) =>
      http.Response(jsonEncode({'error': code}), 428);
}

/// What the fake says when it refuses the token.
const _refused = 'No se ha podido entrar con Google. Inténtalo de nuevo.';

void main() {
  late _FakeGoogle google;
  late FakeAuthGateway auth;
  late AccountService account;
  late InMemorySyncBackend backend;

  setUp(() {
    google = _FakeGoogle();
    debugGoogleTvFlow = () => GoogleDeviceFlow(
      client: google.client,
      clientId: 'test-client',
      clientSecret: 'test-secret',
    );
  });

  tearDown(() => debugGoogleTvFlow = null);

  /// Pumps a button that opens the dialog; the dialog's answer goes to the
  /// returned list once it closes.
  Future<List<bool>> pumpOpener(WidgetTester tester) async {
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    auth = FakeAuthGateway({});
    backend = InMemorySyncBackend();
    account = AccountService(
      db: db,
      auth: auth,
      backend: backend,
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
    );
    addTearDown(account.dispose);
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await showGoogleDeviceDialog(context, account)),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.pump();
    return results;
  }

  /// The label of the focused button, if a button has the focus.
  String? focusedLabel() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? label;
    context.visitChildElements((element) {
      void visit(Element e) {
        final widget = e.widget;
        if (label == null && widget is Text) label = widget.data;
        e.visitChildElements(visit);
      }

      visit(element);
    });
    return label;
  }

  testWidgets('shows the code, the QR and the time left', (tester) async {
    await pumpOpener(tester);

    expect(find.text('Entrar con Google'), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.textContaining('google.com/device'), findsWidgets);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr, isNotNull);
    expect(find.text('Caduca en 30:00'), findsOneWidget);
    expect(focusedLabel(), 'Cancelar');

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Caduca en 28:59'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  for (final (reply, message) in [
    ('access_denied', 'Se ha denegado el acceso con Google.'),
    ('expired_token', 'El código ha caducado.'),
  ]) {
    testWidgets('$reply shows its message and "Reintentar"', (tester) async {
      google.tokenReplies.add(_FakeGoogle.error(reply));
      await pumpOpener(tester);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.textContaining(message), findsOneWidget);
      expect(find.text('ABCD-EFGH'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(focusedLabel(), 'Reintentar');

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(google.codeRequests, 2);
      expect(find.text('ABCD-EFGH'), findsOneWidget);
      expect(focusedLabel(), 'Cancelar');

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('no network shows its message and "Reintentar"', (tester) async {
    google.offline = true;
    await pumpOpener(tester);

    expect(find.textContaining('No se ha podido conectar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(focusedLabel(), 'Reintentar');

    google.offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('ABCD-EFGH'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('Back closes the dialog and stops polling', (tester) async {
    final results = await pumpOpener(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(google.tokenRequests, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Entrar con Google'), findsNothing);
    expect(results, [false]);
    await tester.pump(const Duration(minutes: 1));
    expect(google.tokenRequests, 1);
  });

  testWidgets('the id_token signs in and closes the dialog', (tester) async {
    google.tokenReplies
      ..add(_FakeGoogle.error('authorization_pending'))
      ..add(http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200));
    final results = await pumpOpener(tester);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(auth.lastIdToken, 'id-token-xyz');
    expect(account.status, AccountStatus.signedIn);
    expect(results, [true]);
    expect(find.text('Entrar con Google'), findsNothing);
    // Stops the periodic sync before the test ends.
    await account.signOut();
  });

  testWidgets('an account with a password closes it too (to Cuenta)', (
    tester,
  ) async {
    google.tokenReplies.add(
      http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200),
    );
    final results = await pumpOpener(tester);
    // The account already has a password profile (made elsewhere).
    await backend.saveProfile(
      const RemoteProfile(kdfSalt: 'c2FsdA==', wrappedKey: 'a2V5'),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(account.status, AccountStatus.needsPassword);
    expect(results, [true]);
    await account.signOut();
  });

  testWidgets('a refused token shows the account error and "Reintentar"', (
    tester,
  ) async {
    google.tokenReplies.add(
      http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200),
    );
    final results = await pumpOpener(tester);
    auth.oauthError = const AccountException(_refused);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text(_refused), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(results, isEmpty);
    expect(account.status, AccountStatus.signedOut);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets(
    'an unexpected error shows the network message and "Reintentar"',
    (tester) async {
      google.unexpected = StateError('boom');
      await pumpOpener(tester);

      expect(find.textContaining('No se ha podido conectar'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('"Reintentar" pressed twice asks for one code', (tester) async {
    google.offline = true;
    await pumpOpener(tester);
    google.offline = false;

    final retry = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reintentar'),
    );
    retry.onPressed!();
    retry.onPressed!();
    await tester.pump();
    await tester.pump();

    expect(google.codeRequests, 1);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('while signing in it cannot be cancelled nor closed', (
    tester,
  ) async {
    google.tokenReplies.add(
      http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200),
    );
    final results = await pumpOpener(tester);
    final gate = auth.idTokenGate = Completer<void>();

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Entrando en tu cuenta…'), findsOneWidget);
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancelar'),
    );
    expect(cancel.onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Entrar con Google'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(account.status, AccountStatus.signedIn);
    await account.signOut();
  });
}
