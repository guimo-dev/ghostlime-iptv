import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_models.dart';

const _playlist = Playlist(
  name: 'X',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
);

const _movieChannel = Channel(
  key: 'xm:9',
  name: 'Dune',
  categoryId: 'movie:1',
  kind: MediaKind.movie,
  streamId: 9,
  extension: 'mkv',
);

const _seriesChannel = Channel(
  key: 'xs:5',
  name: 'Dark',
  categoryId: 'series:1',
  kind: MediaKind.series,
  streamId: 5,
);

PlayTarget _movie(int id) => PlayTarget(
  kind: MediaKind.movie,
  key: 'xm:$id',
  title: 'Movie $id',
  iconUrl: 'http://img/$id',
  xtreamType: XtreamStreamType.movie,
  xtreamId: id,
  extension: 'mkv',
);

void main() {
  late CatalogDb db;
  late int id;
  const total = Duration(minutes: 100);

  setUp(() {
    db = CatalogDb.inMemory();
    id = db.savePlaylist(_playlist);
  });
  tearDown(() => db.close());

  test('saves and reads back a progress with its target', () {
    final target = PlayTarget.fromChannel(_movieChannel);
    db.saveProgress(id, target, const Duration(minutes: 5), total);
    final progress = db.progress(id, MediaKind.movie, 'xm:9')!;
    expect(progress.position, const Duration(minutes: 5));
    expect(progress.duration, total);
    expect(progress.target.title, 'Dune');
    expect(progress.target.xtreamType, XtreamStreamType.movie);
    expect(progress.target.xtreamId, 9);
    expect(progress.target.extension, 'mkv');
    expect(db.progress(id, MediaKind.movie, 'xm:1'), isNull);
  });

  test('saving again replaces the position', () {
    final target = _movie(1);
    db.saveProgress(id, target, const Duration(minutes: 5), total);
    db.saveProgress(id, target, const Duration(minutes: 8), total);
    expect(
      db.progress(id, MediaKind.movie, 'xm:1')!.position,
      const Duration(minutes: 8),
    );
  });

  test('continueWatching skips under 60 s and from 95 %', () {
    db.saveProgress(id, _movie(1), const Duration(seconds: 30), total);
    db.saveProgress(id, _movie(2), const Duration(minutes: 50), total);
    db.saveProgress(id, _movie(3), const Duration(minutes: 99), total);
    expect(db.continueWatching(id, MediaKind.movie).map((p) => p.target.key), [
      'xm:2',
    ]);
  });

  test('continueWatching is newest first and respects the limit', () {
    final base = DateTime.utc(2026, 10, 19, 12);
    for (var i = 1; i <= 3; i++) {
      db.saveProgress(
        id,
        _movie(i),
        const Duration(minutes: 10),
        total,
        at: base.add(Duration(minutes: i)),
      );
    }
    db.saveProgress(
      id,
      _movie(1),
      const Duration(minutes: 11),
      total,
      at: base.add(const Duration(minutes: 10)),
    );
    expect(db.continueWatching(id, MediaKind.movie).map((p) => p.target.key), [
      'xm:1',
      'xm:3',
      'xm:2',
    ]);
    expect(db.continueWatching(id, MediaKind.movie, limit: 2), hasLength(2));
  });

  test('a movie removed from the catalog still shows with its title', () {
    db.replaceCatalog(
      id,
      const [Category(id: 'movie:1', name: 'Cine', kind: MediaKind.movie)],
      const [_movieChannel],
      DateTime.utc(2026, 10, 19),
    );
    db.saveProgress(
      id,
      PlayTarget.fromChannel(_movieChannel),
      const Duration(minutes: 50),
      total,
    );
    db.replaceCatalog(id, const [], const [], DateTime.utc(2026, 10, 20));
    final shown = db.continueWatching(id, MediaKind.movie).single;
    expect(shown.target.title, 'Dune');
    expect(shown.target.xtreamId, 9);
  });

  test('series progress holds episodes and is separate from movies', () {
    final episode = PlayTarget.episode(
      series: _seriesChannel,
      episode: const Episode(
        id: 77,
        season: 1,
        number: 2,
        title: 'Secrets',
        extension: 'mp4',
      ),
    );
    db.saveProgress(id, episode, const Duration(minutes: 20), total);
    db.saveProgress(id, _movie(1), const Duration(minutes: 20), total);
    final shown = db.continueWatching(id, MediaKind.series).single;
    expect(shown.target.key, 'xe:77');
    expect(shown.target.seriesKey, 'xs:5');
    expect(db.continueWatching(id, MediaKind.movie).single.target.key, 'xm:1');
  });

  test('clearProgress removes one entry', () {
    db.saveProgress(id, _movie(1), const Duration(minutes: 20), total);
    db.clearProgress(id, MediaKind.movie, 'xm:1');
    expect(db.progress(id, MediaKind.movie, 'xm:1'), isNull);
  });

  test('deletePlaylist deletes its progress only', () {
    final other = db.savePlaylist(_playlist.copyWith(name: 'Other'));
    db.saveProgress(id, _movie(1), const Duration(minutes: 20), total);
    db.saveProgress(other, _movie(1), const Duration(minutes: 20), total);
    db.deletePlaylist(id);
    expect(db.progress(id, MediaKind.movie, 'xm:1'), isNull);
    expect(db.progress(other, MediaKind.movie, 'xm:1'), isNotNull);
  });
}
