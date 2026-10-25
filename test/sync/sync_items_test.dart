import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/sync/sync_crypto.dart';
import 'package:iptv_player/sync/sync_ids.dart';
import 'package:iptv_player/sync/sync_items.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

import 'fake_passwords.dart';

const _m3u = Playlist(
  name: 'M3U',
  type: PlaylistType.m3uUrl,
  source: 'http://h/list.m3u?token=secret',
);
const _xtream = Playlist(
  name: 'Xtream',
  type: PlaylistType.xtream,
  serverUrl: 'http://server:8080',
  username: 'user',
  userAgent: 'UA',
  liveFormat: LiveFormat.m3u8,
  epgUrl: 'http://epg/x.xml',
);
const _target = PlayTarget(
  kind: MediaKind.series,
  key: 'xe:7',
  title: 'Serie T1E2',
  iconUrl: 'http://img/1.png',
  xtreamType: XtreamStreamType.series,
  xtreamId: 7,
  extension: 'mkv',
  seriesKey: 'xs:1',
);

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 10);
  late CatalogDb db;
  late CatalogDb other;
  late FakePasswords passwords;
  late FakePasswords otherPasswords;
  late ItemIds ids;

  /// The dirty states as `kind|itemId` text, sorted.
  List<String> dirty(CatalogDb d) =>
      d.dirtyItems().map((s) => '${s.kind}|${s.itemId}').toList()..sort();

  setUp(() {
    db = CatalogDb.inMemory();
    other = CatalogDb.inMemory();
    passwords = FakePasswords();
    otherPasswords = FakePasswords();
    ids = ItemIds(SyncCrypto.randomBytes(32));
    db.itemIds = ids;
    other.itemIds = ids;
  });
  tearDown(() {
    db.close();
    other.close();
  });

  /// Saves [playlist] in [db], then copies it to [other] through export/apply.
  Future<int> shared(Playlist playlist, {String? password}) async {
    final id = db.savePlaylist(playlist);
    if (password != null) passwords.values[id] = password;
    final state = db.syncState(playlistKind, db.syncIdOfPlaylist(id)!)!;
    final item = await exportPlaylistItem(db, passwords, state);
    await applyPlaylistItem(other, otherPasswords, item);
    return id;
  }

  group('ids', () {
    test('newSyncId is unique and hex with dashes', () {
      final a = newSyncId();
      expect(
        a,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(newSyncId(), isNot(a));
    });

    test('item ids are opaque: playlist prefix and 32 hex characters', () {
      final id = ids.favorite('sync', MediaKind.live, 'Nombre del canal');
      expect(id, matches(RegExp(r'^sync:[0-9a-f]{32}$')));
      expect(
        ids.pref('sync', 'categories/live'),
        matches(RegExp(r'^sync:[0-9a-f]{32}$')),
      );
      expect(
        ids.pref(null, 'channels/default'),
        matches(RegExp(r'^global:[0-9a-f]{32}$')),
      );
    });

    test('item ids are stable for one key and differ between keys', () {
      final keyA = SyncCrypto.randomBytes(32);
      final keyB = SyncCrypto.randomBytes(32);

      String favorite(List<int> key) =>
          ItemIds(key).favorite('sync', MediaKind.live, 'Canal');

      expect(favorite(keyA), favorite(keyA));
      expect(favorite(keyA), isNot(favorite(keyB)));
      expect(
        ItemIds(keyA).pref('sync', 'channels/default'),
        isNot(ItemIds(keyB).pref('sync', 'channels/default')),
      );
    });

    test('kind and key both change the id; progress shares favorite ids', () {
      expect(
        ids.favorite('sync', MediaKind.live, 'k'),
        isNot(ids.favorite('sync', MediaKind.movie, 'k')),
      );
      expect(
        ids.favorite('sync', MediaKind.live, 'k'),
        isNot(ids.favorite('sync', MediaKind.live, 'j')),
      );
      expect(
        ids.progress('sync', MediaKind.live, 'k'),
        ids.favorite('sync', MediaKind.live, 'k'),
      );
    });

    test('without an id key nothing is tracked for favorites', () {
      db.itemIds = null;
      final id = db.savePlaylist(_m3u);
      db.markClean(playlistKind, db.syncIdOfPlaylist(id)!, t0);

      db.setFavorite(id, MediaKind.live, 'k', true);

      expect(dirty(db), isEmpty);
    });

    test('only sort, hidden-category and live guide scopes are synced', () {
      expect(isSyncedPrefScope('channels/default'), isTrue);
      expect(isSyncedPrefScope('channels/live/c1'), isTrue);
      expect(isSyncedPrefScope('categories/movie'), isTrue);
      expect(isSyncedPrefScope('live/guide-grid'), isTrue);
      expect(isSyncedPrefScope('epg/refreshed'), isFalse);
      expect(isSyncedPrefScope('epg/m3u-url'), isFalse);
      expect(isSyncedPrefScope('settings'), isFalse);
    });
  });

  group('sync state', () {
    test('markDirty, dirtyItems, markClean and syncState', () {
      expect(db.syncState('favorite', 'a'), isNull);
      db.markDirty('favorite', 'a', at: t0);
      db.markDirty('favorite', 'b', deleted: true, at: t0);
      expect(dirty(db), ['favorite|a', 'favorite|b']);
      final b = db.syncState('favorite', 'b')!;
      expect((b.dirty, b.deleted, b.updatedAt), (true, true, t0));
      db.markClean('favorite', 'b', t0, deleted: true);
      expect(dirty(db), ['favorite|a']);
      final clean = db.syncState('favorite', 'b')!;
      expect((clean.dirty, clean.deleted), (false, true));
    });

    test('markClean registers elements never seen, with the remote time', () {
      final later = t0.add(const Duration(minutes: 3));
      db.markClean('pref', 'x', later);
      final state = db.syncState('pref', 'x')!;
      expect(
        (state.dirty, state.deleted, state.updatedAt),
        (false, false, later),
      );
    });

    test(
      'markAllDirty dirties known elements and adds unknown ones at the epoch',
      () {
        db.markDirty('favorite', 'known', at: t0);
        db.markClean('favorite', 'known', t0);
        db.markAllDirty([(kind: 'favorite', itemId: 'new')]);
        expect(dirty(db), ['favorite|known', 'favorite|new']);
        expect(db.syncState('favorite', 'known')!.updatedAt, t0);
        expect(
          db.syncState('favorite', 'new')!.updatedAt.millisecondsSinceEpoch,
          0,
        );
      },
    );

    test('the cursor is saved and forgotten', () {
      expect(db.syncCursor(), isNull);
      db.saveSyncCursor(t0);
      expect(db.syncCursor(), t0);
      db.saveSyncCursor(null);
      expect(db.syncCursor(), isNull);
    });

    test('the cursor is not a synced preference', () {
      db.saveSyncCursor(t0);
      expect(dirty(db), isEmpty);
      expect(db.allPrefs(), isEmpty);
    });
  });

  group('local writes mark elements dirty', () {
    test('saving a new playlist gives it a sync id and marks it dirty', () {
      final id = db.savePlaylist(_m3u);
      final syncId = db.playlists().single.syncId!;
      expect(db.syncIdOfPlaylist(id), syncId);
      expect(db.playlistIdForSyncId(syncId), id);
      expect(dirty(db), ['playlist|$syncId']);
    });

    test('a playlist saved with a sync id keeps it', () {
      db.savePlaylist(_m3u.copyWith(syncId: 'fixed-id'));
      expect(db.playlists().single.syncId, 'fixed-id');
    });

    test('editing a playlist keeps its sync id and marks it dirty again', () {
      final id = db.savePlaylist(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      db.markClean(
        playlistKind,
        syncId,
        db.syncState(playlistKind, syncId)!.updatedAt,
      );
      expect(dirty(db), isEmpty);
      db.savePlaylist(_m3u.copyWith(id: id, name: 'Otro'));
      expect(db.syncIdOfPlaylist(id), syncId);
      expect(dirty(db), ['playlist|$syncId']);
    });

    test(
      'deleting a playlist leaves one tombstone and forgets its children',
      () {
        final id = db.savePlaylist(_m3u);
        final syncId = db.syncIdOfPlaylist(id)!;
        db.setFavorite(id, MediaKind.live, 'k', true);
        db.saveProgress(id, _target, Duration.zero, Duration.zero);
        db.saveChannelSort(id, MediaKind.live, 'c', const ChannelSort());
        db.deletePlaylist(id);
        expect(dirty(db), ['playlist|$syncId']);
        expect(db.syncState(playlistKind, syncId)!.deleted, isTrue);
        expect(db.syncIdOfPlaylist(id), isNull);
      },
    );

    test('favorites: add, repeat, remove, remove again', () {
      final id = db.savePlaylist(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      final itemId = ids.favorite(syncId, MediaKind.live, 'k');
      db.setFavorite(id, MediaKind.live, 'k', true);
      expect(db.syncState(favoriteKind, itemId)!.deleted, isFalse);
      final added = db.syncState(favoriteKind, itemId)!;
      db.markClean(favoriteKind, itemId, added.updatedAt);
      db.setFavorite(id, MediaKind.live, 'k', true);
      expect(db.syncState(favoriteKind, itemId)!.dirty, isFalse);
      db.setFavorite(id, MediaKind.live, 'k', false);
      expect(db.syncState(favoriteKind, itemId)!.deleted, isTrue);
      expect(db.syncState(favoriteKind, itemId)!.dirty, isTrue);
      db.markClean(
        favoriteKind,
        itemId,
        db.syncState(favoriteKind, itemId)!.updatedAt,
        deleted: true,
      );
      db.setFavorite(id, MediaKind.live, 'k', false);
      expect(db.syncState(favoriteKind, itemId)!.dirty, isFalse);
    });

    test('a favorite of an unknown playlist is saved but not tracked', () {
      db.setFavorite(99, MediaKind.live, 'k', true);
      expect(db.favoriteKeys(99, MediaKind.live), {'k'});
      expect(dirty(db), isEmpty);
    });

    test('progress: save with its own time, clear one, clear all', () {
      final id = db.savePlaylist(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      final itemId = ids.progress(syncId, MediaKind.series, 'xe:7');
      db.saveProgress(
        id,
        _target,
        const Duration(seconds: 5),
        const Duration(seconds: 50),
        at: t0,
      );
      expect(db.syncState(progressKind, itemId)!.updatedAt, t0);
      db.clearProgress(id, MediaKind.series, 'xe:7');
      expect(db.syncState(progressKind, itemId)!.deleted, isTrue);

      db.saveProgress(id, _target, Duration.zero, Duration.zero, at: t0);
      db.saveProgress(
        id,
        _target.withKey('xe:8'),
        Duration.zero,
        Duration.zero,
        at: t0,
      );
      db.clearAllProgress();
      final other8 = ids.progress(syncId, MediaKind.series, 'xe:8');
      expect(db.syncState(progressKind, itemId)!.deleted, isTrue);
      expect(db.syncState(progressKind, other8)!.deleted, isTrue);
      expect(db.syncState(progressKind, other8)!.dirty, isTrue);
    });

    test('prefs: sorts and hidden categories sync, guide data does not', () {
      final id = db.savePlaylist(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      db.markClean(
        playlistKind,
        syncId,
        db.syncState(playlistKind, syncId)!.updatedAt,
      );
      db.saveDefaultChannelSort(const ChannelSort(mode: SortMode.alphaAsc));
      db.saveChannelSort(
        id,
        MediaKind.live,
        'c1',
        const ChannelSort(mode: SortMode.manual),
      );
      db.saveCategorySort(
        id,
        MediaKind.live,
        const CategorySort(hidden: {'c2'}),
      );
      db.saveM3uTvgUrl(id, 'http://epg');
      db.replaceEpg(id, const [], t0);
      expect(
        dirty(db),
        [
          'pref|${ids.pref(null, 'channels/default')}',
          'pref|${ids.pref(syncId, 'channels/live/c1')}',
          'pref|${ids.pref(syncId, 'categories/live')}',
        ]..sort(),
      );
    });

    test(
      'an unchanged pref is not dirtied again; deleting one is a tombstone',
      () {
        final id = db.savePlaylist(_m3u);
        final syncId = db.syncIdOfPlaylist(id)!;
        final itemId = ids.pref(syncId, 'channels/live/c1');
        db.saveChannelSort(id, MediaKind.live, 'c1', const ChannelSort());
        db.markClean(
          prefKind,
          itemId,
          db.syncState(prefKind, itemId)!.updatedAt,
        );
        db.saveChannelSort(id, MediaKind.live, 'c1', const ChannelSort());
        expect(db.syncState(prefKind, itemId)!.dirty, isFalse);
        db.deleteChannelSort(id, MediaKind.live, 'c1');
        expect(db.syncState(prefKind, itemId)!.deleted, isTrue);
        expect(db.syncState(prefKind, itemId)!.dirty, isTrue);
      },
    );

    test('settings: only changes to synced fields mark dirty', () {
      db.saveSettings(const AppSettings(networkCacheSecs: 30).toJson());
      expect(dirty(db), ['settings|settings']);
      db.markClean(
        settingsKind,
        settingsItemId,
        db.syncState(settingsKind, settingsItemId)!.updatedAt,
      );
      db.saveSettings(
        const AppSettings(
          networkCacheSecs: 30,
          lastPlaylistId: 4,
          parentalLock: true,
        ).toJson(),
      );
      expect(dirty(db), isEmpty);
      db.saveSettings(const AppSettings(networkCacheSecs: 31).toJson());
      expect(dirty(db), ['settings|settings']);
    });
  });

  group('export and apply', () {
    test('playlist travels with its password and the same sync id', () async {
      final id = await shared(_xtream, password: 'pw');
      final syncId = db.syncIdOfPlaylist(id)!;
      final created = other.playlists().single;
      expect(created.syncId, syncId);
      expect(created.name, 'Xtream');
      expect(created.type, PlaylistType.xtream);
      expect(created.serverUrl, 'http://server:8080');
      expect(created.username, 'user');
      expect(created.userAgent, 'UA');
      expect(created.liveFormat, LiveFormat.m3u8);
      expect(created.epgUrl, 'http://epg/x.xml');
      expect(otherPasswords.values[created.id], 'pw');
      expect(dirty(other), isEmpty);
      expect(other.syncState(playlistKind, syncId)!.deleted, isFalse);
    });

    test('the export has no local id or refresh time', () async {
      final id = db.savePlaylist(_m3u);
      final state = db.syncState(playlistKind, db.syncIdOfPlaylist(id)!)!;
      final item = await exportPlaylistItem(db, passwords, state);
      expect(item.deleted, isFalse);
      expect(item.updatedAt, state.updatedAt);
      expect(item.data!.keys, isNot(contains('id')));
      expect(item.data!.keys, isNot(contains('refreshedAt')));
      expect(item.data!['source'], 'http://h/list.m3u?token=secret');
    });

    test(
      'applying reports created playlists, and updates that change the source',
      () async {
        final id = db.savePlaylist(_m3u);
        final syncId = db.syncIdOfPlaylist(id)!;
        var item = await exportPlaylistItem(
          db,
          passwords,
          db.syncState(playlistKind, syncId)!,
        );
        final first = await applyPlaylistItem(other, otherPasswords, item);
        expect(first!.created, isTrue);
        expect(first.playlist.syncId, syncId);
        expect(first.playlist.id, isNotNull);

        final localId = other.playlistIdForSyncId(syncId)!;
        other.replaceCatalog(
          localId,
          const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
          const [
            Channel(key: 'k', name: 'K', categoryId: 'c', kind: MediaKind.live),
          ],
          t0,
        );
        db.savePlaylist(_m3u.copyWith(id: id, name: 'Renombrada'));
        item = await exportPlaylistItem(
          db,
          passwords,
          db.syncState(playlistKind, syncId)!,
        );
        expect(await applyPlaylistItem(other, otherPasswords, item), isNull);
        expect(other.playlists().single.name, 'Renombrada');
        expect(other.channelCount(localId, MediaKind.live), 1);

        db.savePlaylist(_m3u.copyWith(id: id, source: 'http://h/otra.m3u'));
        item = await exportPlaylistItem(
          db,
          passwords,
          db.syncState(playlistKind, syncId)!,
        );
        final changed = await applyPlaylistItem(other, otherPasswords, item);
        expect(changed!.created, isFalse);
        expect(other.channelCount(localId, MediaKind.live), 0);
        expect(other.playlists().single.refreshedAt, isNull);
        expect(dirty(other), isEmpty);
      },
    );

    test('a changed password also asks for a catalog download', () async {
      final id = await shared(_xtream, password: 'one');
      final syncId = db.syncIdOfPlaylist(id)!;
      passwords.values[id] = 'two';
      db.savePlaylist(db.playlists().single);
      final item = await exportPlaylistItem(
        db,
        passwords,
        db.syncState(playlistKind, syncId)!,
      );
      final changed = await applyPlaylistItem(other, otherPasswords, item);
      expect(changed!.created, isFalse);
      expect(otherPasswords.values[other.playlistIdForSyncId(syncId)], 'two');
    });

    test(
      'deleting a playlist remotely removes it, its catalog and its password',
      () async {
        final id = await shared(_xtream, password: 'pw');
        final syncId = db.syncIdOfPlaylist(id)!;
        final localId = other.playlistIdForSyncId(syncId)!;
        other.replaceCatalog(
          localId,
          const [Category(id: 'c', name: 'C', kind: MediaKind.live)],
          const [
            Channel(key: 'k', name: 'K', categoryId: 'c', kind: MediaKind.live),
          ],
          t0,
        );
        other.setFavorite(localId, MediaKind.live, 'k', true);
        db.deletePlaylist(id);
        final item = await exportPlaylistItem(
          db,
          passwords,
          db.syncState(playlistKind, syncId)!,
        );
        expect(item.deleted, isTrue);
        expect(item.data, isNull);
        expect(await applyPlaylistItem(other, otherPasswords, item), isNull);
        expect(other.playlists(), isEmpty);
        expect(other.channelCount(localId, MediaKind.live), 0);
        expect(other.favoriteKeys(localId, MediaKind.live), isEmpty);
        expect(otherPasswords.values, isEmpty);
        expect(dirty(other), isEmpty);
        expect(other.syncState(playlistKind, syncId)!.deleted, isTrue);
      },
    );

    test(
      'favorite round-trip keeps the real key only in the payload',
      () async {
        final id = await shared(_m3u);
        final syncId = db.syncIdOfPlaylist(id)!;
        final itemId = ids.favorite(syncId, MediaKind.movie, 'xm:99');
        db.setFavorite(id, MediaKind.movie, 'xm:99', true, addedAt: t0);
        final item = exportFavoriteItem(
          db,
          db.syncState(favoriteKind, itemId)!,
        );
        expect(item.itemId, itemId);
        expect(itemId, isNot(contains('xm:99')));
        expect(jsonEncode(item.data), contains('xm:99'));
        applyFavoriteItem(other, item);
        final localId = other.playlistIdForSyncId(syncId)!;
        expect(other.favoriteKeys(localId, MediaKind.movie), {'xm:99'});
        expect(other.syncState(favoriteKind, itemId)!.dirty, isFalse);
        expect(
          other.syncState(favoriteKind, itemId)!.updatedAt,
          item.updatedAt,
        );
        expect(dirty(other), isEmpty);
      },
    );

    test('favorite deletion round-trip', () async {
      final id = await shared(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      final itemId = ids.favorite(syncId, MediaKind.live, 'k');
      db.setFavorite(id, MediaKind.live, 'k', true);
      applyFavoriteItem(
        other,
        exportFavoriteItem(db, db.syncState(favoriteKind, itemId)!),
      );
      db.setFavorite(id, MediaKind.live, 'k', false);
      final item = exportFavoriteItem(db, db.syncState(favoriteKind, itemId)!);
      expect(item.deleted, isTrue);
      expect(item.data, isNull);
      applyFavoriteItem(other, item);
      expect(
        other.favoriteKeys(other.playlistIdForSyncId(syncId)!, MediaKind.live),
        isEmpty,
      );
      expect(other.syncState(favoriteKind, itemId)!.deleted, isTrue);
      expect(dirty(other), isEmpty);
    });

    test(
      'a favorite of a playlist this device does not have is ignored',
      () async {
        final id = db.savePlaylist(_m3u);
        final syncId = db.syncIdOfPlaylist(id)!;
        db.setFavorite(id, MediaKind.live, 'k', true);
        final item = exportFavoriteItem(
          db,
          db.syncState(
            favoriteKind,
            ids.favorite(syncId, MediaKind.live, 'k'),
          )!,
        );
        applyFavoriteItem(other, item);
        expect(other.allFavorites(), isEmpty);
        expect(dirty(other), isEmpty);
      },
    );

    test('a dirty element whose data vanished exports as a deletion', () async {
      final id = db.savePlaylist(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      db.markDirty(
        favoriteKind,
        ids.favorite(syncId, MediaKind.live, 'ghost'),
        at: t0,
      );
      final item = exportFavoriteItem(
        db,
        db.dirtyItems().firstWhere((s) => s.kind == favoriteKind),
      );
      expect(item.deleted, isTrue);
    });

    test('progress round-trip and deletion', () async {
      final id = await shared(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      final itemId = ids.progress(syncId, MediaKind.series, 'xe:7');
      db.saveProgress(
        id,
        _target,
        const Duration(seconds: 12),
        const Duration(seconds: 90),
        at: t0,
      );
      final item = exportProgressItem(db, db.syncState(progressKind, itemId)!);
      applyProgressItem(other, item);
      final localId = other.playlistIdForSyncId(syncId)!;
      final progress = other.progress(localId, MediaKind.series, 'xe:7')!;
      expect(progress.position, const Duration(seconds: 12));
      expect(progress.duration, const Duration(seconds: 90));
      expect(progress.updatedAt, t0);
      expect(progress.target.title, 'Serie T1E2');
      expect(progress.target.xtreamType, XtreamStreamType.series);
      expect(progress.target.xtreamId, 7);
      expect(progress.target.extension, 'mkv');
      expect(progress.target.seriesKey, 'xs:1');
      expect(other.syncState(progressKind, itemId)!.updatedAt, t0);
      expect(dirty(other), isEmpty);

      db.clearProgress(id, MediaKind.series, 'xe:7');
      final gone = exportProgressItem(db, db.syncState(progressKind, itemId)!);
      expect(gone.deleted, isTrue);
      applyProgressItem(other, gone);
      expect(other.progress(localId, MediaKind.series, 'xe:7'), isNull);
      expect(dirty(other), isEmpty);
    });

    test('pref round-trip, global and per playlist, and deletion', () async {
      final id = await shared(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      final localId = other.playlistIdForSyncId(syncId)!;
      db.saveDefaultChannelSort(
        const ChannelSort(mode: SortMode.alphaDesc, favoritesFirst: true),
      );
      db.saveCategorySort(
        id,
        MediaKind.live,
        const CategorySort(
          mode: SortMode.manual,
          manualOrder: ['b', 'a'],
          hidden: {'z'},
        ),
      );
      for (final state in db.dirtyItems().where((s) => s.kind == prefKind)) {
        applyPrefItem(other, exportPrefItem(db, state));
      }
      expect(other.defaultChannelSort().mode, SortMode.alphaDesc);
      expect(other.defaultChannelSort().favoritesFirst, isTrue);
      final categories = other.categorySort(localId, MediaKind.live);
      expect(categories.manualOrder, ['b', 'a']);
      expect(categories.hidden, {'z'});
      expect(dirty(other), isEmpty);

      db.saveChannelSort(id, MediaKind.live, 'c', const ChannelSort());
      final itemId = ids.pref(syncId, 'channels/live/c');
      applyPrefItem(other, exportPrefItem(db, db.syncState(prefKind, itemId)!));
      expect(other.hasOwnChannelSort(localId, MediaKind.live, 'c'), isTrue);
      db.deleteChannelSort(id, MediaKind.live, 'c');
      final gone = exportPrefItem(db, db.syncState(prefKind, itemId)!);
      expect(gone.deleted, isTrue);
      applyPrefItem(other, gone);
      expect(other.hasOwnChannelSort(localId, MediaKind.live, 'c'), isFalse);
      expect(dirty(other), isEmpty);
    });

    test('settings never carry local-only fields and never overwrite them', () {
      db.saveSettings(
        const AppSettings(
          networkCacheSecs: 45,
          accentColor: AccentColor.cyan,
          parentalLock: true,
          lockedCategories: {'1/live/x'},
          lastPlaylistId: 3,
        ).toJson(),
      );
      final item = exportSettingsItem(
        db,
        db.syncState(settingsKind, settingsItemId)!,
      );
      final text = jsonEncode(item.data);
      expect(text, isNot(contains('parentalLock')));
      expect(text, isNot(contains('lockedCategories')));
      expect(text, isNot(contains('lastPlaylistId')));

      other.saveSettings(
        const AppSettings(
          parentalLock: true,
          hideAdult: true,
          lockedCategories: {'9/live/y'},
          lastPlaylistId: 8,
        ).toJson(),
      );
      applySettingsItem(other, item);
      final applied = AppSettings.fromJson(other.loadSettings());
      expect(applied.networkCacheSecs, 45);
      expect(applied.accentColor, AccentColor.cyan);
      expect(applied.parentalLock, isTrue);
      expect(applied.lockedCategories, {'9/live/y'});
      expect(applied.lastPlaylistId, 8);
      expect(dirty(other), isEmpty);
      expect(
        other.syncState(settingsKind, settingsItemId)!.updatedAt,
        item.updatedAt,
      );
    });

    test('applyItem and exportItem dispatch by kind', () async {
      final id = await shared(_m3u);
      final syncId = db.syncIdOfPlaylist(id)!;
      db.setFavorite(id, MediaKind.live, 'k', true);
      final state = db.syncState(
        favoriteKind,
        ids.favorite(syncId, MediaKind.live, 'k'),
      )!;
      final item = await exportItem(db, passwords, state);
      expect(item.kind, favoriteKind);
      await applyItem(other, otherPasswords, item);
      expect(other.allFavorites().single.key, 'k');
    });
  });
}

extension on PlayTarget {
  PlayTarget withKey(String key) =>
      PlayTarget(kind: kind, key: key, title: title);
}
