import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/catalog_sync.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:sqlite3/sqlite3.dart';

const _playlist = Playlist(
  name: 'M3U',
  type: PlaylistType.m3uUrl,
  source: 'http://h/list.m3u',
);

final _t0 = DateTime.utc(2026, 10, 19, 12);

/// A programme of [channel] from [startMin] to [stopMin] minutes after [_t0].
Programme _prog(String channel, int startMin, int stopMin, [String? title]) =>
    Programme(
      channelId: channel,
      start: _t0.add(Duration(minutes: startMin)),
      stop: _t0.add(Duration(minutes: stopMin)),
      title: title ?? '$channel@$startMin',
      description: 'd',
    );

/// Creates a version 3 database file (no `epg_url`, no `epg` table).
void _createV3(String path) {
  final db = sqlite3.open(path);
  db.execute('''
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
  server_url TEXT, username TEXT, source TEXT, user_agent TEXT,
  live_format TEXT NOT NULL, refreshed_at INTEGER
);
INSERT INTO playlists (name, type, source, live_format)
  VALUES ('Old', 'm3uUrl', 's', 'ts');
PRAGMA user_version = 3;
''');
  db.close();
}

void main() {
  group('migration to v4', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('epg_migration');
      path = '${dir.path}/catalog.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('v3 keeps its data, gains epg_url and the epg table', () {
      _createV3(path);
      var db = CatalogDb.open(path);
      final old = db.playlists().single;
      expect(old.name, 'Old');
      expect(old.epgUrl, isNull);
      db.savePlaylist(old.copyWith(epgUrl: 'http://g/epg.xml'));
      db.replaceEpg(old.id!, [_prog('a', 0, 60)], _t0);
      db.close();

      db = CatalogDb.open(path);
      expect(db.playlists().single.epgUrl, 'http://g/epg.xml');
      expect(
        db.programmes(old.id!, ['a'], _t0, _t0.add(const Duration(hours: 2))),
        hasLength(1),
      );
      db.close();

      final raw = sqlite3.open(path);
      expect(raw.select('PRAGMA user_version').first.values.first, 5);
      raw.close();
    });
  });

  group('Playlist.epgUrl', () {
    test('round-trips through savePlaylist', () {
      final db = CatalogDb.inMemory();
      final id = db.savePlaylist(_playlist.copyWith(epgUrl: 'http://g/e.xml'));
      expect(db.playlists().single.epgUrl, 'http://g/e.xml');
      db.savePlaylist(db.playlists().single.copyWith(epgUrl: 'http://g/f.xml'));
      expect(db.playlists().single.epgUrl, 'http://g/f.xml');
      expect(db.playlists().single.id, id);
      db.close();
    });

    test('does not make the catalog stale', () {
      expect(
        _playlist.sourceChanged(_playlist.copyWith(epgUrl: 'http://g/e.xml')),
        isFalse,
      );
    });
  });

  group('epg storage', () {
    late CatalogDb db;
    late int id;

    setUp(() {
      db = CatalogDb.inMemory();
      id = db.savePlaylist(_playlist);
    });
    tearDown(() => db.close());

    test('replaceEpg replaces the guide and records the time', () {
      expect(db.epgRefreshedAt(id), isNull);
      db.replaceEpg(id, [_prog('a', 0, 60), _prog('b', 0, 60)], _t0);
      db.replaceEpg(id, [
        _prog('a', 60, 120),
      ], _t0.add(const Duration(hours: 1)));
      final all = db.programmes(
        id,
        ['a', 'b'],
        _t0,
        _t0.add(const Duration(days: 1)),
      );
      expect(all.map((p) => p.title), ['a@60']);
      expect(db.epgRefreshedAt(id), _t0.add(const Duration(hours: 1)));
      expect(all.single.start.isUtc, isTrue);
      expect(all.single.description, 'd');
    });

    test('nowNext handles contiguous programmes, gaps and missing data', () {
      db.replaceEpg(id, [
        _prog('a', 0, 30),
        _prog('a', 30, 60),
        _prog('a', 60, 90),
        _prog('gap', 0, 30),
        _prog('gap', 60, 90),
      ], _t0);
      final result = db.nowNext(id, [
        'a',
        'gap',
        'none',
      ], _t0.add(const Duration(minutes: 30)));
      expect(result['a']!.$1!.title, 'a@30');
      expect(result['a']!.$2!.title, 'a@60');
      // In a gap: nothing now, the next one is still reported.
      final inGap = db.nowNext(id, [
        'gap',
      ], _t0.add(const Duration(minutes: 40)));
      expect(inGap['gap']!.$1, isNull);
      expect(inGap['gap']!.$2!.title, 'gap@60');
      expect(result['none'], (null, null));
      // Last programme running: no next one.
      final last = db.nowNext(id, ['a'], _t0.add(const Duration(minutes: 75)));
      expect(last['a']!.$1!.title, 'a@60');
      expect(last['a']!.$2, isNull);
      // stop is exclusive.
      final atStop = db.nowNext(id, [
        'a',
      ], _t0.add(const Duration(minutes: 90)));
      expect(atStop['a'], (null, null));
    });

    test('nowNext of 500 channels takes under 50 ms', () {
      final programmes = [
        for (var c = 0; c < 500; c++)
          for (var i = 0; i < 50; i++) _prog('c$c', i * 30, i * 30 + 30),
      ];
      db.replaceEpg(id, programmes, _t0);
      final ids = [for (var c = 0; c < 500; c++) 'c$c'];
      final now = _t0.add(const Duration(minutes: 610));
      final watch = Stopwatch()..start();
      final result = db.nowNext(id, ids, now);
      watch.stop();
      expect(result, hasLength(500));
      expect(result['c7']!.$1!.title, 'c7@600');
      expect(result['c7']!.$2!.title, 'c7@630');
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });

    test('programmes returns the overlapping ones in start order', () {
      db.replaceEpg(id, [
        _prog('a', 90, 120),
        _prog('a', 0, 30),
        _prog('a', 30, 60),
        _prog('a', 60, 90),
        _prog('b', 40, 50),
        _prog('c', 40, 50),
      ], _t0);
      final result = db.programmes(
        id,
        ['a', 'b'],
        _t0.add(const Duration(minutes: 45)),
        _t0.add(const Duration(minutes: 90)),
      );
      expect(result.map((p) => p.title), ['a@30', 'a@60', 'b@40']);
    });

    test('liveEpgIds lists the distinct epg ids of live channels', () {
      const category = Category(id: 'c', name: 'C', kind: MediaKind.live);
      db.replaceCatalog(
        id,
        const [category],
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
            epgId: 'a.es',
          ),
          Channel(key: '3', name: 'C', categoryId: 'c', kind: MediaKind.live),
          Channel(
            key: '4',
            name: 'D',
            categoryId: 'c',
            kind: MediaKind.live,
            epgId: '',
          ),
          Channel(
            key: '5',
            name: 'E',
            categoryId: 'c',
            kind: MediaKind.movie,
            epgId: 'm.es',
          ),
        ],
        _t0,
      );
      expect(db.liveEpgIds(id), {'a.es'});
    });

    test('the M3U guide URL is saved and cleared', () {
      expect(db.m3uTvgUrl(id), isNull);
      db.saveM3uTvgUrl(id, 'http://g/e.xml');
      expect(db.m3uTvgUrl(id), 'http://g/e.xml');
      db.saveM3uTvgUrl(id, null);
      expect(db.m3uTvgUrl(id), isNull);
    });

    test('deletePlaylist removes its guide only', () {
      final other = db.savePlaylist(_playlist.copyWith(name: 'Other'));
      db.replaceEpg(id, [_prog('a', 0, 60)], _t0);
      db.replaceEpg(other, [_prog('a', 0, 60)], _t0);
      db.saveM3uTvgUrl(id, 'http://g/e.xml');
      db.deletePlaylist(id);
      final window = _t0.add(const Duration(days: 1));
      expect(db.programmes(id, ['a'], _t0, window), isEmpty);
      expect(db.epgRefreshedAt(id), isNull);
      expect(db.m3uTvgUrl(id), isNull);
      expect(db.programmes(other, ['a'], _t0, window), hasLength(1));
    });
  });

  test('syncPlaylist stores the #EXTM3U guide URL', () async {
    final db = CatalogDb.inMemory();
    final id = db.savePlaylist(_playlist);
    final client = MockClient(
      (_) async => http.Response(
        '#EXTM3U url-tvg="http://g/e.xml.gz"\n'
        '#EXTINF:-1 tvg-id="a",A\nhttp://h/live/u/p/1.ts\n',
        200,
      ),
    );
    await syncPlaylist(db, db.playlists().single, httpClient: client);
    expect(db.m3uTvgUrl(id), 'http://g/e.xml.gz');
    db.close();
  });
}
