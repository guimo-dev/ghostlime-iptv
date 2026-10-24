import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/vod/movie_detail_screen.dart';
import 'package:iptv_player/vod/series_detail_screen.dart';

const _item = Channel(
  key: 'k',
  name: 'Algo',
  categoryId: 'c',
  kind: MediaKind.movie,
  url: 'http://h/1',
);

/// Opens the page built by [page] over a home screen and presses Esc.
Future<void> _escapeFrom(
  WidgetTester tester,
  Widget Function(CatalogDb, Playlist) page,
) async {
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  final unsaved = Playlist(
    name: 'Lista',
    type: PlaylistType.m3uUrl,
    source: 'http://h/l.m3u',
  );
  final playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page(db, playlist))),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(find.text('abrir'), findsNothing);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.text('abrir'), findsOneWidget);
}

void main() {
  testWidgets('Esc leaves the movie page', (tester) async {
    await _escapeFrom(
      tester,
      (db, playlist) => MovieDetailScreen(
        db: db,
        playlist: playlist,
        passwords: MemoryPasswordStore(),
        movie: _item,
      ),
    );
  });

  testWidgets('Esc leaves the series page', (tester) async {
    await _escapeFrom(
      tester,
      (db, playlist) => SeriesDetailScreen(
        db: db,
        playlist: playlist,
        passwords: MemoryPasswordStore(),
        series: _item,
        m3uEpisodes: const [_item],
      ),
    );
  });

  testWidgets('Esc leaves a series page without episodes or focus', (
    tester,
  ) async {
    await _escapeFrom(
      tester,
      (db, playlist) => SeriesDetailScreen(
        db: db,
        playlist: playlist,
        passwords: MemoryPasswordStore(),
        series: _item,
        m3uEpisodes: const [],
      ),
    );
  });
}
