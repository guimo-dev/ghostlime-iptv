import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/player/stream_url.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_models.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

const _xtream = Playlist(
  id: 1,
  name: 'X',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
);

const _m3u = Playlist(id: 2, name: 'M', type: PlaylistType.m3uUrl, source: 's');

const _live = Channel(
  key: 'x:1',
  name: 'Canal',
  categoryId: '1',
  kind: MediaKind.live,
  streamId: 1,
);

const _movie = Channel(
  key: 'xm:9',
  name: 'Dune',
  categoryId: 'movie:1',
  kind: MediaKind.movie,
  streamId: 9,
  extension: 'mkv',
  iconUrl: 'http://img',
);

const _series = Channel(
  key: 'xs:5',
  name: 'Dark',
  categoryId: 'series:1',
  kind: MediaKind.series,
  streamId: 5,
  iconUrl: 'http://cover',
);

const _episode = Episode(
  id: 77,
  season: 1,
  number: 2,
  title: 'Secrets',
  extension: 'mp4',
);

void main() {
  group('PlayTarget', () {
    test('fromChannel copies a live channel and a movie', () {
      final live = PlayTarget.fromChannel(_live);
      expect(live.xtreamType, XtreamStreamType.live);
      expect(live.xtreamId, 1);
      expect(live.key, 'x:1');
      expect(live.title, 'Canal');
      final movie = PlayTarget.fromChannel(_movie);
      expect(movie.kind, MediaKind.movie);
      expect(movie.xtreamType, XtreamStreamType.movie);
      expect(movie.extension, 'mkv');
      expect(movie.iconUrl, 'http://img');
    });

    test('fromChannel of an M3U item keeps its URL and no Xtream type', () {
      final target = PlayTarget.fromChannel(
        const Channel(
          key: 't:a',
          name: 'A',
          categoryId: 'c',
          kind: MediaKind.movie,
          url: 'http://h/a.mkv',
        ),
      );
      expect(target.xtreamType, isNull);
      expect(target.url, 'http://h/a.mkv');
    });

    test('episode keys on the episode id and points back to its series', () {
      final target = PlayTarget.episode(series: _series, episode: _episode);
      expect(target.kind, MediaKind.series);
      expect(target.key, 'xe:77');
      expect(target.seriesKey, 'xs:5');
      expect(target.xtreamType, XtreamStreamType.series);
      expect(target.xtreamId, 77);
      expect(target.title, contains('Dark'));
      expect(target.title, contains('Secrets'));
      expect(target.iconUrl, 'http://cover');
    });
  });

  group('playTargetUrl', () {
    test('Xtream movie', () {
      expect(
        playTargetUrl(_xtream, PlayTarget.fromChannel(_movie), 'p'),
        'http://h/movie/u/p/9.mkv',
      );
    });

    test('Xtream episode', () {
      expect(
        playTargetUrl(
          _xtream,
          PlayTarget.episode(series: _series, episode: _episode),
          'p',
        ),
        'http://h/series/u/p/77.mp4',
      );
    });

    test('Xtream live uses the playlist format', () {
      expect(
        playTargetUrl(_xtream, PlayTarget.fromChannel(_live), 'p'),
        'http://h/live/u/p/1.ts',
      );
      expect(
        playTargetUrl(
          _xtream.copyWith(liveFormat: LiveFormat.m3u8),
          PlayTarget.fromChannel(_live),
          'p',
        ),
        'http://h/live/u/p/1.m3u8',
      );
    });

    test('M3U uses the stored URL', () {
      const target = PlayTarget(
        kind: MediaKind.live,
        key: 't:a',
        title: 'A',
        url: 'http://h/a.ts',
      );
      expect(playTargetUrl(_m3u, target, null), 'http://h/a.ts');
    });

    test('Xtream without password gives null', () {
      expect(
        playTargetUrl(_xtream, PlayTarget.fromChannel(_movie), null),
        isNull,
      );
    });
  });

  group('Progress.isUnfinished', () {
    Progress progress(Duration position, Duration duration) => Progress(
      target: PlayTarget.fromChannel(_movie),
      position: position,
      duration: duration,
      updatedAt: DateTime.utc(2026),
    );

    test('needs more than 60 s and less than 95 %', () {
      const total = Duration(minutes: 100);
      expect(
        progress(const Duration(seconds: 30), total).isUnfinished,
        isFalse,
      );
      expect(
        progress(const Duration(seconds: 60), total).isUnfinished,
        isFalse,
      );
      expect(progress(const Duration(minutes: 50), total).isUnfinished, isTrue);
      expect(
        progress(const Duration(minutes: 95), total).isUnfinished,
        isFalse,
      );
      expect(
        progress(const Duration(minutes: 99), total).isUnfinished,
        isFalse,
      );
    });
  });
}
