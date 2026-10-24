import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_crypto.dart';
import 'package:iptv_player/sync/sync_engine.dart';
import 'package:iptv_player/sync/sync_ids.dart';
import 'package:iptv_player/sync/sync_items.dart';

import 'fake_passwords.dart';

/// The same Xtream source, written slightly differently on each device.
Playlist _xtream({String? syncId, String server = 'http://Server:8080/'}) =>
    Playlist(
      syncId: syncId,
      name: 'Mi proveedor',
      type: PlaylistType.xtream,
      serverUrl: server,
      username: 'ana',
    );

/// A backend whose pulls can be held until [gate] completes, so two devices
/// can both download before either uploads.
class _GatedBackend extends InMemorySyncBackend {
  Completer<void>? gate;

  @override
  Future<List<RemoteItem>> pull(DateTime? since) async {
    await gate?.future;
    return super.pull(since);
  }
}

/// One simulated device: its own database and secure storage.
class _Device {
  _Device(SyncBackend backend, List<int> key) {
    engine = SyncEngine(db, backend, key, passwords);
  }

  final CatalogDb db = CatalogDb.inMemory();
  final FakePasswords passwords = FakePasswords();
  late final SyncEngine engine;

  Future<SyncReport> sync() => engine.syncNow();

  /// Saves [playlist] with a password and returns its row id.
  int add(Playlist playlist) {
    final id = db.savePlaylist(playlist);
    passwords.values[id] = 'secret-pass';
    return id;
  }

  Set<String> favorites(int playlistId) =>
      db.favoriteKeys(playlistId, MediaKind.live);
}

