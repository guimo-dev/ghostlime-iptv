import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/home/home_screen.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/backdrop.dart';

/// Pumps the home of a playlist with one half-watched movie in a window of
/// [size] and returns the height of the hero banner.
Future<double> _heroHeight(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final unsaved = Playlist(
    name: 'Lista',
    type: PlaylistType.m3uUrl,
    source: 'http://h/l.m3u',
  );
  final playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
  db.saveProgress(
    playlist.id!,
    PlayTarget.fromChannel(
      const Channel(
        key: 'm',
        name: 'Una pelicula',
        categoryId: 'c',
        kind: MediaKind.movie,
        url: 'http://h/m',
      ),
    ),
    const Duration(minutes: 40),
    const Duration(minutes: 100),
  );
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: HomeScreen(
            db: db,
            playlist: playlist,
            passwords: MemoryPasswordStore(),
            onOpenSection: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(Backdrop).first).height;
}

void main() {
  testWidgets('the hero takes at most 45% of a short window', (tester) async {
    final height = await _heroHeight(tester, const Size(1024, 700));
    expect(height, lessThanOrEqualTo(700 * 0.45));
  });

  testWidgets('the hero keeps its full height in a tall window', (
    tester,
  ) async {
    final height = await _heroHeight(tester, const Size(1440, 1200));
    expect(height, 420);
  });
}
