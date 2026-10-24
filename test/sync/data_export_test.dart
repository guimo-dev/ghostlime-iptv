import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/sync/data_export.dart';

void main() {
  late CatalogDb db;
  late MemoryPasswordStore passwords;
  late int playlistId;

  setUp(() async {
    db = CatalogDb.inMemory();
    passwords = MemoryPasswordStore();
    playlistId = db.savePlaylist(
      const Playlist(
        name: 'Demo',
        type: PlaylistType.xtream,
        serverUrl: 'http://demo.example:8080',
        username: 'demo-user',
      ),
    );
    await passwords.write(playlistId, 'demo-secret-pass');
    db.setFavorite(playlistId, MediaKind.live, 'ch-1', true);
    db.saveProgress(
      playlistId,
      const PlayTarget(kind: MediaKind.movie, key: 'mv-1', title: 'Pelicula'),
      const Duration(minutes: 5),
      const Duration(minutes: 90),
    );
  });

  tearDown(() => db.close());

  test('export has no playlist password', () {
    final text = exportUserDataJson(db, const AppSettings());
    expect(text, isNot(contains('demo-secret-pass')));
    final json = jsonDecode(text) as Map<String, Object?>;
    final playlist = (json['playlists']! as List).single as Map;
    expect(playlist['name'], 'Demo');
    expect(playlist['server'], 'http://demo.example:8080');
    expect(playlist['username'], 'demo-user');
    expect(playlist.containsKey('password'), isFalse);
  });

  test('export includes favorites, progress and format', () {
    final json = exportUserData(db, const AppSettings());
    expect(json['format'], 'ghostlime-export');
    expect(json['version'], 1);
    final favorite = (json['favorites']! as List).single as Map;
    expect(favorite['playlist'], 'Demo');
    expect(favorite['key'], 'ch-1');
    final progress = (json['progress']! as List).single as Map;
    expect(progress['title'], 'Pelicula');
    expect(progress['positionMs'], const Duration(minutes: 5).inMilliseconds);
    expect(json['settings'], isA<Map>());
  });

  test('export strips credentials from sources and server urls', () {
    db.savePlaylist(
      const Playlist(
        name: 'Query',
        type: PlaylistType.m3uUrl,
        source: 'http://h/get.php?username=u&password=p4ss&token=t0k',
      ),
    );
    db.savePlaylist(
      const Playlist(
        name: 'Path',
        type: PlaylistType.m3uUrl,
        source: 'http://h/live/user9/pass9/list.m3u',
      ),
    );
    db.savePlaylist(
      const Playlist(
        name: 'Userinfo',
        type: PlaylistType.xtream,
        serverUrl: 'http://usr:pw@h:8080',
        username: 'u',
      ),
    );
    db.savePlaylist(
      const Playlist(
        name: 'File',
        type: PlaylistType.m3uFile,
        source: r'C:\Users\demo\lists\mine.m3u',
      ),
    );
    final text = exportUserDataJson(db, const AppSettings());
    for (final secret in ['p4ss', 't0k', 'pass9', 'pw', 'usr', 'user9']) {
      expect(text, isNot(contains(secret)));
    }
    expect(text, contains('"http://h"'));
    expect(text, contains('http://h:8080'));
    expect(text, contains('mine.m3u'));
    expect(text, isNot(contains('demo\\\\lists')));
  });

  test('export has no PIN data nor locked categories', () {
    final text = exportUserDataJson(
      db,
      const AppSettings(
        parentalLock: true,
        lockedCategories: {'live:Adultos-demo'},
      ),
    );
    expect(text, isNot(contains('Adultos-demo')));
    expect(text, isNot(contains('parentalLock')));
    expect(text, isNot(contains('lockedCategories')));
  });
}
