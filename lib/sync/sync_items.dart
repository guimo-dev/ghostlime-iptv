import 'dart:convert';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../player/play_target.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/settings_transfer.dart';
import '../xtream/xtream_urls.dart';
import 'sync_ids.dart';

/// One synced element in clear form: [data] is the JSON that gets encrypted
/// (`null` for a deletion).
typedef SyncItem = ({
  String kind,
  String itemId,
  Map<String, Object?>? data,
  DateTime updatedAt,
  bool deleted,
});

/// A playlist that must download its catalog after a remote change.
typedef PlaylistToSync = ({Playlist playlist, bool created});

/// Local favorites, progress and preferences addressed by `item_id`, built
/// once per pass so looking each one up is not quadratic. Deletions arrive
/// with only an `item_id`, and this is how they find what to remove.
class SyncLocalIndex {
  SyncLocalIndex(this._db);

  final CatalogDb _db;

  late final Map<int, String> _syncIds = {
    for (final p in _db.playlists())
      if (p.syncId != null) p.id!: p.syncId!,
  };

  /// Favorites by `item_id`.
  late final Map<
    String,
    ({
      String playlistSyncId,
      int playlistId,
      MediaKind kind,
      String key,
      DateTime addedAt,
    })
  >
  favorites = {
    if (_db.itemIds case final ids?)
      for (final f in _db.allFavorites())
        if (_syncIds[f.playlistId] case final syncId?)
          ids.favorite(syncId, f.kind, f.key): (
            playlistSyncId: syncId,
            playlistId: f.playlistId,
            kind: f.kind,
            key: f.key,
            addedAt: f.addedAt,
          ),
  };

  /// Progress by `item_id`.
  late final Map<
    String,
    ({String playlistSyncId, int playlistId, Progress progress})
  >
  progress = {
    if (_db.itemIds case final ids?)
      for (final p in _db.allProgress())
        if (_syncIds[p.playlistId] case final syncId?)
          ids.progress(syncId, p.progress.target.kind, p.progress.target.key): (
            playlistSyncId: syncId,
            playlistId: p.playlistId,
            progress: p.progress,
          ),
  };

  /// Preferences by `item_id`.
  late final Map<
    String,
    ({
      String? playlistSyncId,
      int playlistId,
      String scope,
      Map<String, Object?> value,
    })
  >
  prefs = {
    if (_db.itemIds case final ids?)
      for (final p in _db.allPrefs())
        if (p.playlistId == 0 || _syncIds.containsKey(p.playlistId))
          ids.pref(_syncIds[p.playlistId], p.scope): (
            playlistSyncId: _syncIds[p.playlistId],
            playlistId: p.playlistId,
            scope: p.scope,
            value: p.value,
          ),
  };

  /// Every local syncable element as `(kind, itemId)` (settings only once
  /// saved), used to upload everything on the first sync of an account.
  List<({String kind, String itemId})> allItems() => [
    for (final syncId in _syncIds.values) (kind: playlistKind, itemId: syncId),
    for (final id in favorites.keys) (kind: favoriteKind, itemId: id),
    for (final id in progress.keys) (kind: progressKind, itemId: id),
    for (final id in prefs.keys) (kind: prefKind, itemId: id),
    if (_db.loadSettings().isNotEmpty)
      (kind: settingsKind, itemId: settingsItemId),
  ];
}

/// The element for [state] as a deletion.
SyncItem _gone(SyncState state) => (
  kind: state.kind,
  itemId: state.itemId,
  data: null,
  updatedAt: state.updatedAt,
  deleted: true,
);

SyncItem _present(SyncState state, Map<String, Object?> data) => (
  kind: state.kind,
  itemId: state.itemId,
  data: data,
  updatedAt: state.updatedAt,
  deleted: false,
);

