import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/ui/tv_device.dart';

import '../tool/demo_server/demo_data.dart';
import 'support/harness.dart';

/// Demo server on the PC as the Android emulator sees it (10.0.2.2 is the
/// host's loopback). Start it with
/// `dart run tool/demo_server/main.dart --port 8899`.
const _hostDemoServer = 'http://10.0.2.2:8899';

/// A 1080p TV at density 2: on a phone or tablet this size gets the phone
/// layout, so the side bar only shows because the device is a TV.
const _tvSize = Size(960, 540);

/// Pumps (letting real time pass) until [done] is true; fails after [limit].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < limit) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: 'condition not met within $limit');
}

/// Runs on an Android TV emulator (`ghostlime_tv9`, `ghostlime_tv`): the
/// device is detected as a TV and, with the PC's demo server added as an
/// Xtream playlist, the shell shows the side bar.
///
/// That the app is in the TV launcher is checked from the PC after the run:
/// `adb shell cmd package query-activities --brief -a
/// android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER`
/// lists `dev.guimo.iptv_player/.MainActivity` (without `-a` it finds
/// nothing). `flutter test` uninstalls the app when it ends, so install the
/// debug APK first: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a TV gets the side bar', (tester) async {
    await detectTvDevice();
    expect(isTvDevice, isTrue);

    final harness = await AppHarness.start(tester, size: _tvSize);
    addTearDown(harness.close);
    await settle(tester);

    await tester.tap(find.text('Añadir lista'));
    await tester.pumpAndSettle();
    // On a TV a field stays read-only until it is opened (OK or a tap).
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
    }

    await fill('Nombre', 'Demo');
    await fill('Servidor', _hostDemoServer);
    await fill('Usuario', demoUser);
    await fill('Contraseña', demoPassword);
    await tester.tap(find.text('Guardar'));
    await _pumpUntil(
      tester,
      () =>
          harness.db.playlists().isNotEmpty &&
          harness.db.playlists().single.refreshedAt != null,
    );
    await _pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo'));
    await settle(tester, timeout: const Duration(seconds: 2));

    // The side bar carries Listas and Ajustes; the bottom bar would say Más.
    expect(find.text('Directo'), findsWidgets);
    expect(find.text('Listas'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Más'), findsNothing);
  });
}
