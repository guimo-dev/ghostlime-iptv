import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_crypto.dart';
import 'package:iptv_player/sync/sync_engine.dart';
import 'package:iptv_player/sync/sync_ids.dart';

import 'fake_passwords.dart';

const _m3u = Playlist(
  name: 'Lista',
  type: PlaylistType.m3uUrl,
  source: 'http://h/l.m3u',
);

/// One simulated device: its own database and secure storage.
class _Device {
  _Device(this.backend, List<int> key) {
    engine = SyncEngine(db, backend, key, passwords);
  }

  final InMemorySyncBackend backend;
  final CatalogDb db = CatalogDb.inMemory();
  final FakePasswords passwords = FakePasswords();
  late final SyncEngine engine;

  Future<SyncReport> sync() => engine.syncNow();

  /// Local id of the playlist with [syncId].
  int playlist(String syncId) => db.playlistIdForSyncId(syncId)!;

  /// Saves settings with [cache] as the network cache seconds, stamped at
  /// [at].
  void saveCache(int cache, DateTime at) {
    db.saveSettings(AppSettings(networkCacheSecs: cache).toJson());
    db.markDirty(settingsKind, settingsItemId, at: at);
  }

  int get cache => AppSettings.fromJson(db.loadSettings()).networkCacheSecs;
}

void main() {
  final key = SyncCrypto.randomBytes(32);
  // Relative to now: the real clock wins over fixed dates (see APRENDIZAJES).
  final now = DateTime.now().toUtc();
  final t1 = now.add(const Duration(hours: 1));
  final t2 = now.add(const Duration(hours: 2));
  late InMemorySyncBackend backend;
  late _Device a;
  late _Device b;
  late String syncId;

  setUp(() async {
    backend = InMemorySyncBackend();
    a = _Device(backend, key);
    b = _Device(backend, key);
    syncId = a.db.syncIdOfPlaylist(a.db.savePlaylist(_m3u))!;
    await a.sync();
    await b.sync();
  });
  tearDown(() {
    a.db.close();
    b.db.close();
  });

  test('settings sync is on by default and stored on the device only', () {
    expect(a.db.syncSettingsEnabled(), isTrue);
    a.db.saveSyncSettingsEnabled(false);
    expect(a.db.syncSettingsEnabled(), isFalse);
    expect(a.db.dirtyItems(), isEmpty, reason: 'the switch is not synced');
  });

  test(
    'switched off, settings and list prefs stay home; the rest travels',
    () async {
      a.db.saveSyncSettingsEnabled(false);
      a.saveCache(30, t1);
      a.db.saveChannelSort(
        a.playlist(syncId),
        MediaKind.live,
        'c',
        const ChannelSort(mode: SortMode.alphaAsc),
      );
      a.db.setFavorite(a.playlist(syncId), MediaKind.live, 'ch:1', true);

      await a.sync();
      expect(backend.items.map((i) => i.kind), isNot(contains(settingsKind)));
      expect(backend.items.map((i) => i.kind), isNot(contains(prefKind)));
      final report = await b.sync();

      expect(report.settingsApplied, isFalse);
      expect(b.cache, isNot(30));
      expect(
        b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
        isFalse,
      );
      expect(b.db.favoriteKeys(b.playlist(syncId), MediaKind.live), {'ch:1'});
    },
  );

  test('switched off, remote settings and prefs are not applied', () async {
    b.db.saveSyncSettingsEnabled(false);
    a.saveCache(30, t1);
    a.db.saveChannelSort(
      a.playlist(syncId),
      MediaKind.live,
      'c',
      const ChannelSort(mode: SortMode.alphaAsc),
    );
    a.db.setFavorite(a.playlist(syncId), MediaKind.live, 'ch:1', true);
    await a.sync();

    final report = await b.sync();

    expect(report.settingsApplied, isFalse);
    expect(b.cache, isNot(30));
    expect(
      b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
      isFalse,
    );
    expect(b.db.favoriteKeys(b.playlist(syncId), MediaKind.live), {'ch:1'});
  });

  test('switched back on, a newer remote change wins', () async {
    b.db.saveSyncSettingsEnabled(false);
    b.saveCache(45, t1);
    a.saveCache(30, t2);
    a.db.saveChannelSort(
      a.playlist(syncId),
      MediaKind.live,
      'c',
      const ChannelSort(mode: SortMode.alphaAsc),
    );
    await a.sync();
    await b.sync();
    expect(b.cache, 45);

    b.db.saveSyncSettingsEnabled(true);
    final report = await b.sync();

    expect(report.settingsApplied, isTrue);
    expect(b.cache, 30);
    expect(
      b.db.channelSort(b.playlist(syncId), MediaKind.live, 'c').mode,
      SortMode.alphaAsc,
    );
    await a.sync();
    expect(a.cache, 30);
  });

  test('switched back on, a newer local change wins and is uploaded', () async {
    b.db.saveSyncSettingsEnabled(false);
    a.saveCache(30, t1);
    await a.sync();
    await b.sync();
    b.saveCache(45, t2);
    await b.sync();

    b.db.saveSyncSettingsEnabled(true);
    await b.sync();
    expect(b.cache, 45);
    await a.sync();
    expect(a.cache, 45);
  });

  test('catching up happens once', () async {
    b.db.saveSyncSettingsEnabled(false);
    b.db.saveSyncSettingsEnabled(true);
    expect(b.db.syncSettingsCatchUp(), isTrue);
    await b.sync();
    expect(b.db.syncSettingsCatchUp(), isFalse);
  });

  group('removed list preferences', () {
    /// Gives both devices the same own sort for category "c".
    Future<void> shareSort() async {
      a.db.saveChannelSort(
        a.playlist(syncId),
        MediaKind.live,
        'c',
        const ChannelSort(mode: SortMode.alphaAsc),
      );
      await a.sync();
      await b.sync();
      expect(
        b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
        isTrue,
      );
    }

    test('switched off, a local removal is not uploaded', () async {
      await shareSort();
      a.db.saveSyncSettingsEnabled(false);
      a.db.deleteChannelSort(a.playlist(syncId), MediaKind.live, 'c');
      await a.sync();
      expect(
        backend.items.where((i) => i.kind == prefKind && i.deleted),
        isEmpty,
      );
      await b.sync();
      expect(
        b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
        isTrue,
      );
    });

    test('switched off, a remote removal waits until it is on again', () async {
      await shareSort();
      b.db.saveSyncSettingsEnabled(false);
      a.db.deleteChannelSort(a.playlist(syncId), MediaKind.live, 'c');
      await a.sync();
      await b.sync();
      expect(
        b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
        isTrue,
      );

      b.db.saveSyncSettingsEnabled(true);
      await b.sync();
      expect(
        b.db.hasOwnChannelSort(b.playlist(syncId), MediaKind.live, 'c'),
        isFalse,
      );
    });
  });
}
