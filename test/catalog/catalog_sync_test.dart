import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/catalog_sync.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_client.dart';

const _xtream = Playlist(
  name: 'X',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
  userAgent: 'TestUA',
);

const _m3u = Playlist(
  name: 'M',
  type: PlaylistType.m3uUrl,
  source: 'http://h/get.php',
  userAgent: 'TestUA',
);

const _m3uBody =
    '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="a" group-title="Noticias",A\nhttp://h/live/u/p/1.ts\n'
    '#EXTINF:-1 group-title="Cine",Peli\nhttp://h/movie/u/p/2.mkv\n'
    '#EXTINF:-1 group-title="",Serie\nhttp://h/series/u/p/3.mp4\n';

/// Fake Xtream server answering by `action`.
http.Response _xtreamResponse(http.Request request) {
  final action = request.url.queryParameters['action'];
  final Object body = switch (action) {
    null => {
      'user_info': {'auth': 1},
    },
    'get_live_categories' => [
      {'category_id': '1', 'category_name': 'Uno'},
      {'category_id': '2', 'category_name': 'Dos'},
    ],
    'get_live_streams' => [
      {'stream_id': 10, 'name': 'A', 'category_id': '1'},
      {'stream_id': 11, 'name': 'B', 'category_id': '1'},
      {'stream_id': 12, 'name': 'C', 'category_id': '2'},
    ],
    'get_vod_categories' => [
      {'category_id': '7', 'category_name': 'Cine'},
    ],
    'get_vod_streams' => [
      {
        'stream_id': 20,
        'name': 'Dune',
        'category_id': '7',
        'container_extension': 'mkv',
        'rating': '6.5',
        'stream_icon': 'http://img/dune.jpg',
      },
      {'stream_id': 21, 'name': 'Arrival', 'category_id': '7'},
    ],
    'get_series_categories' => [
      {'category_id': '1', 'category_name': 'Drama'},
    ],
    'get_series' => [
      {
        'series_id': 30,
        'name': 'Dark',
        'category_id': '1',
        'cover': 'http://c',
      },
    ],
    _ => <Object>[],
  };
  return http.Response(jsonEncode(body), 200);
}

