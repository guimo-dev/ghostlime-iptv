import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';

import 'support/harness.dart';

/// Opens "Añadir lista" and fills in the demo server as an Xtream playlist
/// with [password].
Future<void> _fillXtreamForm(
  WidgetTester tester,
  AppHarness harness, {
  required String password,
}) async {
  await tester.tap(find.text('Añadir lista'));
  await tester.pumpAndSettle();
  Future<void> fill(String label, String value) =>
      tester.enterText(find.widgetWithText(TextFormField, label), value);
  await fill('Nombre', 'Demo');
  await fill('Servidor', harness.server.baseUrl.toString());
  await fill('Usuario', 'demo');
  await fill('Contraseña', password);
}

/// Taps "Guardar" and pumps until [finder] shows up or [limit] passes, then
/// lets transitions finish; returns how long [finder] took to show up.
Future<Duration> _saveUntil(
  WidgetTester tester,
  Finder finder, {
  Duration limit = const Duration(seconds: 25),
}) async {
  final watch = Stopwatch()..start();
  await tester.tap(find.text('Guardar'));
  while (finder.evaluate().isEmpty && watch.elapsed < limit) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  final elapsed = watch.elapsed;
  await tester.pumpAndSettle();
  return elapsed;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adding a playlist against a down server shows an error in '
      'under 20 s and the form stays editable', (tester) async {
    final harness = await AppHarness.start(tester, size: smallSize);
    addTearDown(harness.close);
    harness.server.down = true;
    await settle(tester);
    await _fillXtreamForm(tester, harness, password: 'demo');

    final error = find.textContaining('HTTP 503');
    final elapsed = await _saveUntil(tester, error);

    expect(find.byType(PlaylistFormScreen), findsOneWidget);
    expect(error, findsOneWidget);
    expect(elapsed, lessThan(const Duration(seconds: 20)));
    expect(harness.db.playlists(), isEmpty);
    final server = find.widgetWithText(TextFormField, 'Servidor');
    await tester.enterText(server, 'http://otro');
    expect(
      tester.widget<TextFormField>(server).controller!.text,
      'http://otro',
    );
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets('a wrong Xtream password is rejected in the form', (
    tester,
  ) async {
    final harness = await AppHarness.start(tester, size: smallSize);
    addTearDown(harness.close);
    await settle(tester);
    await _fillXtreamForm(tester, harness, password: 'mal');

    final error = find.textContaining('rechazado las credenciales');
    await _saveUntil(tester, error);

    expect(find.byType(PlaylistFormScreen), findsOneWidget);
    expect(error, findsOneWidget);
    expect(harness.db.playlists(), isEmpty);
  });
}
