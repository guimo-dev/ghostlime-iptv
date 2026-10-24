import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

const _xtream = Playlist(
  name: 'Xtream',
  type: PlaylistType.xtream,
  serverUrl: 'http://h:8080',
  username: 'u',
  userAgent: 'UA',
  liveFormat: LiveFormat.m3u8,
);

const _m3u = Playlist(
  name: 'M3U',
  type: PlaylistType.m3uUrl,
  source: 'http://h/list.m3u',
);

Channel _channel(String key, String categoryId, {int? streamId}) => Channel(
  key: key,
  name: 'Ch $key',
  categoryId: categoryId,
  kind: MediaKind.live,
  streamId: streamId ?? 1,
);

const _categories = [
  Category(id: 'b', name: 'B', kind: MediaKind.live),
  Category(id: 'a', name: 'A', kind: MediaKind.live),
];

void main() {
  late CatalogDb db;
  final refreshed = DateTime.utc(2026, 10, 19, 12);

  setUp(() => db = CatalogDb.inMemory());
  tearDown(() => db.close());

  test('saves and reads playlists with all fields', () {
    final xtreamId = db.savePlaylist(_xtream);
    db.savePlaylist(_m3u);
    final all = db.playlists();
    expect(all.map((p) => p.name), ['M3U', 'Xtream']);
    final xtream = all.firstWhere((p) => p.id == xtreamId);
    expect(xtream.type, PlaylistType.xtream);
    expect(xtream.serverUrl, 'http://h:8080');
    expect(xtream.username, 'u');
    expect(xtream.userAgent, 'UA');
    expect(xtream.liveFormat, LiveFormat.m3u8);
    expect(xtream.refreshedAt, isNull);
    final m3u = all.firstWhere((p) => p.id != xtreamId);
    expect(m3u.source, 'http://h/list.m3u');
    expect(m3u.liveFormat, LiveFormat.ts);
  });

  test('saving with an id updates instead of duplicating', () {
    final id = db.savePlaylist(_xtream);
    db.savePlaylist(_xtream.copyWith(id: id, name: 'Renamed'));
    expect(db.playlists().map((p) => p.name), ['Renamed']);
  });

  test('updating a playlist keeps its refresh time', () {
    final id = db.savePlaylist(_xtream);
    db.replaceCatalog(id, _categories, [_channel('1', 'a')], refreshed);
    db.savePlaylist(_xtream.copyWith(id: id, name: 'Renamed'));
    expect(db.playlists().single.refreshedAt, refreshed);
  });

  test('clearCatalog empties the catalog and the refresh time', () {
    final id = db.savePlaylist(_xtream);
    db.replaceCatalog(id, _categories, [_channel('1', 'a')], refreshed);
    db.clearCatalog(id);
    expect(db.channelCount(id, MediaKind.live), 0);
    expect(db.categories(id, MediaKind.live), isEmpty);
    expect(db.playlists().single.refreshedAt, isNull);
  });

  test('replaceCatalog keeps provider order and stores refresh time', () {
    final id = db.savePlaylist(_xtream);
    db.replaceCatalog(id, _categories, [
      _channel('2', 'a'),
      _channel('1', 'a'),
      _channel('3', 'b'),
    ], refreshed);
    expect(db.categories(id, MediaKind.live).map((c) => c.id), ['b', 'a']);
    expect(db.channels(id, 'a').map((c) => c.key), ['2', '1']);
    expect(db.playlists().single.refreshedAt, refreshed);
    expect(db.channelCount(id, MediaKind.live), 3);
  });

  test('a second replaceCatalog replaces everything', () {
    final id = db.savePlaylist(_xtream);
    db.replaceCatalog(id, _categories, [_channel('1', 'a')], refreshed);
    db.replaceCatalog(
      id,
      const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
      [_channel('9', 'c')],
      refreshed,
    );
    expect(db.categories(id, MediaKind.live).map((c) => c.id), ['c']);
    expect(db.channels(id, 'a'), isEmpty);
    expect(db.channelCount(id, MediaKind.live), 1);
  });

  test('duplicate channel keys keep the first one', () {
    final id = db.savePlaylist(_xtream);
    db.replaceCatalog(id, _categories, [
      _channel('1', 'a', streamId: 10),
      _channel('1', 'b', streamId: 20),
    ], refreshed);
    final channels = db.channels(id, 'a');
    expect(channels.single.streamId, 10);
    expect(db.channels(id, 'b'), isEmpty);
  });

  test('deletePlaylist removes only that playlist and its catalog', () {
    final a = db.savePlaylist(_xtream);
    final b = db.savePlaylist(_m3u);
    db.replaceCatalog(a, _categories, [_channel('1', 'a')], refreshed);
    db.replaceCatalog(b, _categories, [_channel('1', 'a')], refreshed);
    db.deletePlaylist(a);
    expect(db.playlists().map((p) => p.id), [b]);
    expect(db.channelCount(a, MediaKind.live), 0);
    expect(db.categories(a, MediaKind.live), isEmpty);
    expect(db.channelCount(b, MediaKind.live), 1);
  });

  test('round-trips every channel field', () {
    final id = db.savePlaylist(_m3u);
    db.replaceCatalog(id, _categories, const [
      Channel(
        key: 't:x',
        name: 'X',
        categoryId: 'a',
        kind: MediaKind.movie,
        iconUrl: 'http://l/x.png',
        epgId: 'x.es',
        url: 'http://h/movie/1.mkv',
      ),
    ], refreshed);
    final channel = db.channels(id, 'a').single;
    expect(channel.kind, MediaKind.movie);
    expect(channel.iconUrl, 'http://l/x.png');
    expect(channel.epgId, 'x.es');
    expect(channel.url, 'http://h/movie/1.mkv');
    expect(channel.streamId, isNull);
    expect(db.channelCount(id, MediaKind.movie), 1);
  });

  test('replaceCatalog with 5000 channels takes under 2 s', () {
    final id = db.savePlaylist(_xtream);
    final channels = [for (var i = 0; i < 5000; i++) _channel('$i', 'a')];
    final stopwatch = Stopwatch()..start();
    db.replaceCatalog(id, _categories, channels, refreshed);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(db.channelCount(id, MediaKind.live), 5000);
  });
}
