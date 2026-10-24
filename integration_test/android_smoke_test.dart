import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:media_kit_video/media_kit_video.dart' show Video;

import '../tool/demo_server/demo_data.dart';
import 'support/harness.dart';

/// Demo server on the PC as the Android emulator sees it (10.0.2.2 is the
/// host's loopback). Start it with
/// `dart run tool/demo_server/main.dart --port 8899`.
const _hostDemoServer = 'http://10.0.2.2:8899';

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

/// Runs on the Android emulator: adds the PC's demo server as an Xtream
/// playlist, opens live TV and plays the first channel full screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the first live channel plays on Android', (tester) async {
    final harness = await AppHarness.start(tester, size: smallSize);
    addTearDown(harness.close);
    await settle(tester);

    await tester.tap(find.text('Añadir lista'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) =>
        tester.enterText(find.widgetWithText(TextFormField, label), value);
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
    await tester.tap(find.text('Directo').first);
    await settle(tester, timeout: const Duration(seconds: 2));

    // First tap previews the channel, the second opens it full screen.
    final firstChannel = find.byType(ChannelRow).first;
    await tester.tap(firstChannel);
    await settle(tester, timeout: const Duration(seconds: 2));
    await tester.tap(firstChannel);
    await _pumpUntil(
      tester,
      () => find.byType(PlayerScreen).evaluate().isNotEmpty,
    );

    final video = find.descendant(
      of: find.byType(PlayerScreen),
      matching: find.byType(Video),
    );
    final player = tester.widget<Video>(video).controller.player;
    await _pumpUntil(tester, () => player.state.position > Duration.zero);
    expect(player.state.position, greaterThan(Duration.zero));
  });
}
