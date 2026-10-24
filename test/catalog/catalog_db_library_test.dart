import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:sqlite3/sqlite3.dart';

const _live = MediaKind.live;
const _category = Category(id: 'c', name: 'C', kind: MediaKind.live);

Channel _ch(String key, [String? name]) => Channel(
  key: key,
  name: name ?? 'Ch $key',
  categoryId: 'c',
  kind: _live,
  streamId: 1,
);

void main() {
  late CatalogDb db;
  late int id;
  final at = DateTime.utc(2026, 10, 19);

  void load(List<Channel> channels, [int? playlistId]) =>
      db.replaceCatalog(playlistId ?? id, const [_category], channels, at);

  setUp(() {
    db = CatalogDb.inMemory();
    id = db.savePlaylist(
      const Playlist(name: 'A', type: PlaylistType.m3uUrl, source: 'x'),
    );
  });
  tearDown(() => db.close());

  group('favorites', () {
    test('toggle and list in insertion order', () {
      load([_ch('1'), _ch('2'), _ch('3')]);
      db.setFavorite(id, _live, '3', true);
      db.setFavorite(id, _live, '1', true);
      db.setFavorite(id, _live, '2', true);
      db.setFavorite(id, _live, '2', false);
      expect(db.favoriteKeys(id, _live), {'1', '3'});
      expect(db.favoriteChannels(id, _live).map((c) => c.key), ['3', '1']);
    });

    test('a favorite missing from the catalog comes back when it returns', () {
      load([_ch('1'), _ch('2')]);
      db.setFavorite(id, _live, '2', true);
      load([_ch('1')]);
      expect(db.favoriteChannels(id, _live), isEmpty);
      load([_ch('1'), _ch('2')]);
      expect(db.favoriteChannels(id, _live).map((c) => c.key), ['2']);
    });
  });

  test('a favorite in a hidden category still shows in favorites', () {
    load([_ch('1')]);
    db.setFavorite(id, _live, '1', true);
    db.saveCategorySort(id, _live, const CategorySort(hidden: {'c'}));
    expect(db.favoriteChannels(id, _live).map((c) => c.key), ['1']);
  });

  test('live favorites and recents ignore items of another kind', () {
    db.replaceCatalog(
      id,
      const [_category],
      const [
        Channel(
          key: 't:x',
          name: 'Peli',
          categoryId: 'c',
          kind: MediaKind.movie,
          url: 'http://h/movie/1.mkv',
        ),
      ],
      at,
    );
    db.setFavorite(id, _live, 't:x', true);
    db.addRecent(id, _live, 't:x');
    expect(db.favoriteChannels(id, _live), isEmpty);
    expect(db.recentChannels(id, _live), isEmpty);
  });

  group('recents', () {
    test('keeps the 50 most recent, newest first, without duplicates', () {
      load([for (var i = 0; i < 51; i++) _ch('$i')]);
      for (var i = 0; i < 51; i++) {
        db.addRecent(id, _live, '$i', at: at.add(Duration(minutes: i)));
      }
      var recents = db.recentChannels(id, _live).map((c) => c.key).toList();
      expect(recents, hasLength(50));
      expect(recents.first, '50');
      expect(recents, isNot(contains('0')));
      db.addRecent(id, _live, '10', at: at.add(const Duration(hours: 5)));
      recents = db.recentChannels(id, _live).map((c) => c.key).toList();
      expect(recents.first, '10');
      expect(recents.where((k) => k == '10'), hasLength(1));
    });
  });

  group('library data lifecycle', () {
    test('survives replaceCatalog and is deleted with the playlist only', () {
      final other = db.savePlaylist(
        const Playlist(name: 'B', type: PlaylistType.m3uUrl, source: 'y'),
      );
      load([_ch('1')]);
      load([_ch('1')], other);
      for (final p in [id, other]) {
        db.setFavorite(p, _live, '1', true);
        db.addRecent(p, _live, '1');
        db.saveChannelSort(
          p,
          _live,
          'c',
          const ChannelSort(mode: SortMode.alphaAsc),
        );
      }
      load([_ch('1')]);
      expect(db.favoriteKeys(id, _live), {'1'});
      expect(db.recentChannels(id, _live), hasLength(1));
      expect(db.hasOwnChannelSort(id, _live, 'c'), isTrue);

      db.deletePlaylist(id);
      expect(db.favoriteKeys(id, _live), isEmpty);
      expect(db.hasOwnChannelSort(id, _live, 'c'), isFalse);
      expect(db.favoriteKeys(other, _live), {'1'});
      expect(db.recentChannels(other, _live), hasLength(1));
      expect(db.hasOwnChannelSort(other, _live, 'c'), isTrue);
    });
  });

  group('search', () {
    test('ignores case and accents', () {
      load([_ch('1', 'TELEDIÁRIO 24h'), _ch('2', 'Otra cosa')]);
      expect(db.searchChannels(id, 'telediario').map((c) => c.key), ['1']);
    });

    test('treats LIKE wildcards as text', () {
      load([
        _ch('1', '500 canales'),
        _ch('2', '50% descuento'),
        _ch('3', 'axb'),
      ]);
      expect(db.searchChannels(id, '50%').map((c) => c.key), ['2']);
      expect(db.searchChannels(id, 'a_b'), isEmpty);
    });

    test('empty query returns nothing', () {
      load([_ch('1')]);
      expect(db.searchChannels(id, '  '), isEmpty);
    });
  });

  group('sort prefs', () {
    test(
      'falls back to the global default unless the category has its own',
      () {
        expect(db.channelSort(id, _live, 'c').mode, SortMode.original);
        expect(db.hasOwnChannelSort(id, _live, 'c'), isFalse);

        db.saveDefaultChannelSort(const ChannelSort(mode: SortMode.alphaAsc));
        expect(db.defaultChannelSort().mode, SortMode.alphaAsc);
        expect(db.channelSort(id, _live, 'c').mode, SortMode.alphaAsc);

        db.saveChannelSort(
          id,
          _live,
          'c',
          const ChannelSort(mode: SortMode.manual, manualOrder: ['2', '1']),
        );
        expect(db.hasOwnChannelSort(id, _live, 'c'), isTrue);
        expect(db.channelSort(id, _live, 'c').manualOrder, ['2', '1']);
        expect(db.channelSort(id, _live, 'other').mode, SortMode.alphaAsc);

        db.deleteChannelSort(id, _live, 'c');
        expect(db.hasOwnChannelSort(id, _live, 'c'), isFalse);
      },
    );

    test('category sort round-trips', () {
      db.saveCategorySort(
        id,
        _live,
        const CategorySort(mode: SortMode.manual, hidden: {'x'}),
      );
      final sort = db.categorySort(id, _live);
      expect(sort.mode, SortMode.manual);
      expect(sort.hidden, {'x'});
    });
  });

  test('upgrades a version 1 database file', () {
    final dir = Directory.systemTemp.createTempSync('catalog_v1');
    final path = '${dir.path}/catalog.db';
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        type TEXT NOT NULL, server_url TEXT, username TEXT, source TEXT,
        user_agent TEXT, live_format TEXT NOT NULL, refreshed_at INTEGER);
      INSERT INTO playlists (name, type, live_format) VALUES ('Old', 'm3uUrl', 'ts');
      PRAGMA user_version = 1;
    ''');
    raw.close();

    final upgraded = CatalogDb.open(path);
    final old = upgraded.playlists().single;
    expect(old.name, 'Old');
    upgraded.setFavorite(old.id!, _live, 'k', true);
    expect(upgraded.favoriteKeys(old.id!, _live), {'k'});
    upgraded.close();
    dir.deleteSync(recursive: true);
  });
}
