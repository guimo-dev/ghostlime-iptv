import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/search/search_results.dart';
import 'package:iptv_player/settings/parental_session.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

void main() {
  late CatalogDb db;
  late Playlist playlist;
  late SettingsController settings;

  setUp(() {
    db = CatalogDb.inMemory();
    const unsaved = Playlist(
      name: 'Lista',
      type: PlaylistType.m3uUrl,
      source: 'http://h/l.m3u',
    );
    playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
    Channel live(String key, String name, {String category = 'c'}) => Channel(
      key: key,
      name: name,
      categoryId: category,
      kind: MediaKind.live,
      url: 'http://h/$key',
    );
    db.replaceCatalog(
      playlist.id!,
      const [
        Category(id: 'c', name: 'Noticias', kind: MediaKind.live),
        Category(id: 'n', name: 'Infantil', kind: MediaKind.live),
      ],
      [
        live('a', 'ES - Noticias 24'),
        live('b', 'ES - Noticias 24'),
        live('s', '##### Noticias 24 #####'),
        live('n', 'Noticias 24 Junior', category: 'n'),
      ],
      DateTime.now(),
    );
    settings = SettingsController(db);
  });

  tearDown(() {
    ParentalSession.unlocked.value = false;
    db.close();
  });

  Future<void> pumpResults(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SettingsScope(
        controller: settings,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SearchResults(
              db: db,
              playlist: playlist,
              passwords: MemoryPasswordStore(),
              query: 'noticias',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Titles of the result rows, in order.
  List<String> titles(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      (tile.title! as Text).data!,
  ];

  testWidgets('names follow the Live rules: duplicate suffix', (tester) async {
    await pumpResults(tester);
    expect(titles(tester), [
      'ES - Noticias 24',
      'ES - Noticias 24 · 2',
      '##### Noticias 24 #####',
      'Noticias 24 Junior',
    ]);
  });

  testWidgets('a locked group shows up once the session is unlocked', (
    tester,
  ) async {
    settings.update(
      settings.value.copyWith(
        parentalLock: true,
        lockedCategories: {'${playlist.id}/live/n'},
      ),
    );
    await pumpResults(tester);
    expect(titles(tester), isNot(contains('Noticias 24 Junior')));

    ParentalSession.unlocked.value = true;
    await tester.pump();
    expect(titles(tester), contains('Noticias 24 Junior'));
  });
}