void main() {
  group('playlistIdentity', () {
    test('ignores case and trailing slash of the Xtream server', () {
      expect(
        playlistIdentity(_xtream(server: 'HTTP://Server:8080//')),
        playlistIdentity(_xtream(server: 'http://server:8080')),
      );
    });

    test('differs by username, type and source', () {
      final base = _xtream();
      expect(
        playlistIdentity(
          Playlist(
            name: 'x',
            type: PlaylistType.xtream,
            serverUrl: base.serverUrl,
            username: 'bob',
          ),
        ),
        isNot(playlistIdentity(base)),
      );
      const url = Playlist(
        name: 'x',
        type: PlaylistType.m3uUrl,
        source: 'http://a/list.m3u',
      );
      const file = Playlist(
        name: 'x',
        type: PlaylistType.m3uFile,
        source: 'http://a/list.m3u',
      );
      expect(playlistIdentity(url), isNot(playlistIdentity(file)));
      expect(playlistIdentity(url), isNotNull);
    });

    test('is null when the defining fields are missing', () {
      expect(
        playlistIdentity(const Playlist(name: 'x', type: PlaylistType.xtream)),
        isNull,
      );
      expect(
        playlistIdentity(const Playlist(name: 'x', type: PlaylistType.m3uUrl)),
        isNull,
      );
    });
  });

  group('the same source added on two devices', () {
    final key = SyncCrypto.randomBytes(32);
    late _GatedBackend backend;
    late _Device a;
    late _Device b;

    setUp(() {
      backend = _GatedBackend();
      a = _Device(backend, key);
      b = _Device(backend, key);
    });
    tearDown(() {
      a.db.close();
      b.db.close();
    });

    Iterable<String> tombstones() => backend.items
        .where((i) => i.kind == playlistKind && i.deleted)
        .map((i) => i.itemId);

    test('the local row takes the smaller remote sync id', () async {
      a.add(_xtream(syncId: 'aaa'));
      final idB = b.add(_xtream(syncId: 'zzz'));
      b.db.replaceCatalog(
        idB,
        const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
        const [
          Channel(key: 'k', name: 'K', categoryId: 'c', kind: MediaKind.live),
        ],
        DateTime.now(),
      );
      b.db.setFavorite(idB, MediaKind.live, 'k', true);
      await a.sync();

      final report = await b.sync();

      final copy = b.db.playlists().single;
      expect(copy.syncId, 'aaa');
      expect(copy.id, idB);
      expect(copy.refreshedAt, isNotNull);
      expect(b.db.channelCount(idB, MediaKind.live), 1);
      expect(report.createdPlaylists, isEmpty);
      expect(report.changedPlaylists, isEmpty);
      expect(b.passwords.values[idB], 'secret-pass');
      expect(b.favorites(idB), {'k'});
      expect(tombstones(), ['zzz']);
      expect(b.db.dirtyItems(), isEmpty);
    });

    test('the local copy wins when its sync id is smaller', () async {
      b.add(_xtream(syncId: 'zzz'));
      await b.sync();
      final idA = a.add(_xtream(syncId: 'aaa'));

      final report = await a.sync();

      expect(a.db.playlists().single.id, idA);
      expect(a.db.playlists().single.syncId, 'aaa');
      expect(report.createdPlaylists, isEmpty);
      expect(tombstones(), ['zzz']);
      await b.sync();
      expect(b.db.playlists().single.syncId, 'aaa');
    });

    test('two devices that sync at the same time end with one playlist '
        'and all favorites', () async {
      final idA = a.add(_xtream(syncId: 'aaa'));
      final idB = b.add(_xtream(syncId: 'zzz'));
      a.db.setFavorite(idA, MediaKind.live, 'from-a', true);
      b.db.setFavorite(idB, MediaKind.live, 'from-b', true);
      b.db.saveProgress(
        idB,
        const PlayTarget(kind: MediaKind.movie, key: 'xm:1', title: 'Peli'),
        const Duration(seconds: 5),
        const Duration(minutes: 90),
      );

      backend.gate = Completer<void>();
      final both = Future.wait([a.sync(), b.sync()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      backend.gate!.complete();
      await both;
      backend.gate = null;
      for (var round = 0; round < 2; round++) {
        await a.sync();
        await b.sync();
      }

      for (final device in [a, b]) {
        final playlist = device.db.playlists().single;
        expect(playlist.syncId, 'aaa');
        expect(device.favorites(playlist.id!), {'from-a', 'from-b'});
        expect(
          device.db.progress(playlist.id!, MediaKind.movie, 'xm:1'),
          isNotNull,
        );
        expect(device.db.dirtyItems(), isEmpty);
      }
      final live = backend.items.where(
        (i) => i.kind == playlistKind && !i.deleted,
      );
      expect(live.map((i) => i.itemId), ['aaa']);
    });
  });

  test('duplicates already on a device are merged into the smallest', () async {
    final key = SyncCrypto.randomBytes(32);
    final backend = InMemorySyncBackend();
    final a = _Device(backend, key);
    final c = _Device(backend, key);
    addTearDown(a.db.close);
    addTearDown(c.db.close);
    final keep = a.add(_xtream(syncId: 'aaa'));
    final drop = a.add(_xtream(syncId: 'mmm', server: 'http://server:8080'));
    final other = a.add(
      const Playlist(
        name: 'Otra',
        type: PlaylistType.m3uUrl,
        source: 'http://x/y.m3u',
        syncId: 'zzz',
      ),
    );
    a.db.setFavorite(keep, MediaKind.live, 'both', true);
    a.db.setFavorite(drop, MediaKind.live, 'both', true);
    a.db.setFavorite(drop, MediaKind.live, 'only-drop', true);
    a.db.setFavorite(other, MediaKind.live, 'other', true);
    a.db.savePref(drop, 'channels/live/c', {'sort': 'az'});

    await a.sync();

    expect(a.db.playlists().map((p) => p.syncId), ['aaa', 'zzz']);
    expect(a.favorites(keep), {'both', 'only-drop'});
    expect(a.favorites(other), {'other'});
    final prefs = a.db.allPrefs().where((p) => p.playlistId == keep).toList();
    expect(prefs.single.scope, 'channels/live/c');
    expect(prefs.single.value, {'sort': 'az'});
    expect(a.passwords.values.containsKey(drop), isFalse);
    expect(a.db.dirtyItems(), isEmpty);
    final gone = backend.items
        .where((i) => i.deleted && i.kind == playlistKind)
        .map((i) => i.itemId);
    expect(gone, ['mmm']);

    await c.sync();
    expect(c.db.playlists().map((p) => p.syncId), ['aaa', 'zzz']);
    final copy = c.db.playlistIdForSyncId('aaa')!;
    expect(c.favorites(copy), {'both', 'only-drop'});
  });
}
