import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

Channel _channel(String key, String name) => Channel(
  key: key,
  name: name,
  categoryId: 'c',
  kind: MediaKind.live,
  url: 'http://h/$key',
);

/// A category with separator-looking names between channels: nothing marks
/// them as separators, so they are channels like any other.
final _channels = [
  _channel('s1', '##### ES - DEPORTES #####'),
  _channel('a', 'La 1'),
  _channel('s2', '------'),
  _channel('b', 'La 1'),
  _channel('s3', '------'),
];

void main() {
  late CatalogDb db;
  late Playlist playlist;

  setUp(() {
    db = CatalogDb.inMemory();
    const unsaved = Playlist(
      name: 'Lista',
      type: PlaylistType.m3uUrl,
      source: 'http://h/l.m3u',
    );
    playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
    db.replaceCatalog(
      playlist.id!,
      const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
      _channels,
      DateTime.now(),
    );
  });
  tearDown(() => db.close());

  /// Live TV with default settings (separators shown), on the category.
  Future<void> pumpLive(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cat'));
    await tester.pump();
  }

  testWidgets('by default separators are ordinary channels in provider order', (
    tester,
  ) async {
    await pumpLive(tester);
    final rows = tester.widgetList<ChannelRow>(find.byType(ChannelRow));
    expect(rows.map((row) => row.channel.key), ['s1', 'a', 's2', 'b', 's3']);
    expect(rows.map((row) => row.number), [1, 2, 3, 4, 5]);
    expect(rows.map((row) => row.name), [
      '##### ES - DEPORTES #####',
      'La 1',
      '------',
      'La 1 · 2',
      '------ · 2',
    ]);
  });
}
