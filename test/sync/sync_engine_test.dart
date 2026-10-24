import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_crypto.dart';
import 'package:iptv_player/sync/sync_engine.dart';
import 'package:iptv_player/sync/sync_ids.dart';

import 'fake_passwords.dart';

const _xtream = Playlist(
  name: 'Mi proveedor',
  type: PlaylistType.xtream,
  serverUrl: 'http://secret-server:8080',
  username: 'secret-user',
);
const _target = PlayTarget(kind: MediaKind.movie, key: 'xm:5', title: 'Peli');

/// A backend that reports what it was asked and can run code during a push.
class _SpyBackend extends InMemorySyncBackend {
  final List<DateTime?> pullSinces = [];
  final List<int> pulledCounts = [];
  void Function()? duringPush;

  /// When set, a pull waits for it before answering.
  Future<void>? pullGate;

  @override
  Future<List<RemoteItem>> pull(DateTime? since) async {
    pullSinces.add(since);
    await pullGate;
    final items = await super.pull(since);
    pulledCounts.add(items.length);
    return items;
  }

  @override
  Future<void> push(List<RemoteItem> items) async {
    await super.push(items);
    duringPush?.call();
  }
}

/// One simulated device: its own database and secure storage.
class _Device {
  _Device(this.backend, List<int> key) {
    engine = SyncEngine(db, backend, key, passwords);
  }

  final SyncBackend backend;
  final CatalogDb db = CatalogDb.inMemory();
  final FakePasswords passwords = FakePasswords();
  late final SyncEngine engine;

  Future<SyncReport> sync() => engine.syncNow();

  Set<String> favorites(String syncId, MediaKind kind) =>
      db.favoriteKeys(db.playlistIdForSyncId(syncId)!, kind);
}

