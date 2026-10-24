import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';

void main() {
  late CatalogDb db;
  late int id;

  setUp(() {
    db = CatalogDb.inMemory();
    id = db.savePlaylist(
      const Playlist(name: 'A', type: PlaylistType.m3uUrl, source: 's'),
    );
    db.replaceCatalog(
      id,
      const [Category(id: 'c', name: 'C', kind: MediaKind.movie)],
      const [
        Channel(
          key: 'k',
          name: 'Peli',
          categoryId: 'c',
          kind: MediaKind.movie,
          url: 'http://h/movie/1.mp4',
        ),
      ],
      DateTime.utc(2026),
    );
  });
  tearDown(() => db.close());

  test(
    'clearRecents removes recents of every playlist and keeps favorites',
    () {
      db.addRecent(id, MediaKind.movie, 'k');
      db.setFavorite(id, MediaKind.movie, 'k', true);
      db.clearRecents();
      expect(db.recentChannels(id, MediaKind.movie), isEmpty);
      expect(db.favoriteKeys(id, MediaKind.movie), {'k'});
    },
  );

  test('clearProgress removes all saved positions', () {
    const target = PlayTarget(
      kind: MediaKind.movie,
      key: 'k',
      title: 'Peli',
      url: 'http://h/movie/1.mp4',
    );
    db.saveProgress(
      id,
      target,
      const Duration(minutes: 10),
      const Duration(minutes: 90),
    );
    db.clearProgress(id, MediaKind.movie, 'other');
    expect(db.progress(id, MediaKind.movie, 'k'), isNotNull);
    db.clearAllProgress();
    expect(db.progress(id, MediaKind.movie, 'k'), isNull);
  });
}