DateTime _fromMicros(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

/// Playlist element for [state], password included. A playlist that no longer
/// exists exports as a deletion.
Future<SyncItem> exportPlaylistItem(
  CatalogDb db,
  PasswordStore passwords,
  SyncState state,
) async {
  final id = state.deleted ? null : db.playlistIdForSyncId(state.itemId);
  if (id == null) return _gone(state);
  final playlist = db.playlists().firstWhere((p) => p.id == id);
  return _present(state, {
    'name': playlist.name,
    'type': playlist.type.name,
    'serverUrl': playlist.serverUrl,
    'username': playlist.username,
    'source': playlist.source,
    'userAgent': playlist.userAgent,
    'liveFormat': playlist.liveFormat.name,
    'epgUrl': playlist.epgUrl,
    'password': playlist.type == PlaylistType.xtream
        ? await passwords.read(id)
        : null,
  });
}

/// What makes two playlists the same source, whatever their `sync_id`: type,
/// server (lowercase, no trailing slash) and username for Xtream; type and
/// source for the rest. `null` when the fields that define it are missing.
String? playlistIdentity(Playlist playlist) {
  String? present(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  if (playlist.type == PlaylistType.xtream) {
    final server = present(playlist.serverUrl)
        ?.toLowerCase()
        .replaceAll(RegExp(r'/+$'), '');
    final username = present(playlist.username);
    if (server == null || username == null) return null;
    return 'xtream|$server|$username';
  }
  final source = present(playlist.source);
  return source == null ? null : '${playlist.type.name}|$source';
}

/// The local playlist with the smallest `sync_id` among those sharing
/// [identity], if any.
Playlist? _survivorOf(CatalogDb db, String identity) {
  Playlist? best;
  for (final p in db.playlists()) {
    final syncId = p.syncId;
    if (syncId == null || playlistIdentity(p) != identity) continue;
    if (best == null || syncId.compareTo(best.syncId!) < 0) best = p;
  }
  return best;
}

/// Creates, updates or deletes the local playlist described by [item]; returns
/// the playlist whose catalog must be downloaded (created, or with a new
/// source or password), if any.
///
/// A playlist with an unknown `sync_id` whose source a local playlist already
/// has is the same playlist added on two devices: the smallest `sync_id`
/// survives. If the remote one is smaller the local row takes its `sync_id`
/// (catalog and library data stay); otherwise the remote one is deleted
/// instead of copied.
Future<PlaylistToSync?> applyPlaylistItem(
  CatalogDb db,
  PasswordStore passwords,
  SyncItem item,
) async {
  var existingId = db.playlistIdForSyncId(item.itemId);
  final data = item.data;
  if (item.deleted || data == null) {
    if (existingId != null) {
      db.deletePlaylist(existingId);
      await passwords.delete(existingId);
    }
    db.markClean(item.kind, item.itemId, item.updatedAt, deleted: true);
    return null;
  }
  final remote = Playlist(
    syncId: item.itemId,
    name: data['name']! as String,
    type: PlaylistType.values.byName(data['type']! as String),
    serverUrl: data['serverUrl'] as String?,
    username: data['username'] as String?,
    source: data['source'] as String?,
    userAgent: data['userAgent'] as String?,
    liveFormat: LiveFormat.values.byName(data['liveFormat']! as String),
    epgUrl: data['epgUrl'] as String?,
  );
  if (existingId == null) {
    final identity = playlistIdentity(remote);
    final survivor = identity == null ? null : _survivorOf(db, identity);
    if (survivor != null) {
      if (survivor.syncId!.compareTo(item.itemId) < 0) {
        // The local copy wins: delete the remote one for everybody instead.
        db.markDirty(
          item.kind,
          item.itemId,
          deleted: true,
          at: _after(item.updatedAt),
        );
        return null;
      }
      db.rebindPlaylist(survivor.id!, item.itemId);
      existingId = survivor.id;
    }
  }
  final old = existingId == null
      ? null
      : db.playlists().firstWhere((p) => p.id == existingId);
  final playlist = remote.copyWith(
    id: existingId,
    refreshedAt: old?.refreshedAt,
  );
  final id = db.savePlaylist(playlist);
  final password = data['password'] as String?;
  final oldPassword = existingId == null ? null : await passwords.read(id);
  if (playlist.type != PlaylistType.xtream) {
    await passwords.delete(id);
  } else if (password != null) {
    await passwords.write(id, password);
  }
  db.markClean(item.kind, item.itemId, item.updatedAt);
  final mustResync =
      old == null ||
      old.sourceChanged(playlist) ||
      (playlist.type == PlaylistType.xtream && password != oldPassword);
  if (!mustResync) return null;
  if (old != null) db.clearCatalog(id);
  return (
    playlist: db.playlists().firstWhere((p) => p.id == id),
    created: old == null,
  );
}

/// A time later than both now and [t], for a deletion that must beat [t].
DateTime _after(DateTime t) {
  final now = DateTime.now().toUtc();
  final later = t.add(const Duration(milliseconds: 1));
  return later.isAfter(now) ? later : now;
}

/// Merges playlists that already share a source (see [playlistIdentity]): the
/// smallest `sync_id` keeps its place and receives whatever favorites,
/// progress and preferences the others have that it lacks; the others are
/// deleted, with their passwords, and their ids tombstoned so that other
/// devices drop them too.
Future<void> mergeDuplicatePlaylists(
  CatalogDb db,
  PasswordStore passwords,
) async {
  final groups = <String, List<Playlist>>{};
  for (final p in db.playlists()) {
    final identity = playlistIdentity(p);
    if (identity != null && p.syncId != null) {
      groups.putIfAbsent(identity, () => []).add(p);
    }
  }
  for (final group in groups.values) {
    if (group.length < 2) continue;
    group.sort((x, y) => x.syncId!.compareTo(y.syncId!));
    for (final loser in group.skip(1)) {
      db.moveLibraryData(loser.id!, group.first.id!);
      db.deletePlaylist(loser.id!, tombstoneItems: true);
      await passwords.delete(loser.id!);
    }
  }
}

/// Favorite element for [state]; one that is no longer local exports as a
/// deletion.
SyncItem exportFavoriteItem(
  CatalogDb db,
  SyncState state, {
  SyncLocalIndex? index,
}) {
  final favorite = state.deleted
      ? null
      : (index ?? SyncLocalIndex(db)).favorites[state.itemId];
  if (favorite == null) return _gone(state);
  return _present(state, {
    'playlist': favorite.playlistSyncId,
    'kind': favorite.kind.name,
    'key': favorite.key,
    'addedAt': favorite.addedAt.microsecondsSinceEpoch,
  });
}

/// Adds or removes the local favorite described by [item]. A favorite of a
/// playlist this device does not have is ignored.
void applyFavoriteItem(CatalogDb db, SyncItem item, {SyncLocalIndex? index}) {
  final data = item.data;
  if (item.deleted || data == null) {
    final local = (index ?? SyncLocalIndex(db)).favorites[item.itemId];
    if (local != null) {
      db.setFavorite(local.playlistId, local.kind, local.key, false);
    }
  } else {
    final playlistId = db.playlistIdForSyncId(data['playlist']! as String);
    if (playlistId == null) return;
    db.setFavorite(
      playlistId,
      MediaKind.values.byName(data['kind']! as String),
      data['key']! as String,
      true,
      addedAt: _fromMicros(data['addedAt']! as int),
    );
  }
  db.markClean(item.kind, item.itemId, item.updatedAt, deleted: item.deleted);
}

/// Progress element for [state].
SyncItem exportProgressItem(
  CatalogDb db,
  SyncState state, {
  SyncLocalIndex? index,
}) {
  final local = state.deleted
      ? null
      : (index ?? SyncLocalIndex(db)).progress[state.itemId];
  if (local == null) return _gone(state);
  final p = local.progress;
  return _present(state, {
    'playlist': local.playlistSyncId,
    'kind': p.target.kind.name,
    'key': p.target.key,
    'title': p.target.title,
    'iconUrl': p.target.iconUrl,
    'xtreamType': p.target.xtreamType?.name,
    'xtreamId': p.target.xtreamId,
    'extension': p.target.extension,
    'url': p.target.url,
    'seriesKey': p.target.seriesKey,
    'positionMs': p.position.inMilliseconds,
    'durationMs': p.duration.inMilliseconds,
    'updatedAt': p.updatedAt.microsecondsSinceEpoch,
  });
}

/// Saves or clears the local progress described by [item].
void applyProgressItem(CatalogDb db, SyncItem item, {SyncLocalIndex? index}) {
  final data = item.data;
  if (item.deleted || data == null) {
    final local = (index ?? SyncLocalIndex(db)).progress[item.itemId];
    if (local != null) {
      db.clearProgress(
        local.playlistId,
        local.progress.target.kind,
        local.progress.target.key,
      );
    }
  } else {
    final playlistId = db.playlistIdForSyncId(data['playlist']! as String);
    if (playlistId == null) return;
    final type = data['xtreamType'] as String?;
    db.saveProgress(
      playlistId,
      PlayTarget(
        kind: MediaKind.values.byName(data['kind']! as String),
        key: data['key']! as String,
        title: data['title']! as String,
        iconUrl: data['iconUrl'] as String?,
        xtreamType: type == null ? null : XtreamStreamType.values.byName(type),
        xtreamId: data['xtreamId'] as int?,
        extension: data['extension'] as String?,
        url: data['url'] as String?,
        seriesKey: data['seriesKey'] as String?,
      ),
      Duration(milliseconds: data['positionMs']! as int),
      Duration(milliseconds: data['durationMs']! as int),
      at: _fromMicros(data['updatedAt']! as int),
    );
  }
  db.markClean(item.kind, item.itemId, item.updatedAt, deleted: item.deleted);
}

/// Preference element for [state].
SyncItem exportPrefItem(
  CatalogDb db,
  SyncState state, {
  SyncLocalIndex? index,
}) {
  final local = state.deleted
      ? null
      : (index ?? SyncLocalIndex(db)).prefs[state.itemId];
  if (local == null) return _gone(state);
  return _present(state, {
    'playlist': local.playlistSyncId,
    'scope': local.scope,
    'value': local.value,
  });
}

/// Saves or removes the local preference described by [item].
void applyPrefItem(CatalogDb db, SyncItem item, {SyncLocalIndex? index}) {
  final data = item.data;
  if (item.deleted || data == null) {
    final local = (index ?? SyncLocalIndex(db)).prefs[item.itemId];
    if (local != null) db.deletePref(local.playlistId, local.scope);
  } else {
    final playlistSyncId = data['playlist'] as String?;
    final playlistId = playlistSyncId == null
        ? 0
        : db.playlistIdForSyncId(playlistSyncId);
    if (playlistId == null) return;
    db.savePref(
      playlistId,
      data['scope']! as String,
      Map<String, Object?>.from(data['value']! as Map),
    );
  }
  db.markClean(item.kind, item.itemId, item.updatedAt, deleted: item.deleted);
}

/// Settings element for [state], without the fields that never leave the
/// device (parental control and last playlist).
SyncItem exportSettingsItem(CatalogDb db, SyncState state) => _present(
  state,
  jsonDecode(exportSettings(AppSettings.fromJson(db.loadSettings())))
      as Map<String, Object?>,
);

/// Merges the remote settings in [item] into the local ones; parental data,
/// the last playlist and (while locked) "hide adult content" keep their local
/// values. A malformed element is ignored.
void applySettingsItem(CatalogDb db, SyncItem item) {
  final data = item.data;
  if (data == null) return;
  final AppSettings merged;
  try {
    merged = importSettings(
      jsonEncode(data),
      current: AppSettings.fromJson(db.loadSettings()),
    );
  } on FormatException {
    return;
  }
  db.saveSettings(merged.toJson());
  db.markClean(item.kind, item.itemId, item.updatedAt);
}

/// Element for [state] of any kind.
Future<SyncItem> exportItem(
  CatalogDb db,
  PasswordStore passwords,
  SyncState state, {
  SyncLocalIndex? index,
}) async => switch (state.kind) {
  playlistKind => await exportPlaylistItem(db, passwords, state),
  favoriteKind => exportFavoriteItem(db, state, index: index),
  progressKind => exportProgressItem(db, state, index: index),
  prefKind => exportPrefItem(db, state, index: index),
  settingsKind => exportSettingsItem(db, state),
  _ => throw ArgumentError('Unknown sync kind: ${state.kind}'),
};

/// Applies [item] of any kind; returns the playlist to download, if any.
/// Elements of unknown kinds (from a newer app) are ignored.
Future<PlaylistToSync?> applyItem(
  CatalogDb db,
  PasswordStore passwords,
  SyncItem item, {
  SyncLocalIndex? index,
}) async {
  switch (item.kind) {
    case playlistKind:
      return applyPlaylistItem(db, passwords, item);
    case favoriteKind:
      applyFavoriteItem(db, item, index: index);
    case progressKind:
      applyProgressItem(db, item, index: index);
    case prefKind:
      applyPrefItem(db, item, index: index);
    case settingsKind:
      applySettingsItem(db, item);
  }
  return null;
}
