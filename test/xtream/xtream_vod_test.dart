import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/xtream/xtream_client.dart';
import 'package:iptv_player/xtream/xtream_credentials.dart';
import 'package:iptv_player/xtream/xtream_models.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

void main() {
  group('VodStream.fromJson', () {
    test('parses a real provider entry', () {
      final vod = VodStream.fromJson({
        'stream_id': 9,
        'name': 'Dune',
        'stream_icon': 'http://img/dune.jpg',
        'rating': '6.5',
        'category_id': '12',
        'container_extension': 'mkv',
      });
      expect(vod.streamId, 9);
      expect(vod.name, 'Dune');
      expect(vod.categoryId, '12');
      expect(vod.iconUrl, 'http://img/dune.jpg');
      expect(vod.extension, 'mkv');
      expect(vod.rating, 6.5);
    });

    test('tolerates empty rating, null icon and numeric category', () {
      final vod = VodStream.fromJson({
        'stream_id': '3',
        'name': 'X',
        'stream_icon': null,
        'rating': '',
        'category_id': 4,
        'container_extension': '',
      });
      expect(vod.streamId, 3);
      expect(vod.categoryId, '4');
      expect(vod.iconUrl, isNull);
      expect(vod.rating, isNull);
      expect(vod.extension, isNull);
    });
  });

  group('SeriesItem.fromJson', () {
    test('parses a real provider entry', () {
      final series = SeriesItem.fromJson({
        'series_id': 5,
        'name': 'Dark',
        'cover': 'http://img/dark.jpg',
        'plot': 'Winden',
        'genre': 'Drama',
        'releaseDate': '2017-12-01',
        'rating': '8.7',
        'category_id': '1',
      });
      expect(series.seriesId, 5);
      expect(series.name, 'Dark');
      expect(series.categoryId, '1');
      expect(series.coverUrl, 'http://img/dark.jpg');
      expect(series.rating, 8.7);
    });

    test('empty rating is null', () {
      expect(
        SeriesItem.fromJson({'series_id': 1, 'rating': ''}).rating,
        isNull,
      );
    });
  });

  group('SeriesInfo.fromJson', () {
    Map<String, dynamic> episode(int id, int number, {Object? season}) => {
      'id': id,
      'episode_num': number,
      'title': 'T$number',
      'container_extension': 'mp4',
      'season': ?season,
      'info': {'plot': 'p', 'duration_secs': 1500, 'movie_image': 'http://i'},
    };

    test('parses episodes keyed by season, sorted', () {
      final info = SeriesInfo.fromJson({
        'info': {
          'plot': 'Plot',
          'genre': 'Drama',
          'releaseDate': '2017',
          'cover': 'http://c',
        },
        'seasons': [],
        'episodes': {
          '2': [episode(30, 1, season: 2)],
          '1': [episode(11, 2, season: 1), episode(10, 1, season: 1)],
        },
      });
      expect(info.plot, 'Plot');
      expect(info.genre, 'Drama');
      expect(info.releaseDate, '2017');
      expect(info.coverUrl, 'http://c');
      expect(info.seasons.keys, [1, 2]);
      expect(info.seasons[1]!.map((e) => e.id), [10, 11]);
      final first = info.seasons[1]!.first;
      expect(first.number, 1);
      expect(first.title, 'T1');
      expect(first.extension, 'mp4');
      expect(first.plot, 'p');
      expect(first.durationSecs, 1500);
      expect(first.imageUrl, 'http://i');
    });

    test('accepts episodes as a flat list grouped by season', () {
      final info = SeriesInfo.fromJson({
        'info': {},
        'episodes': [
          episode(2, 1, season: 2),
          episode(1, 1, season: 1),
          episode(3, 2, season: '2'),
        ],
      });
      expect(info.seasons.keys, [1, 2]);
      expect(info.seasons[2]!.map((e) => e.id), [2, 3]);
    });

    test('season comes from the map key when the episode has none', () {
      final info = SeriesInfo.fromJson({
        'episodes': {
          '3': [episode(1, 1)],
        },
      });
      expect(info.seasons.keys, [3]);
    });

    test('drops seasons without episodes', () {
      final info = SeriesInfo.fromJson({
        'episodes': {
          '1': [],
          '2': [episode(1, 1, season: 2)],
        },
      });
      expect(info.seasons.keys, [2]);
    });

    test('info as an empty list and missing episodes give an empty result', () {
      final info = SeriesInfo.fromJson({'info': [], 'episodes': []});
      expect(info.plot, isNull);
      expect(info.seasons, isEmpty);
      expect(SeriesInfo.fromJson({'info': []}).seasons, isEmpty);
    });

    test('episode info as an empty list and string duration', () {
      final info = SeriesInfo.fromJson({
        'episodes': {
          '1': [
            {'id': '7', 'episode_num': '1', 'title': 'A', 'info': []},
            {
              'id': 8,
              'episode_num': 2,
              'info': {'duration_secs': '60'},
            },
          ],
        },
      });
      final episodes = info.seasons[1]!;
      expect(episodes.first.id, 7);
      expect(episodes.first.plot, isNull);
      expect(episodes.first.durationSecs, isNull);
      expect(episodes.first.extension, isNull);
      expect(episodes.last.durationSecs, 60);
      expect(episodes.last.title, '');
    });
  });

  group('MovieInfo.fromJson', () {
    test('parses a real provider answer', () {
      final info = MovieInfo.fromJson({
        'info': {
          'plot': 'Arrakis',
          'genre': 'Sci-Fi',
          'director': 'Denis',
          'cast': 'Timothée',
          'releasedate': '2021-09-15',
          'duration_secs': '9360',
          'cover_big': 'http://big',
        },
        'movie_data': {'stream_id': 9},
      });
      expect(info.plot, 'Arrakis');
      expect(info.genre, 'Sci-Fi');
      expect(info.director, 'Denis');
      expect(info.cast, 'Timothée');
      expect(info.releaseDate, '2021-09-15');
      expect(info.durationSecs, 9360);
    });

    test('info as an empty list gives empty fields', () {
      final info = MovieInfo.fromJson({'info': []});
      expect(info.plot, isNull);
      expect(info.durationSecs, isNull);
    });
  });

  group('movieUrl and episodeUrl', () {
    const credentials = XtreamCredentials('http://h', 'u', 'p');

    test('build the movie and episode paths', () {
      expect(movieUrl(credentials, 9, 'mkv'), 'http://h/movie/u/p/9.mkv');
      expect(episodeUrl(credentials, 77, 'mp4'), 'http://h/series/u/p/77.mp4');
    });

    test('encode special characters in credentials', () {
      const special = XtreamCredentials('http://h', 'a b', 'p/w?');
      expect(
        movieUrl(special, 1, 'mp4'),
        'http://h/movie/a%20b/p%2Fw%3F/1.mp4',
      );
    });

    test('missing or empty extension defaults to mp4', () {
      expect(movieUrl(credentials, 9, null), 'http://h/movie/u/p/9.mp4');
      expect(episodeUrl(credentials, 7, ''), 'http://h/series/u/p/7.mp4');
    });
  });

  group('XtreamClient VOD calls', () {
    XtreamClient clientFor(Object body, void Function(Uri) onRequest) {
      return XtreamClient(
        const XtreamCredentials('http://h', 'u', 'p'),
        httpClient: MockClient((request) async {
          onRequest(request.url);
          return http.Response(jsonEncode(body), 200);
        }),
      );
    }

    test('getVodStreams and getSeries parse lists; {} is empty', () async {
      late Uri uri;
      final vod = clientFor([
        {'stream_id': 1, 'name': 'A', 'category_id': '1'},
      ], (u) => uri = u);
      expect((await vod.getVodStreams()).single.streamId, 1);
      expect(uri.queryParameters['action'], 'get_vod_streams');
      final series = clientFor(<String, Object>{}, (u) => uri = u);
      expect(await series.getSeries(), isEmpty);
      expect(uri.queryParameters['action'], 'get_series');
    });

    test('categories use the live category format', () async {
      late Uri uri;
      final client = clientFor([
        {'category_id': '5', 'category_name': 'Cine'},
      ], (u) => uri = u);
      expect((await client.getVodCategories()).single.name, 'Cine');
      expect(uri.queryParameters['action'], 'get_vod_categories');
      await client.getSeriesCategories();
      expect(uri.queryParameters['action'], 'get_series_categories');
    });

    test('getSeriesInfo and getVodInfo send the id', () async {
      late Uri uri;
      final client = clientFor({'info': []}, (u) => uri = u);
      await client.getSeriesInfo(5);
      expect(uri.queryParameters['action'], 'get_series_info');
      expect(uri.queryParameters['series_id'], '5');
      await client.getVodInfo(9);
      expect(uri.queryParameters['action'], 'get_vod_info');
      expect(uri.queryParameters['vod_id'], '9');
    });

    test('a non-object answer gives an empty info', () async {
      final client = clientFor(<Object>[], (_) {});
      expect((await client.getSeriesInfo(1)).seasons, isEmpty);
      expect((await client.getVodInfo(1)).plot, isNull);
    });
  });
}
