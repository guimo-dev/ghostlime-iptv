import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/epg_refresh.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_client.dart';

final _now = DateTime.utc(2026, 10, 19, 12);

const _m3u = Playlist(
  name: 'M3U',
  type: PlaylistType.m3uUrl,
  source: 'http://h/list.m3u',
);

const _xtream = Playlist(
  name: 'X',
  type: PlaylistType.xtream,
  serverUrl: 'http://h:8080',
  username: 'u',
);

Programme _prog(String channel, String title) => Programme(
  channelId: channel,
  start: _now,
  stop: _now.add(const Duration(hours: 1)),
  title: title,
);

/// Saves [playlist] with live channels having the given EPG ids.
(CatalogDb, Playlist) _setUp(Playlist playlist) {
  final db = CatalogDb.inMemory();
  final id = db.savePlaylist(playlist);
  db.replaceCatalog(
    id,
    const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
    const [
      Channel(
        key: '1',
        name: 'A',
        categoryId: 'c',
        kind: MediaKind.live,
        epgId: 'a.es',
      ),
      Channel(
        key: '2',
        name: 'B',
        categoryId: 'c',
        kind: MediaKind.live,
        epgId: 'b.es',
      ),
      Channel(key: '3', name: 'C', categoryId: 'c', kind: MediaKind.live),
    ],
    _now,
  );
  return (db, playlist.copyWith(id: id));
}

void main() {
  group('needsEpgRefresh', () {
    test('is true when never refreshed or older than 12 hours', () {
      expect(needsEpgRefresh(null, _now), isTrue);
      expect(
        needsEpgRefresh(_now.subtract(const Duration(hours: 13)), _now),
        isTrue,
      );
      expect(
        needsEpgRefresh(_now.subtract(const Duration(hours: 12)), _now),
        isFalse,
      );
      expect(
        needsEpgRefresh(_now.subtract(const Duration(hours: 1)), _now),
        isFalse,
      );
    });
  });

  group('epgSource', () {
    test('epgUrl wins over everything', () {
      final (db, playlist) = _setUp(_xtream.copyWith(epgUrl: 'http://g/e.xml'));
      db.saveM3uTvgUrl(playlist.id!, 'http://other/e.xml');
      expect(epgSource(db, playlist, 'pw'), Uri.parse('http://g/e.xml'));
    });

    test('Xtream falls back to xmltv.php', () {
      final (db, playlist) = _setUp(_xtream);
      final uri = epgSource(db, playlist, 'p w')!;
      expect(uri.origin, 'http://h:8080');
      expect(uri.path, '/xmltv.php');
      expect(uri.queryParameters, {'username': 'u', 'password': 'p w'});
    });

    test('M3U uses the saved url-tvg', () {
      final (db, playlist) = _setUp(_m3u);
      expect(epgSource(db, playlist, null), isNull);
      db.saveM3uTvgUrl(playlist.id!, 'http://g/e.xml.gz');
      expect(epgSource(db, playlist, null), Uri.parse('http://g/e.xml.gz'));
    });
  });

  group('refreshEpg', () {
    test('asks for live epg ids in the -6h/+72h window and stores', () async {
      final (db, playlist) = _setUp(
        _m3u.copyWith(epgUrl: 'http://g/e.xml', userAgent: 'UA'),
      );
      Set<String>? ids;
      DateTime? windowFrom;
      DateTime? windowTo;
      Uri? asked;
      String? agent;
      final count = await refreshEpg(
        db,
        playlist,
        now: () => _now,
        fetch:
            (
              url, {
              required channelIds,
              required from,
              required to,
              userAgent,
            }) async {
              asked = url;
              ids = channelIds;
              windowFrom = from;
              windowTo = to;
              agent = userAgent;
              return [_prog('a.es', 'Uno'), _prog('b.es', 'Dos')];
            },
      );
      expect(count, 2);
      expect(asked, Uri.parse('http://g/e.xml'));
      expect(ids, {'a.es', 'b.es'});
      expect(windowFrom, _now.subtract(const Duration(hours: 6)));
      expect(windowTo, _now.add(const Duration(hours: 72)));
      expect(agent, 'UA');
      expect(db.epgRefreshedAt(playlist.id!), _now);
      final stored = db.programmes(
        playlist.id!,
        ['a.es', 'b.es'],
        _now,
        windowTo!,
      );
      expect(stored.map((p) => p.title), ['Uno', 'Dos']);
    });

    test('an empty download fails and keeps the previous guide', () async {
      final (db, playlist) = _setUp(_m3u.copyWith(epgUrl: 'http://g/e.xml'));
      db.replaceEpg(playlist.id!, [_prog('a.es', 'Viejo')], _now);
      await expectLater(
        refreshEpg(
          db,
          playlist,
          now: () => _now.add(const Duration(hours: 13)),
          fetch: (
            _, {
            required channelIds,
            required from,
            required to,
            userAgent,
          }) async => const [],
        ),
        throwsA(isA<XtreamException>()),
      );
      expect(db.epgRefreshedAt(playlist.id!), _now);
      expect(
        db.programmes(
          playlist.id!,
          ['a.es'],
          _now,
          _now.add(const Duration(days: 1)),
        ),
        hasLength(1),
      );
    });

    test('a failing fetch keeps the previous guide', () async {
      final (db, playlist) = _setUp(_m3u.copyWith(epgUrl: 'http://g/e.xml'));
      db.replaceEpg(playlist.id!, [_prog('a.es', 'Viejo')], _now);
      await expectLater(
        refreshEpg(
          db,
          playlist,
          now: () => _now.add(const Duration(hours: 13)),
          fetch: (
            _, {
            required channelIds,
            required from,
            required to,
            userAgent,
          }) => throw const XtreamException('No se puede descargar la guía.'),
        ),
        throwsA(isA<XtreamException>()),
      );
      expect(db.epgRefreshedAt(playlist.id!), _now);
      expect(
        db
            .programmes(
              playlist.id!,
              ['a.es'],
              _now,
              _now.add(const Duration(days: 1)),
            )
            .single
            .title,
        'Viejo',
      );
    });

    test('without any source it throws a Spanish message', () async {
      final (db, playlist) = _setUp(_m3u);
      await expectLater(
        refreshEpg(db, playlist),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            'La lista no tiene guía de programación.',
          ),
        ),
      );
    });

    test('without live epg ids it does not download', () async {
      final db = CatalogDb.inMemory();
      final id = db.savePlaylist(_m3u.copyWith(epgUrl: 'http://g/e.xml'));
      var called = false;
      final count = await refreshEpg(
        db,
        _m3u.copyWith(id: id, epgUrl: 'http://g/e.xml'),
        fetch:
            (
              _, {
              required channelIds,
              required from,
              required to,
              userAgent,
            }) async {
              called = true;
              return [];
            },
      );
      expect(count, 0);
      expect(called, isFalse);
    });
  });
}