void main() {
  late CatalogDb db;
  final now = DateTime.utc(2026, 10, 19, 12);

  setUp(() => db = CatalogDb.inMemory());
  tearDown(() => db.close());

  group('needsRefresh', () {
    test('null or older than 24 h needs refresh', () {
      expect(needsRefresh(null, now), isTrue);
      expect(
        needsRefresh(now.subtract(const Duration(hours: 23)), now),
        isFalse,
      );
      expect(
        needsRefresh(now.subtract(const Duration(hours: 25)), now),
        isTrue,
      );
    });
  });

  test('syncs an Xtream playlist', () async {
    final id = db.savePlaylist(_xtream);
    final result = await syncPlaylist(
      db,
      _xtream.copyWith(id: id),
      password: 'p',
      httpClient: MockClient((r) async => _xtreamResponse(r)),
      now: () => now,
    );
    expect((result.live, result.movies, result.series), (3, 2, 1));
    expect(db.categories(id, MediaKind.live).map((c) => c.name), [
      'Uno',
      'Dos',
    ]);
    final channels = db.channels(id, '1');
    expect(channels.map((c) => c.key), ['x:10', 'x:11']);
    expect(channels.first.streamId, 10);
    expect(db.playlists().single.refreshedAt, now);
  });

  test('syncs Xtream movies and series with their own keys', () async {
    final id = db.savePlaylist(_xtream);
    await syncPlaylist(
      db,
      _xtream.copyWith(id: id),
      password: 'p',
      httpClient: MockClient((r) async => _xtreamResponse(r)),
      now: () => now,
    );
    final movieCategory = db.categories(id, MediaKind.movie).single;
    expect(movieCategory.name, 'Cine');
    final movies = db.channels(id, movieCategory.id);
    expect(movies.map((c) => c.key), ['xm:20', 'xm:21']);
    expect(movies.first.kind, MediaKind.movie);
    expect(movies.first.streamId, 20);
    expect(movies.first.extension, 'mkv');
    expect(movies.first.rating, 6.5);
    expect(movies.first.iconUrl, 'http://img/dune.jpg');
    final seriesCategory = db.categories(id, MediaKind.series).single;
    final series = db.channels(id, seriesCategory.id).single;
    expect(series.key, 'xs:30');
    expect(series.kind, MediaKind.series);
    expect(series.streamId, 30);
    // Live category "1" and series category "1" must not share channels.
    expect(db.channels(id, '1').map((c) => c.key), ['x:10', 'x:11']);
  });

  test('empty Xtream movies and series do not fail the sync', () async {
    final id = db.savePlaylist(_xtream);
    final client = MockClient(
      (r) async => switch (r.url.queryParameters['action']) {
        'get_vod_streams' || 'get_series' => http.Response('{}', 200),
        _ => _xtreamResponse(r),
      },
    );
    final result = await syncPlaylist(
      db,
      _xtream.copyWith(id: id),
      password: 'p',
      httpClient: client,
      now: () => now,
    );
    expect((result.live, result.movies, result.series), (3, 0, 0));
    expect(db.channelCount(id, MediaKind.movie), 0);
  });

  test('syncs an M3U playlist by kind', () async {
    final id = db.savePlaylist(_m3u);
    final result = await syncPlaylist(
      db,
      _m3u.copyWith(id: id),
      httpClient: MockClient((_) async => http.Response(_m3uBody, 200)),
      now: () => now,
    );
    expect((result.live, result.movies, result.series), (1, 1, 1));
    final live = db.categories(id, MediaKind.live);
    expect(live.map((c) => c.name), ['Noticias']);
    expect(
      db.channels(id, live.single.id).single.url,
      'http://h/live/u/p/1.ts',
    );
    expect(db.categories(id, MediaKind.series).single.name, 'Sin categoría');
  });

  test('sends the playlist User-Agent', () async {
    final agents = <String?>[];
    final client = MockClient((r) async {
      agents.add(r.headers['User-Agent']);
      return r.url.path.endsWith('player_api.php')
          ? _xtreamResponse(r)
          : http.Response(_m3uBody, 200);
    });
    await syncPlaylist(
      db,
      _xtream.copyWith(id: db.savePlaylist(_xtream)),
      password: 'p',
      httpClient: client,
      now: () => now,
    );
    await syncPlaylist(
      db,
      _m3u.copyWith(id: db.savePlaylist(_m3u)),
      httpClient: client,
      now: () => now,
    );
    expect(agents, isNotEmpty);
    expect(agents, everyElement('TestUA'));
  });

  test(
    'an Xtream answer without channels fails and keeps the catalog',
    () async {
      final playlist = _xtream.copyWith(id: db.savePlaylist(_xtream));
      await syncPlaylist(
        db,
        playlist,
        password: 'p',
        httpClient: MockClient((r) async => _xtreamResponse(r)),
        now: () => now,
      );
      final empty = MockClient(
        (r) async => r.url.queryParameters['action'] == 'get_live_streams'
            ? http.Response('{}', 200)
            : _xtreamResponse(r),
      );
      await expectLater(
        syncPlaylist(
          db,
          playlist,
          password: 'p',
          httpClient: empty,
          now: () => now,
        ),
        throwsA(isA<XtreamException>()),
      );
      expect(db.channelCount(playlist.id!, MediaKind.live), 3);
    },
  );

  test('a failed sync keeps the previous catalog', () async {
    final playlist = _m3u.copyWith(id: db.savePlaylist(_m3u));
    await syncPlaylist(
      db,
      playlist,
      httpClient: MockClient((_) async => http.Response(_m3uBody, 200)),
      now: () => now,
    );
    await expectLater(
      syncPlaylist(
        db,
        playlist,
        httpClient: MockClient((_) async => http.Response('boom', 500)),
        now: () => now,
      ),
      throwsA(isA<XtreamException>()),
    );
    expect(db.channelCount(playlist.id!, MediaKind.live), 1);
  });

  test('an M3U without entries fails and keeps the catalog', () async {
    final playlist = _m3u.copyWith(id: db.savePlaylist(_m3u));
    await syncPlaylist(
      db,
      playlist,
      httpClient: MockClient((_) async => http.Response(_m3uBody, 200)),
      now: () => now,
    );
    await expectLater(
      syncPlaylist(
        db,
        playlist,
        httpClient: MockClient(
          (_) async => http.Response('<html>login</html>', 200),
        ),
        now: () => now,
      ),
      throwsA(
        isA<XtreamException>().having(
          (e) => e.message,
          'message',
          contains('no contiene canales'),
        ),
      ),
    );
    expect(db.channelCount(playlist.id!, MediaKind.live), 1);
  });

  test(
    'a failed sync records its error and a later success clears it',
    () async {
      final playlist = _m3u.copyWith(id: db.savePlaylist(_m3u));
      await expectLater(
        syncPlaylist(
          db,
          playlist,
          httpClient: MockClient((_) async => http.Response('boom', 503)),
          now: () => now,
        ),
        throwsA(isA<XtreamException>()),
      );
      expect(db.syncError(playlist.id!), contains('HTTP 503'));

      await syncPlaylist(
        db,
        playlist,
        httpClient: MockClient((_) async => http.Response(_m3uBody, 200)),
        now: () => now,
      );
      expect(db.syncError(playlist.id!), isNull);
    },
  );

  test('any other failure records a generic message, never its text', () async {
    final playlist = _m3u.copyWith(id: db.savePlaylist(_m3u));
    await expectLater(
      syncPlaylist(
        db,
        playlist,
        httpClient: MockClient((_) async => http.Response(_m3uBody, 200)),
        now: () => throw StateError('http://user:secret@host/x'),
      ),
      throwsStateError,
    );
    expect(db.syncError(playlist.id!), syncFailedMessage);
  });

  group('checkPlaylistSource', () {
    http.Client auth(Object value) => MockClient(
      (_) async => http.Response(
        jsonEncode({
          'user_info': {'auth': value},
        }),
        200,
      ),
    );

    test('accepted Xtream credentials give no error', () async {
      expect(
        await checkPlaylistSource(_xtream, password: 'p', httpClient: auth(1)),
        isNull,
      );
    });

    test('rejected Xtream credentials give a Spanish error', () async {
      expect(
        await checkPlaylistSource(_xtream, password: 'x', httpClient: auth(0)),
        contains('rechazado las credenciales'),
      );
    });

    test('a down Xtream server gives its HTTP error', () async {
      expect(
        await checkPlaylistSource(
          _xtream,
          password: 'p',
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
        contains('HTTP 503'),
      );
    });

    test('a malformed server address gives a fixed Spanish error', () async {
      expect(
        await checkPlaylistSource(
          _xtream.copyWith(serverUrl: 'http://host:abc'),
          password: 'p',
          httpClient: auth(1),
        ),
        'La dirección del servidor no es válida.',
      );
    });

    test('a server that never answers times out', () async {
      expect(
        await checkPlaylistSource(
          _xtream,
          password: 'p',
          httpClient: MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 50),
        ),
        'El servidor no responde (tiempo agotado).',
      );
    });

    test('M3U playlists are not checked', () async {
      var requests = 0;
      expect(
        await checkPlaylistSource(
          _m3u,
          httpClient: MockClient((_) async {
            requests++;
            return http.Response('', 503);
          }),
        ),
        isNull,
      );
      expect(requests, 0);
    });
  });
}
