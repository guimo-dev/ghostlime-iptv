import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:sqlite3/sqlite3.dart';

const _playlist = Playlist(
  name: 'M3U',
  type: PlaylistType.m3uUrl,
  source: 'http://h/list.m3u',
);

/// Creates a version 2 database file with one favorite and one pref.
void _createV2(String path) {
  final db = sqlite3.open(path);
  db.execute('''
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
  server_url TEXT, username TEXT, source TEXT, user_agent TEXT,
  live_format TEXT NOT NULL, refreshed_at INTEGER
);
CREATE TABLE categories (
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL,
  position INTEGER NOT NULL, PRIMARY KEY (playlist_id, kind, id)
);
CREATE TABLE channels (
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  key TEXT NOT NULL, kind TEXT NOT NULL, category_id TEXT NOT NULL,
  name TEXT NOT NULL, icon_url TEXT, epg_id TEXT, stream_id INTEGER, url TEXT,
  position INTEGER NOT NULL, PRIMARY KEY (playlist_id, key)
);
CREATE TABLE favorites (
  playlist_id INTEGER NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL,
  added_at INTEGER NOT NULL, PRIMARY KEY (playlist_id, kind, key)
);
CREATE TABLE recents (
  playlist_id INTEGER NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL,
  watched_at INTEGER NOT NULL, PRIMARY KEY (playlist_id, kind, key)
);
CREATE TABLE prefs (
  playlist_id INTEGER NOT NULL, scope TEXT NOT NULL, value TEXT NOT NULL,
  PRIMARY KEY (playlist_id, scope)
);
INSERT INTO playlists (name, type, source, live_format)
  VALUES ('Old', 'm3uUrl', 's', 'ts');
INSERT INTO favorites VALUES (1, 'live', 'x:1', 5);
INSERT INTO prefs VALUES (0, 'channels/default',
  '{"mode":"alphaAsc","favoritesFirst":true,"manualOrder":[]}');
PRAGMA user_version = 2;
''');
  db.close();
}

/// Creates a version 4 database file with two playlists and no sync ids.
void _createV4(String path) {
  final db = sqlite3.open(path);
  db.execute('''
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
  server_url TEXT, username TEXT, source TEXT, user_agent TEXT,
  live_format TEXT NOT NULL, refreshed_at INTEGER, epg_url TEXT
);
INSERT INTO playlists (name, type, source, live_format)
  VALUES ('Uno', 'm3uUrl', 's1', 'ts'), ('Dos', 'm3uUrl', 's2', 'ts');
PRAGMA user_version = 4;
''');
  db.close();
}

int _userVersion(String path) {
  final db = sqlite3.open(path);
  final version = db.select('PRAGMA user_version').first.values.first as int;
  db.close();
  return version;
}

void main() {
  test('extension and rating round-trip through the catalog', () {
    final db = CatalogDb.inMemory();
    final id = db.savePlaylist(_playlist);
    db.replaceCatalog(
      id,
      const [Category(id: 'c', name: 'C', kind: MediaKind.movie)],
      const [
        Channel(
          key: 'xm:1',
          name: 'Peli',
          categoryId: 'c',
          kind: MediaKind.movie,
          streamId: 1,
          extension: 'mkv',
          rating: 6.5,
        ),
        Channel(
          key: 'xm:2',
          name: 'Otra',
          categoryId: 'c',
          kind: MediaKind.movie,
        ),
      ],
      DateTime.utc(2026, 10, 19),
    );
    final channels = db.channels(id, 'c');
    expect(channels.first.extension, 'mkv');
    expect(channels.first.rating, 6.5);
    expect(channels.last.extension, isNull);
    expect(channels.last.rating, isNull);
    db.close();
  });

  group('migration', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('catalog_migration');
      path = '${dir.path}/catalog.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('v2 database keeps its data and reaches v5', () {
      _createV2(path);
      final db = CatalogDb.open(path);
      expect(db.favoriteKeys(1, MediaKind.live), {'x:1'});
      expect(db.defaultChannelSort().mode, SortMode.alphaAsc);
      db.replaceCatalog(
        1,
        const [Category(id: 'c', name: 'C', kind: MediaKind.movie)],
        const [
          Channel(
            key: 'xm:1',
            name: 'Peli',
            categoryId: 'c',
            kind: MediaKind.movie,
            extension: 'mkv',
            rating: 7,
          ),
        ],
        DateTime.utc(2026, 10, 19),
      );
      expect(db.channels(1, 'c').single.extension, 'mkv');
      db.close();
      expect(_userVersion(path), 5);
    });

    test(
      'v4 database gets a distinct sync id per playlist, kept on reopen',
      () {
        _createV4(path);
        var db = CatalogDb.open(path);
        final first = db.playlists().map((p) => p.syncId).toList();
        expect(first, everyElement(isNotNull));
        expect(first.toSet(), hasLength(2));
        expect(db.dirtyItems(), isEmpty);
        db.close();
        expect(_userVersion(path), 5);
        db = CatalogDb.open(path);
        expect(db.playlists().map((p) => p.syncId).toList(), first);
        db.close();
      },
    );

    test('opening twice does not fail', () {
      _createV2(path);
      CatalogDb.open(path).close();
      final db = CatalogDb.open(path);
      expect(db.favoriteKeys(1, MediaKind.live), {'x:1'});
      db.close();
      expect(_userVersion(path), 5);
    });
  });
}
