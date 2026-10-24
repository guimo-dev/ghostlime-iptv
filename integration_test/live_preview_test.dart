import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import '../tool/demo_server/demo_data.dart';
import '../tool/demo_server/demo_server.dart';

/// Pumps with real time passing until [finder] matches or [limit] passes.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  Duration limit,
) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && watch.elapsed < limit) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switching the preview from a working channel to a silent one '
      'shows the start error', (tester) async {
    MediaKit.ensureInitialized();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    final demo = await DemoServer.start();
    final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final held = <HttpRequest>[];
    silent.listen(held.add);
    final db = CatalogDb.inMemory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await demo.close();
      await silent.close(force: true);
      db.close();
      tester.view.reset();
    });

    const unsaved = Playlist(
      name: 'Prueba',
      type: PlaylistType.m3uUrl,
      source: 'http://127.0.0.1/none.m3u',
    );
    final playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
    final working =
        '${demo.baseUrl.origin}/live/$demoUser/$demoPassword/'
        '${demoChannels.first.id}.ts';
    db.replaceCatalog(
      playlist.id!,
      const [Category(id: 'live:G', name: 'G', kind: MediaKind.live)],
      [
        Channel(
          key: 'm:1',
          name: 'Bueno',
          categoryId: 'live:G',
          kind: MediaKind.live,
          url: working,
        ),
        Channel(
          key: 'm:2',
          name: 'Mudo',
          categoryId: 'live:G',
          kind: MediaKind.live,
          url: 'http://127.0.0.1:${silent.port}/live.ts',
        ),
      ],
      DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(db),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LiveTvScreen(
              db: db,
              playlist: playlist,
              passwords: MemoryPasswordStore(),
              previewStartTimeout: const Duration(seconds: 4),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final failed = find.text('No se ha podido abrir el canal');

    await tester.tap(find.text('Bueno'));
    await _waitFor(tester, failed, const Duration(seconds: 6));
    expect(failed, findsNothing, reason: 'the demo channel should start');

    await tester.tap(find.text('Mudo'));
    await _waitFor(tester, failed, const Duration(seconds: 10));
    expect(failed, findsOneWidget);
  });
}