void main() {
  final key = SyncCrypto.randomBytes(32);
  final ids = ItemIds(key);
  // Relative to now: the real clock wins over fixed dates (see APRENDIZAJES).
  final now = DateTime.now().toUtc();
  final t1 = now.add(const Duration(hours: 1));
  final t2 = now.add(const Duration(hours: 2));
  final t3 = now.add(const Duration(hours: 3));
  late _SpyBackend backend;
  late _Device a;
  late _Device b;

  /// A playlist on [a] that [b] has already received.
  Future<String> sharedPlaylist() async {
    final id = a.db.savePlaylist(_xtream);
    a.passwords.values[id] = 'secret-pass';
    await a.sync();
    await b.sync();
    return a.db.syncIdOfPlaylist(id)!;
  }

  setUp(() {
    backend = _SpyBackend();
    a = _Device(backend, key);
    b = _Device(backend, key);
  });
  tearDown(() {
    a.db.close();
    b.db.close();
  });

  test(
    'a playlist with its password and a favorite reach the other device',
    () async {
      final id = a.db.savePlaylist(_xtream);
      a.passwords.values[id] = 'secret-pass';
      final syncId = a.db.syncIdOfPlaylist(id)!;
      a.db.setFavorite(id, MediaKind.live, 'ch:1', true);

      final first = await a.sync();
      expect(first.pushed, 2);
      final report = await b.sync();

      expect(report.pulled, 2);
      expect(report.applied, 2);
      expect(report.createdPlaylists.single.syncId, syncId);
      expect(report.createdPlaylists.single.id, isNotNull);
      expect(report.changedPlaylists, isEmpty);
      final copy = b.db.playlists().single;
      expect(copy.name, 'Mi proveedor');
      expect(copy.serverUrl, 'http://secret-server:8080');
      expect(b.passwords.values[copy.id], 'secret-pass');
      expect(b.favorites(syncId, MediaKind.live), {'ch:1'});
    },
  );

  test('nothing readable leaves the device', () async {
    final id = a.db.savePlaylist(_xtream);
    a.passwords.values[id] = 'secret-pass';
    a.db.setFavorite(id, MediaKind.live, 'Canal Secreto HD', true);
    a.db.saveProgress(
      id,
      _target,
      const Duration(seconds: 3),
      const Duration(seconds: 9),
    );
    a.db.saveChannelSort(
      id,
      MediaKind.live,
      'Categoría X',
      const ChannelSort(),
    );
    a.db.saveSettings(const AppSettings(audioLanguage: 'klingon').toJson());
    await a.sync();

    expect(backend.items, hasLength(5));
    final everything = jsonEncode([
      for (final i in backend.items) [i.kind, i.itemId, i.payload],
    ]);
    for (final secret in [
      'secret',
      'Secreto',
      'Peli',
      'xm:5',
      'Categor',
      'klingon',
      'Mi proveedor',
    ]) {
      expect(everything, isNot(contains(secret)));
    }
    for (final item in backend.items) {
      expect(base64Decode(item.payload!).length, greaterThan(28));
    }
  });

  test('applied remote elements are not uploaded again', () async {
    await sharedPlaylist();
    expect(b.db.dirtyItems(), isEmpty);
    final report = await b.sync();
    expect(report.pushed, 0);
    expect(report.applied, 0);
  });

  test('later changes travel both ways', () async {
    final syncId = await sharedPlaylist();
    a.db.setFavorite(
      a.db.playlistIdForSyncId(syncId)!,
      MediaKind.live,
      'x',
      true,
    );
    b.db.saveDefaultChannelSort(const ChannelSort(mode: SortMode.alphaAsc));
    await a.sync();
    await b.sync();
    await a.sync();
    expect(b.favorites(syncId, MediaKind.live), {'x'});
    expect(a.db.defaultChannelSort().mode, SortMode.alphaAsc);
  });

  group('conflicts', () {
    test(
      'the newest change to the same favorite wins, in either order',
      () async {
        final syncId = await sharedPlaylist();
        final idA = a.db.playlistIdForSyncId(syncId)!;
        final idB = b.db.playlistIdForSyncId(syncId)!;
        final itemId = ids.favorite(syncId, MediaKind.live, 'k');
        a.db.setFavorite(idA, MediaKind.live, 'k', true);
        await a.sync();
        await b.sync();

        // A removes it at t1; B removes and re-adds it at t2 (newer).
        a.db.setFavorite(idA, MediaKind.live, 'k', false);
        a.db.markDirty(favoriteKind, itemId, deleted: true, at: t1);
        b.db.setFavorite(idB, MediaKind.live, 'k', false);
        b.db.setFavorite(idB, MediaKind.live, 'k', true);
        b.db.markDirty(favoriteKind, itemId, at: t2);

        await a.sync();
        await b.sync();
        await a.sync();
        expect(a.favorites(syncId, MediaKind.live), {'k'});
        expect(b.favorites(syncId, MediaKind.live), {'k'});
        expect(a.db.syncState(favoriteKind, itemId)!.updatedAt, t2);
      },
    );

    test(
      'an older change does not overwrite a newer one already uploaded',
      () async {
        final syncId = await sharedPlaylist();
        final idA = a.db.playlistIdForSyncId(syncId)!;
        final idB = b.db.playlistIdForSyncId(syncId)!;
        final itemId = ids.favorite(syncId, MediaKind.live, 'k');
        a.db.setFavorite(idA, MediaKind.live, 'k', true);
        a.db.markDirty(favoriteKind, itemId, at: t1);
        b.db.setFavorite(idB, MediaKind.live, 'k', true);
        b.db.setFavorite(idB, MediaKind.live, 'k', false);
        b.db.markDirty(favoriteKind, itemId, deleted: true, at: t2);

        await b.sync();
        await a.sync();
        expect(a.favorites(syncId, MediaKind.live), isEmpty);
        expect(
          backend.items.firstWhere((i) => i.itemId == itemId).deleted,
          isTrue,
        );
      },
    );

    test('a newer deletion beats an older edit', () async {
      final syncId = await sharedPlaylist();
      final idA = a.db.playlistIdForSyncId(syncId)!;
      final idB = b.db.playlistIdForSyncId(syncId)!;
      a.db.saveProgress(
        idA,
        _target,
        const Duration(seconds: 1),
        const Duration(seconds: 9),
        at: t1,
      );
      await a.sync();
      await b.sync();
      expect(b.db.progress(idB, MediaKind.movie, 'xm:5'), isNotNull);

      a.db.saveProgress(
        idA,
        _target,
        const Duration(seconds: 5),
        const Duration(seconds: 9),
        at: t2,
      );
      b.db.clearProgress(idB, MediaKind.movie, 'xm:5');
      b.db.markDirty(
        progressKind,
        ids.progress(syncId, MediaKind.movie, 'xm:5'),
        deleted: true,
        at: t3,
      );

      await a.sync();
      await b.sync();
      await a.sync();
      expect(a.db.progress(idA, MediaKind.movie, 'xm:5'), isNull);
      expect(b.db.progress(idB, MediaKind.movie, 'xm:5'), isNull);
    });

    test('a newer edit beats an older deletion', () async {
      final syncId = await sharedPlaylist();
      final idA = a.db.playlistIdForSyncId(syncId)!;
      final idB = b.db.playlistIdForSyncId(syncId)!;
      final itemId = ids.progress(syncId, MediaKind.movie, 'xm:5');
      a.db.saveProgress(
        idA,
        _target,
        const Duration(seconds: 1),
        const Duration(seconds: 9),
        at: t1,
      );
      await a.sync();
      await b.sync();

      b.db.clearProgress(idB, MediaKind.movie, 'xm:5');
      b.db.markDirty(progressKind, itemId, deleted: true, at: t2);
      a.db.saveProgress(
        idA,
        _target,
        const Duration(seconds: 7),
        const Duration(seconds: 9),
        at: t3,
      );

      await b.sync();
      await a.sync();
      await b.sync();
      expect(
        b.db.progress(idB, MediaKind.movie, 'xm:5')!.position,
        const Duration(seconds: 7),
      );
      expect(
        a.db.progress(idA, MediaKind.movie, 'xm:5')!.position,
        const Duration(seconds: 7),
      );
    });
  });

  test(
    'deleting a playlist removes it, its catalog and its password elsewhere',
    () async {
      final syncId = await sharedPlaylist();
      final idB = b.db.playlistIdForSyncId(syncId)!;
      b.db.replaceCatalog(
        idB,
        const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
        const [
          Channel(key: 'k', name: 'K', categoryId: 'c', kind: MediaKind.live),
        ],
        t1,
      );
      a.db.deletePlaylist(a.db.playlistIdForSyncId(syncId)!);
      await a.sync();
      final report = await b.sync();
      expect(report.createdPlaylists, isEmpty);
      expect(b.db.playlists(), isEmpty);
      expect(b.db.channelCount(idB, MediaKind.live), 0);
      expect(b.passwords.values, isEmpty);
    },
  );

  test('a changed source comes back in changedPlaylists', () async {
    final syncId = await sharedPlaylist();
    final idA = a.db.playlistIdForSyncId(syncId)!;
    a.db.savePlaylist(
      a.db.playlists().single.copyWith(serverUrl: 'http://otro:1'),
    );
    expect(idA, isNotNull);
    await a.sync();
    final report = await b.sync();
    expect(report.createdPlaylists, isEmpty);
    expect(report.changedPlaylists.single.serverUrl, 'http://otro:1');
  });

  test('settings sync but parental control stays local', () async {
    a.db.saveSettings(
      const AppSettings(networkCacheSecs: 60, parentalLock: true).toJson(),
    );
    b.db.saveSettings(const AppSettings(lastPlaylistId: 7).toJson());
    await a.sync();
    await b.sync();
    final settings = AppSettings.fromJson(b.db.loadSettings());
    expect(settings.networkCacheSecs, 60);
    expect(settings.parentalLock, isFalse);
    expect(settings.lastPlaylistId, 7);
  });

  group('wrong key or tampered data', () {
    test(
      'a wrong key applies and uploads nothing and keeps the cursor',
      () async {
        await sharedPlaylist();
        a.db.setFavorite(
          a.db.playlists().single.id!,
          MediaKind.live,
          'k',
          true,
        );
        await a.sync();
        final stranger = _Device(backend, SyncCrypto.randomBytes(32));
        stranger.db.setFavorite(
          stranger.db.savePlaylist(_xtream),
          MediaKind.live,
          'mine',
          true,
        );
        final before = backend.items.length;

        await expectLater(stranger.sync(), throwsA(isA<SyncCryptoException>()));
        expect(stranger.db.playlists().length, 1);
        expect(stranger.db.syncCursor(), isNull);
        expect(backend.items, hasLength(before));
        expect(stranger.db.dirtyItems(), isNotEmpty);
        stranger.db.close();
      },
    );

    /// Flips a bit of the sealed payload of [victim] on the server, and
    /// restamps it with [syncedAt] when given.
    void tamper(RemoteItem victim, {DateTime? syncedAt}) {
      final bytes = base64Decode(victim.payload!);
      bytes[bytes.length - 1] ^= 1;
      backend.overwrite(
        RemoteItem(
          kind: victim.kind,
          itemId: victim.itemId,
          payload: base64Encode(bytes),
          updatedAt: victim.updatedAt,
          deleted: false,
          syncedAt: syncedAt ?? victim.syncedAt,
        ),
      );
    }

    test(
      'a tampered element is skipped and counted; the rest is applied',
      () async {
        final syncId = await sharedPlaylist();
        final idA = a.db.playlistIdForSyncId(syncId)!;
        a.db.setFavorite(idA, MediaKind.live, 'one', true);
        a.db.setFavorite(idA, MediaKind.live, 'two', true);
        await a.sync();
        tamper(backend.items.firstWhere((i) => i.kind == favoriteKind));

        final report = await b.sync();

        expect(report.skipped, 1);
        expect(b.favorites(syncId, MediaKind.live), hasLength(1));
      },
    );

    test('the cursor moves past unreadable elements', () async {
      final syncId = await sharedPlaylist();
      a.db.setFavorite(
        a.db.playlistIdForSyncId(syncId)!,
        MediaKind.live,
        'one',
        true,
      );
      await a.sync();
      final victim = backend.items.firstWhere((i) => i.kind == favoriteKind);
      tamper(victim, syncedAt: DateTime.utc(2030));

      await b.sync();

      expect(b.db.syncCursor(), DateTime.utc(2030));
    });

    /// Replaces the server copy of [row] with [changes] applied.
    void forge(
      RemoteItem row, {
      String? payload,
      bool? deleted,
      DateTime? updatedAt,
      bool noPayload = false,
    }) => backend.overwrite(
      RemoteItem(
        kind: row.kind,
        itemId: row.itemId,
        payload: noPayload ? null : payload ?? row.payload,
        updatedAt: updatedAt ?? row.updatedAt,
        deleted: deleted ?? row.deleted,
        syncedAt: DateTime.utc(2030),
      ),
    );

    test('a payload moved to another item_id is rejected', () async {
      final syncId = await sharedPlaylist();
      final idA = a.db.playlistIdForSyncId(syncId)!;
      a.db.setFavorite(idA, MediaKind.live, 'one', true);
      a.db.setFavorite(idA, MediaKind.live, 'two', true);
      await a.sync();
      final favorites = backend.items.where((i) => i.kind == favoriteKind);
      final first = favorites.first;
      final second = favorites.last;
      forge(first, payload: second.payload);
      forge(second, payload: first.payload);

      final report = await b.sync();

      expect(report.skipped, 2);
      expect(b.favorites(syncId, MediaKind.live), isEmpty);
    });

    test('a forged tombstone is rejected', () async {
      final syncId = await sharedPlaylist();
      a.db.setFavorite(
        a.db.playlistIdForSyncId(syncId)!,
        MediaKind.live,
        'k',
        true,
      );
      await a.sync();
      await b.sync();
      final row = backend.items.firstWhere((i) => i.kind == favoriteKind);
      final newer = t3;

      // Without any payload, with the live row's payload, and with a payload
      // of another element.
      final cursor = b.db.syncCursor();
      for (final payload in [null, row.payload, backend.items.first.payload]) {
        // Back to the earlier cursor so the pull also returns a readable row.
        b.db.saveSyncCursor(cursor);
        forge(
          row,
          deleted: true,
          updatedAt: newer,
          payload: payload,
          noPayload: payload == null,
        );
        final report = await b.sync();
        expect(report.skipped, greaterThanOrEqualTo(1));
        expect(b.favorites(syncId, MediaKind.live), {'k'});
      }
    });

    test('changing updatedAt or deleted of a sealed row is rejected', () async {
      final syncId = await sharedPlaylist();
      a.db.setFavorite(
        a.db.playlistIdForSyncId(syncId)!,
        MediaKind.live,
        'k',
        true,
      );
      await a.sync();
      final row = backend.items.firstWhere((i) => i.kind == favoriteKind);
      forge(row, updatedAt: row.updatedAt.add(const Duration(hours: 1)));

      final report = await b.sync();

      expect(report.skipped, 1);
      expect(b.favorites(syncId, MediaKind.live), isEmpty);
    });

    test('a tombstone carries a sealed empty payload', () async {
      final syncId = await sharedPlaylist();
      a.db.deletePlaylist(a.db.playlistIdForSyncId(syncId)!);
      await a.sync();

      final tombstone = backend.items.singleWhere((i) => i.deleted);

      expect(tombstone.payload, isNotNull);
      final report = await b.sync();
      expect(report.skipped, 0);
      expect(b.db.playlists(), isEmpty);
    });

    test('a live element without payload is skipped', () async {
      final syncId = await sharedPlaylist();
      backend.overwrite(
        RemoteItem(
          kind: favoriteKind,
          itemId: ids.favorite(syncId, MediaKind.live, 'x'),
          payload: null,
          updatedAt: t1,
          deleted: false,
          syncedAt: DateTime.utc(2030),
        ),
      );

      final report = await b.sync();

      expect(report.skipped, 1);
    });

    test('a validly sealed but malformed element is skipped', () async {
      final syncId = await sharedPlaylist();
      backend.overwrite(
        RemoteItem(
          kind: playlistKind,
          itemId: newSyncId(),
          payload: await SyncCrypto.seal(key, utf8.encode('{"name": 5}')),
          updatedAt: t1,
          deleted: false,
          syncedAt: DateTime.utc(2030),
        ),
      );
      backend.overwrite(
        RemoteItem(
          kind: favoriteKind,
          itemId: newSyncId(),
          payload: await SyncCrypto.seal(key, utf8.encode('[1, 2]')),
          updatedAt: t1,
          deleted: false,
          syncedAt: DateTime.utc(2030),
        ),
      );

      final report = await b.sync();

      expect(report.skipped, 2);
      expect(b.db.playlists(), hasLength(1));
      expect(b.favorites(syncId, MediaKind.live), isEmpty);
    });
  });

  group('cursor', () {
    test('only newer elements are downloaded after the first sync', () async {
      final syncId = await sharedPlaylist();
      backend.pullSinces.clear();
      backend.pulledCounts.clear();

      a.db.setFavorite(
        a.db.playlistIdForSyncId(syncId)!,
        MediaKind.live,
        'new',
        true,
      );
      await a.sync();
      backend.pullSinces.clear();
      backend.pulledCounts.clear();
      final report = await b.sync();

      expect(backend.pullSinces.first, isNotNull);
      expect(backend.pulledCounts.first, greaterThanOrEqualTo(1));
      expect(report.applied, 1);
      expect(b.db.syncCursor(), isNotNull);
    });

    test(
      'the first sync starts from nothing and uploads existing local data',
      () async {
        final id = a.db.savePlaylist(_xtream);
        a.db.setFavorite(id, MediaKind.live, 'k', true);
        await a.sync();
        expect(backend.pullSinces.first, isNull);

        // A new account (empty server) on a device that already synced before.
        final fresh = _SpyBackend();
        final other = SyncEngine(a.db, fresh, key, a.passwords);
        a.db.saveSyncCursor(null);
        final report = await other.syncNow();
        expect(report.pushed, 2);
        expect(fresh.items, hasLength(2));
      },
    );

    test(
      'pulls with an overlap so late-committed rows are not missed',
      () async {
        final syncId = await sharedPlaylist();
        final cursor = b.db.syncCursor()!;
        a.db.setFavorite(
          a.db.playlistIdForSyncId(syncId)!,
          MediaKind.live,
          'late',
          true,
        );
        await a.sync();
        // The server stamped it slightly before B's cursor (a transaction that
        // committed after B's last pull).
        final row = backend.items.firstWhere((i) => i.kind == favoriteKind);
        backend.overwrite(
          RemoteItem(
            kind: row.kind,
            itemId: row.itemId,
            payload: row.payload,
            updatedAt: row.updatedAt,
            deleted: row.deleted,
            syncedAt: cursor.subtract(const Duration(seconds: 30)),
          ),
        );
        backend.pullSinces.clear();

        await b.sync();

        expect(backend.pullSinces.first, cursor.subtract(syncOverlap));
        expect(b.favorites(syncId, MediaKind.live), {'late'});
      },
    );

    test('applying remote elements does not announce local changes', () async {
      final syncId = await sharedPlaylist();
      a.db.setFavorite(
        a.db.playlistIdForSyncId(syncId)!,
        MediaKind.live,
        'new',
        true,
      );
      await a.sync();
      var announced = 0;
      b.db.onLocalChange = (_) => announced++;

      final report = await b.sync();

      expect(report.applied, greaterThan(0));
      expect(announced, 0);
      expect(b.favorites(syncId, MediaKind.live), {'new'});
    });

    test('reports whether settings were applied', () async {
      a.db.saveSettings(const AppSettings(networkCacheSecs: 60).toJson());
      await a.sync();

      expect((await b.sync()).settingsApplied, isTrue);
      expect((await b.sync()).settingsApplied, isFalse);
    });

    test(
      'a closed engine neither applies, uploads nor saves a cursor',
      () async {
        final syncId = await sharedPlaylist();
        a.db.setFavorite(
          a.db.playlistIdForSyncId(syncId)!,
          MediaKind.live,
          'late',
          true,
        );
        await a.sync();
        b.db.setFavorite(
          b.db.playlistIdForSyncId(syncId)!,
          MediaKind.live,
          'mine',
          true,
        );
        final cursorBefore = b.db.syncCursor();
        final itemsBefore = backend.items.length;
        final gate = Completer<void>();
        backend.pullGate = gate.future;

        final running = b.engine.syncNow();
        b.engine.close();
        gate.complete();
        final report = await running;

        expect(report.applied, 0);
        expect(report.pushed, 0);
        expect(b.db.syncCursor(), cursorBefore);
        expect(b.favorites(syncId, MediaKind.live), {'mine'});
        expect(backend.items, hasLength(itemsBefore));
      },
    );

    test('a change made while uploading is not marked as uploaded', () async {
      final syncId = await sharedPlaylist();
      final idA = a.db.playlistIdForSyncId(syncId)!;
      final itemId = ids.favorite(syncId, MediaKind.live, 'k');
      a.db.setFavorite(idA, MediaKind.live, 'k', true);
      backend.duringPush = () {
        a.db.setFavorite(idA, MediaKind.live, 'k', false);
        a.db.markDirty(
          favoriteKind,
          itemId,
          deleted: true,
          at: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
        backend.duringPush = null;
      };
      await a.sync();
      expect(a.db.syncState(favoriteKind, itemId)!.dirty, isTrue);
      final report = await a.sync();
      expect(report.pushed, 1);
      await b.sync();
      expect(b.favorites(syncId, MediaKind.live), isEmpty);
    });
  });

  test('two calls at once share one pass', () async {
    final first = a.engine.syncNow();
    final second = a.engine.syncNow();
    expect(identical(first, second), isTrue);
    await first;
  });
}
