import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../epg/programme.dart';
import '../player/play_target.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/settings_transfer.dart';
import '../sync/sync_ids.dart';
import '../xtream/xtream_urls.dart';
import 'catalog_models.dart';
import 'sorting.dart';

const _schemaVersion = 5;

/// How many recently played items are kept per playlist and kind.
const maxRecents = 50;

const _schema = '''
CREATE TABLE IF NOT EXISTS playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  server_url TEXT,
  username TEXT,
  source TEXT,
  user_agent TEXT,
  live_format TEXT NOT NULL,
  refreshed_at INTEGER,
  epg_url TEXT,
  sync_id TEXT
);
CREATE TABLE IF NOT EXISTS categories (
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, kind, id)
);
CREATE TABLE IF NOT EXISTS channels (
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  kind TEXT NOT NULL,
  category_id TEXT NOT NULL,
  name TEXT NOT NULL,
  icon_url TEXT,
  epg_id TEXT,
  stream_id INTEGER,
  url TEXT,
  position INTEGER NOT NULL,
  extension TEXT,
  rating REAL,
  PRIMARY KEY (playlist_id, key)
);
CREATE INDEX IF NOT EXISTS channels_by_category
  ON channels (playlist_id, category_id, position);
CREATE TABLE IF NOT EXISTS favorites (
  playlist_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  key TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, kind, key)
);
CREATE TABLE IF NOT EXISTS recents (
  playlist_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  key TEXT NOT NULL,
  watched_at INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, kind, key)
);
CREATE TABLE IF NOT EXISTS prefs (
  playlist_id INTEGER NOT NULL,
  scope TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (playlist_id, scope)
);
CREATE TABLE IF NOT EXISTS progress (
  playlist_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  key TEXT NOT NULL,
  title TEXT NOT NULL,
  icon_url TEXT,
  xtream_type TEXT,
  xtream_id INTEGER,
  extension TEXT,
  url TEXT,
  series_key TEXT,
  position_ms INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, kind, key)
);
CREATE TABLE IF NOT EXISTS epg (
  playlist_id INTEGER NOT NULL,
  channel_id TEXT NOT NULL,
  start_ms INTEGER NOT NULL,
  stop_ms INTEGER NOT NULL,
  title TEXT NOT NULL,
  description TEXT
);
CREATE INDEX IF NOT EXISTS epg_by_channel
  ON epg (playlist_id, channel_id, start_ms);
CREATE TABLE IF NOT EXISTS sync_state (
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  dirty INTEGER NOT NULL,
  deleted INTEGER NOT NULL,
  PRIMARY KEY (kind, item_id)
);
''';

/// Local SQLite cache of playlists and their catalogs.
class CatalogDb {
  CatalogDb._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.createFunction(
      functionName: 'fold',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      function: (args) => foldText('${args[0] ?? ''}'),
    );
    _db.execute(_schema);
    _migrate();
    _db.execute('PRAGMA user_version = $_schemaVersion');
  }

  /// Brings a database created by an older version up to [_schemaVersion].
  ///
  /// Tables missing in old files were just created by [_schema]; only columns
  /// added later to existing tables need an `ALTER TABLE`, and only when absent.
  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version >= 5) return;
    if (version < 3) {
      final columns = {
        for (final row in _db.select('PRAGMA table_info(channels)'))
          row['name'] as String,
      };
      if (!columns.contains('extension')) {
        _db.execute('ALTER TABLE channels ADD COLUMN extension TEXT');
      }
      if (!columns.contains('rating')) {
        _db.execute('ALTER TABLE channels ADD COLUMN rating REAL');
      }
    }
    final playlistColumns = {
      for (final row in _db.select('PRAGMA table_info(playlists)'))
        row['name'] as String,
    };
    if (!playlistColumns.contains('epg_url')) {
      _db.execute('ALTER TABLE playlists ADD COLUMN epg_url TEXT');
    }
    if (!playlistColumns.contains('sync_id')) {
      _db.execute('ALTER TABLE playlists ADD COLUMN sync_id TEXT');
    }
    for (final row in _db.select(
      'SELECT id FROM playlists WHERE sync_id IS NULL',
    )) {
      _db.execute('UPDATE playlists SET sync_id = ? WHERE id = ?', [
        newSyncId(),
        row['id'],
      ]);
    }
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS playlists_by_sync_id '
      'ON playlists (sync_id)',
    );
  }

  /// Opens (or creates) the database file at [path].
  static CatalogDb open(String path) => CatalogDb._(sqlite3.open(path));

  /// Opens a throwaway in-memory database, for tests.
  static CatalogDb inMemory() => CatalogDb._(sqlite3.openInMemory());

  final Database _db;
  final _refreshes = StreamController<int>.broadcast();

  /// Ids of playlists whose catalog refresh just finished, well or not (each
  /// [saveSyncError]), so screens showing them can read them again.
  Stream<int> get refreshes => _refreshes.stream;

  /// Closes the database.
  void close() {
    _refreshes.close();
    _db.close();
  }

  /// Inserts [playlist] when it has no id, otherwise updates it.
  ///
  /// An update never touches `refreshed_at`, which only [replaceCatalog] and
  /// [clearCatalog] change. Returns the playlist id.
  int savePlaylist(Playlist playlist) {
    final values = [
      playlist.name,
      playlist.type.name,
      playlist.serverUrl,
      playlist.username,
      playlist.source,
      playlist.userAgent,
      playlist.liveFormat.name,
      playlist.epgUrl,
    ];
    final id = playlist.id;
    if (id == null) {
      final syncId = playlist.syncId ?? newSyncId();
      _db.execute(
        'INSERT INTO playlists (name, type, server_url, username, source, '
        'user_agent, live_format, epg_url, refreshed_at, sync_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, playlist.refreshedAt?.millisecondsSinceEpoch, syncId],
      );
      markDirty(playlistKind, syncId);
      return _db.lastInsertRowId;
    }
    _db.execute(
      'UPDATE playlists SET name = ?, type = ?, server_url = ?, username = ?, '
      'source = ?, user_agent = ?, live_format = ?, epg_url = ? WHERE id = ?',
      [...values, id],
    );
    final syncId = syncIdOfPlaylist(id);
    if (syncId != null) markDirty(playlistKind, syncId);
    return id;
  }

  /// All playlists, sorted by name.
  List<Playlist> playlists() {
    final rows = _db.select(
      'SELECT * FROM playlists ORDER BY name COLLATE NOCASE',
    );
    return [
      for (final row in rows)
        Playlist(
          id: row['id'] as int,
          name: row['name'] as String,
          type: PlaylistType.values.byName(row['type'] as String),
          serverUrl: row['server_url'] as String?,
          username: row['username'] as String?,
          source: row['source'] as String?,
          userAgent: row['user_agent'] as String?,
          liveFormat: LiveFormat.values.byName(row['live_format'] as String),
          epgUrl: row['epg_url'] as String?,
          syncId: row['sync_id'] as String?,
          refreshedAt: row['refreshed_at'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  row['refreshed_at'] as int,
                  isUtc: true,
                ),
        ),
    ];
  }

  /// Removes a playlist's catalog and marks it as never refreshed, used when
  /// its source changes and the old channels no longer apply.
  void clearCatalog(int playlistId) {
    _db.execute('DELETE FROM channels WHERE playlist_id = ?', [playlistId]);
    _db.execute('DELETE FROM categories WHERE playlist_id = ?', [playlistId]);
    _db.execute('UPDATE playlists SET refreshed_at = NULL WHERE id = ?', [
      playlistId,
    ]);
  }

  /// Deletes a playlist and, by cascade, its catalog.
  ///
  /// For sync only the playlist gets a deletion mark; its favorites, progress
  /// and preferences are forgotten along with it, and other devices drop them
  /// when they drop the playlist. With [tombstoneItems] the ones already known
  /// to the server are marked deleted too, so they do not linger there.
  void deletePlaylist(int id, {bool tombstoneItems = false}) {
    final syncId = syncIdOfPlaylist(id);
    // Library tables have no foreign key (prefs use id 0 for global values).
    for (final table in ['favorites', 'recents', 'prefs', 'progress', 'epg']) {
      _db.execute('DELETE FROM $table WHERE playlist_id = ?', [id]);
    }
    _db.execute('DELETE FROM playlists WHERE id = ?', [id]);
    if (syncId == null) return;
    if (tombstoneItems) {
      _tombstoneItemsOf(syncId);
    } else {
      _db.execute(
        'DELETE FROM sync_state WHERE kind != ? AND substr(item_id, 1, ?) = ?',
        [playlistKind, syncId.length + 1, '$syncId:'],
      );
    }
    markDirty(playlistKind, syncId, deleted: true);
  }

  /// Marks every favorite, progress and preference id under [syncId] that is
  /// not deleted yet as a pending deletion.
  void _tombstoneItemsOf(String syncId) {
    _db.execute(
      'UPDATE sync_state SET deleted = 1, dirty = 1, updated_at = ? '
      'WHERE kind != ? AND deleted = 0 AND substr(item_id, 1, ?) = ?',
      [
        DateTime.now().microsecondsSinceEpoch,
        playlistKind,
        syncId.length + 1,
        '$syncId:',
      ],
    );
  }

  /// Gives the playlist [id] the sync id [newSyncId], keeping its row, catalog
  /// and library data. The old sync id and the ids derived from it become
  /// deletions, and the favorites, progress and preferences are marked changed
  /// so they upload under the new one (stamped with their own times, so newer
  /// remote versions still win).
  void rebindPlaylist(int id, String newSyncId) {
    final oldSyncId = syncIdOfPlaylist(id);
    _db.execute('UPDATE playlists SET sync_id = ? WHERE id = ?', [
      newSyncId,
      id,
    ]);
    if (oldSyncId != null) {
      _tombstoneItemsOf(oldSyncId);
      markDirty(playlistKind, oldSyncId, deleted: true);
    }
    final ids = itemIds;
    if (ids == null) return;
    for (final f in allFavorites().where((f) => f.playlistId == id)) {
      markDirty(
        favoriteKind,
        ids.favorite(newSyncId, f.kind, f.key),
        at: f.addedAt,
      );
    }
    for (final p in allProgress().where((p) => p.playlistId == id)) {
      final target = p.progress.target;
      markDirty(
        progressKind,
        ids.progress(newSyncId, target.kind, target.key),
        at: p.progress.updatedAt,
      );
    }
    for (final p in allPrefs().where((p) => p.playlistId == id)) {
      markDirty(prefKind, ids.pref(newSyncId, p.scope));
    }
  }

  /// Copies the favorites, recents, progress and preferences of playlist
  /// [fromId] to [toId] where [toId] has nothing for that key (it wins
  /// conflicts). Leaves [fromId] untouched.
  void moveLibraryData(int fromId, int toId) {
    for (final f in allFavorites().where((f) => f.playlistId == fromId)) {
      setFavorite(toId, f.kind, f.key, true, addedAt: f.addedAt);
    }
    for (final p in allProgress().where((p) => p.playlistId == fromId)) {
      final target = p.progress.target;
      if (progress(toId, target.kind, target.key) != null) continue;
      saveProgress(
        toId,
        target,
        p.progress.position,
        p.progress.duration,
        at: p.progress.updatedAt,
      );
    }
    for (final p in allPrefs().where((p) => p.playlistId == fromId)) {
      if (_pref(toId, p.scope) == null) savePref(toId, p.scope, p.value);
    }
    _db.execute(
      'INSERT OR IGNORE INTO recents (playlist_id, kind, key, watched_at) '
      'SELECT ?, kind, key, watched_at FROM recents WHERE playlist_id = ?',
      [toId, fromId],
    );
  }

  /// Deletes every playlist with its catalog, favorites, recents, progress and
  /// preferences, the global synced preferences and all sync bookkeeping,
  /// without leaving anything to upload. Settings are kept. Used to discard
  /// local data when a different account signs in.
  void deleteLocalLibrary() {
    _quiet++;
    try {
      for (final playlist in playlists()) {
        deletePlaylist(playlist.id!);
      }
    } finally {
      _quiet--;
    }
    _db.execute(
      "DELETE FROM prefs WHERE playlist_id = 0 AND "
      "(scope LIKE 'channels/%' OR scope LIKE 'categories/%')",
    );
    _db.execute('DELETE FROM sync_state');
  }

  /// Replaces the whole catalog of [playlistId] atomically and records
  /// [refreshedAt]. List order is kept as the provider order; duplicate
  /// channel keys keep their first occurrence.
  void replaceCatalog(
    int playlistId,
    List<Category> categories,
    List<Channel> channels,
    DateTime refreshedAt,
  ) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM channels WHERE playlist_id = ?', [playlistId]);
      _db.execute('DELETE FROM categories WHERE playlist_id = ?', [playlistId]);

      final insertCategory = _db.prepare(
        'INSERT OR IGNORE INTO categories (playlist_id, kind, id, name, position) '
        'VALUES (?, ?, ?, ?, ?)',
      );
      for (var i = 0; i < categories.length; i++) {
        final category = categories[i];
        insertCategory.execute([
          playlistId,
          category.kind.name,
          category.id,
          category.name,
          i,
        ]);
      }
      insertCategory.close();

      final insertChannel = _db.prepare(
        'INSERT OR IGNORE INTO channels (playlist_id, key, kind, category_id, '
        'name, icon_url, epg_id, stream_id, url, position, extension, rating) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      for (var i = 0; i < channels.length; i++) {
        final c = channels[i];
        insertChannel.execute([
          playlistId,
          c.key,
          c.kind.name,
          c.categoryId,
          c.name,
          c.iconUrl,
          c.epgId,
          c.streamId,
          c.url,
          i,
          c.extension,
          c.rating,
        ]);
      }
      insertChannel.close();

      _db.execute('UPDATE playlists SET refreshed_at = ? WHERE id = ?', [
        refreshedAt.millisecondsSinceEpoch,
        playlistId,
      ]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Categories of [kind] in provider order.
  List<Category> categories(int playlistId, MediaKind kind) {
    final rows = _db.select(
      'SELECT id, name FROM categories WHERE playlist_id = ? AND kind = ? '
      'ORDER BY position',
      [playlistId, kind.name],
    );
    return [
      for (final row in rows)
        Category(
          id: row['id'] as String,
          name: row['name'] as String,
          kind: kind,
        ),
    ];
  }

  /// Channels of a category in provider order.
  List<Channel> channels(int playlistId, String categoryId) {
    final rows = _db.select(
      'SELECT * FROM channels WHERE playlist_id = ? AND category_id = ? '
      'ORDER BY position',
      [playlistId, categoryId],
    );
    return rows.map(_channelFromRow).toList();
  }

  static Channel _channelFromRow(Row row) => Channel(
    key: row['key'] as String,
    name: row['name'] as String,
    categoryId: row['category_id'] as String,
    kind: MediaKind.values.byName(row['kind'] as String),
    iconUrl: row['icon_url'] as String?,
    epgId: row['epg_id'] as String?,
    streamId: row['stream_id'] as int?,
    url: row['url'] as String?,
    extension: row['extension'] as String?,
    rating: (row['rating'] as num?)?.toDouble(),
  );

  /// Keys of the playlist's favorites of [kind].
  Set<String> favoriteKeys(int playlistId, MediaKind kind) {
    final rows = _db.select(
      'SELECT key FROM favorites WHERE playlist_id = ? AND kind = ?',
      [playlistId, kind.name],
    );
    return {for (final row in rows) row['key'] as String};
  }

  /// Adds or removes a favorite. Favorites are kept by stable key, so they
  /// survive catalog refreshes.
  ///
  /// [addedAt] (default now) sets the position among favorites.
  void setFavorite(
    int playlistId,
    MediaKind kind,
    String key,
    bool favorite, {
    DateTime? addedAt,
  }) {
    if (favorite) {
      _db.execute(
        'INSERT OR IGNORE INTO favorites (playlist_id, kind, key, added_at) '
        'VALUES (?, ?, ?, ?)',
        [
          playlistId,
          kind.name,
          key,
          (addedAt ?? DateTime.now()).microsecondsSinceEpoch,
        ],
      );
    } else {
      _db.execute(
        'DELETE FROM favorites WHERE playlist_id = ? AND kind = ? AND key = ?',
        [playlistId, kind.name, key],
      );
    }
    if (_db.updatedRows == 0) return;
    final syncId = syncIdOfPlaylist(playlistId);
    final ids = itemIds;
    if (syncId == null || ids == null) return;
    markDirty(
      favoriteKind,
      ids.favorite(syncId, kind, key),
      deleted: !favorite,
    );
  }

  /// Favorites present in the current catalog, in the order they were added.
  List<Channel> favoriteChannels(int playlistId, MediaKind kind) {
    final rows = _db.select(
      'SELECT c.* FROM favorites f JOIN channels c '
      'ON c.playlist_id = f.playlist_id AND c.key = f.key AND c.kind = f.kind '
      'WHERE f.playlist_id = ? AND f.kind = ? ORDER BY f.added_at, f.rowid',
      [playlistId, kind.name],
    );
    return rows.map(_channelFromRow).toList();
  }

  /// Records that [key] was just played, keeping the [maxRecents] newest.
  void addRecent(int playlistId, MediaKind kind, String key, {DateTime? at}) {
    final time = (at ?? DateTime.now()).microsecondsSinceEpoch;
    _db.execute(
      'INSERT INTO recents (playlist_id, kind, key, watched_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (playlist_id, kind, key) DO UPDATE SET watched_at = excluded.watched_at',
      [playlistId, kind.name, key, time],
    );
    _db.execute(
      'DELETE FROM recents WHERE playlist_id = ? AND kind = ? AND key NOT IN '
      '(SELECT key FROM recents WHERE playlist_id = ? AND kind = ? '
      'ORDER BY watched_at DESC LIMIT $maxRecents)',
      [playlistId, kind.name, playlistId, kind.name],
    );
  }

  /// Recently played items present in the catalog, newest first.
  List<Channel> recentChannels(int playlistId, MediaKind kind) {
    final rows = _db.select(
      'SELECT c.* FROM recents r JOIN channels c '
      'ON c.playlist_id = r.playlist_id AND c.key = r.key AND c.kind = r.kind '
      'WHERE r.playlist_id = ? AND r.kind = ? ORDER BY r.watched_at DESC',
      [playlistId, kind.name],
    );
    return rows.map(_channelFromRow).toList();
  }

  /// Saves where [target] was left. The target's own data is stored with it, so
  /// the entry survives the item leaving the catalog. [at] defaults to now.
  void saveProgress(
    int playlistId,
    PlayTarget target,
    Duration position,
    Duration duration, {
    DateTime? at,
  }) {
    final time = at ?? DateTime.now();
    _db.execute(
      'INSERT OR REPLACE INTO progress (playlist_id, kind, key, title, icon_url, '
      'xtream_type, xtream_id, extension, url, series_key, position_ms, '
      'duration_ms, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        playlistId,
        target.kind.name,
        target.key,
        target.title,
        target.iconUrl,
        target.xtreamType?.name,
        target.xtreamId,
        target.extension,
        target.url,
        target.seriesKey,
        position.inMilliseconds,
        duration.inMilliseconds,
        time.microsecondsSinceEpoch,
      ],
    );
    final syncId = syncIdOfPlaylist(playlistId);
    final ids = itemIds;
    if (syncId == null || ids == null) return;
    markDirty(
      progressKind,
      ids.progress(syncId, target.kind, target.key),
      at: time,
    );
  }

  /// The saved progress of one item, if any.
  Progress? progress(int playlistId, MediaKind kind, String key) {
    final rows = _db.select(
      'SELECT * FROM progress WHERE playlist_id = ? AND kind = ? AND key = ?',
      [playlistId, kind.name, key],
    );
    return rows.isEmpty ? null : _progressFromRow(rows.first);
  }

  /// Id of the category of the catalog item [key], or `null` when the
  /// catalog has no such item (it left the catalog).
  String? categoryOfItem(int playlistId, MediaKind kind, String key) {
    final rows = _db.select(
      'SELECT category_id FROM channels '
      'WHERE playlist_id = ? AND kind = ? AND key = ?',
      [playlistId, kind.name, key],
    );
    return rows.isEmpty ? null : rows.first['category_id'] as String;
  }

  /// Unfinished items of [kind] (episodes included for series), newest first.
  List<Progress> continueWatching(
    int playlistId,
    MediaKind kind, {
    int limit = 30,
  }) {
    final rows = _db.select(
      'SELECT * FROM progress WHERE playlist_id = ? AND kind = ? '
      'ORDER BY updated_at DESC, rowid DESC',
      [playlistId, kind.name],
    );
    return rows
        .map(_progressFromRow)
        .where((p) => p.isUnfinished)
        .take(limit)
        .toList();
  }

  /// Forgets every recently played item of every playlist.
  void clearRecents() => _db.execute('DELETE FROM recents');

  /// Forgets every saved playback position of every playlist.
  void clearAllProgress() {
    final all = allProgress();
    _db.execute('DELETE FROM progress');
    for (final (:playlistId, :progress) in all) {
      _markProgressDeleted(
        playlistId,
        progress.target.kind,
        progress.target.key,
      );
    }
  }

  /// Forgets the saved progress of one item.
  void clearProgress(int playlistId, MediaKind kind, String key) {
    _db.execute(
      'DELETE FROM progress WHERE playlist_id = ? AND kind = ? AND key = ?',
      [playlistId, kind.name, key],
    );
    if (_db.updatedRows > 0) _markProgressDeleted(playlistId, kind, key);
  }

  void _markProgressDeleted(int playlistId, MediaKind kind, String key) {
    final syncId = syncIdOfPlaylist(playlistId);
    final ids = itemIds;
    if (syncId == null || ids == null) return;
    markDirty(progressKind, ids.progress(syncId, kind, key), deleted: true);
  }

  static Progress _progressFromRow(Row row) {
    final type = row['xtream_type'] as String?;
    return Progress(
      target: PlayTarget(
        kind: MediaKind.values.byName(row['kind'] as String),
        key: row['key'] as String,
        title: row['title'] as String,
        iconUrl: row['icon_url'] as String?,
        xtreamType: type == null ? null : XtreamStreamType.values.byName(type),
        xtreamId: row['xtream_id'] as int?,
        extension: row['extension'] as String?,
        url: row['url'] as String?,
        seriesKey: row['series_key'] as String?,
      ),
      position: Duration(milliseconds: row['position_ms'] as int),
      duration: Duration(milliseconds: row['duration_ms'] as int),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
    );
  }

  /// Items of any kind whose name contains [query], ignoring case and accents.
  List<Channel> searchChannels(
    int playlistId,
    String query, {
    int limit = 200,
  }) {
    final folded = foldText(query.trim());
    if (folded.isEmpty) return const [];
    // Make LIKE wildcards in the query literal; backslash is the escape char.
    final escaped = folded
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = _db.select(
      r"SELECT * FROM channels WHERE playlist_id = ? AND fold(name) LIKE ? ESCAPE '\' "
      'ORDER BY kind, position LIMIT ?',
      [playlistId, '%$escaped%', limit],
    );
    return rows.map(_channelFromRow).toList();
  }

  String? _pref(int playlistId, String scope) {
    final rows = _db.select(
      'SELECT value FROM prefs WHERE playlist_id = ? AND scope = ?',
      [playlistId, scope],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void _savePref(int playlistId, String scope, Map<String, Object?> value) {
    final encoded = jsonEncode(value);
    final changed = _pref(playlistId, scope) != encoded;
    _db.execute(
      'INSERT OR REPLACE INTO prefs (playlist_id, scope, value) VALUES (?, ?, ?)',
      [playlistId, scope, encoded],
    );
    if (changed) _markPrefDirty(playlistId, scope);
  }

  /// Marks a synced preference as changed (or removed); ignores local-only
  /// scopes and preferences of playlists that do not exist.
  void _markPrefDirty(int playlistId, String scope, {bool deleted = false}) {
    final ids = itemIds;
    if (ids == null || !isSyncedPrefScope(scope)) return;
    final syncId = playlistId == 0 ? null : syncIdOfPlaylist(playlistId);
    if (playlistId != 0 && syncId == null) return;
    markDirty(prefKind, ids.pref(syncId, scope), deleted: deleted);
  }

  static Map<String, Object?> _decode(String? value) {
    if (value == null) return const {};
    final json = jsonDecode(value);
    return json is Map<String, Object?> ? json : const {};
  }

  static String _channelScope(MediaKind kind, String categoryId) =>
      'channels/${kind.name}/$categoryId';

  /// Global default channel sort, inherited by categories without their own.
  ChannelSort defaultChannelSort() =>
      ChannelSort.fromJson(_decode(_pref(0, 'channels/default')));

  /// Saves the global default channel sort.
  void saveDefaultChannelSort(ChannelSort sort) =>
      _savePref(0, 'channels/default', sort.toJson());

  /// The category's own sort, or the global default when it has none.
  ChannelSort channelSort(int playlistId, MediaKind kind, String categoryId) {
    final own = _pref(playlistId, _channelScope(kind, categoryId));
    return own == null
        ? defaultChannelSort()
        : ChannelSort.fromJson(_decode(own));
  }

  /// Whether the category has its own sort instead of the default.
  bool hasOwnChannelSort(int playlistId, MediaKind kind, String categoryId) =>
      _pref(playlistId, _channelScope(kind, categoryId)) != null;

  /// Saves the category's own sort.
  void saveChannelSort(
    int playlistId,
    MediaKind kind,
    String categoryId,
    ChannelSort sort,
  ) => _savePref(playlistId, _channelScope(kind, categoryId), sort.toJson());

  /// Removes the category's own sort so it inherits the default again.
  void deleteChannelSort(int playlistId, MediaKind kind, String categoryId) =>
      deletePref(playlistId, _channelScope(kind, categoryId));

  /// Order and visibility of the playlist's categories of [kind].
  CategorySort categorySort(int playlistId, MediaKind kind) =>
      CategorySort.fromJson(
        _decode(_pref(playlistId, 'categories/${kind.name}')),
      );

  /// Saves the order and visibility of the playlist's categories of [kind].
  void saveCategorySort(int playlistId, MediaKind kind, CategorySort sort) =>
      _savePref(playlistId, 'categories/${kind.name}', sort.toJson());

  /// Whether the live view shows the guide grid instead of the channel list
  /// for this playlist (off by default).
  bool liveGuideGrid(int playlistId) =>
      _decode(_pref(playlistId, liveGuideGridScope))['on'] == true;

  /// Remembers the live view's guide toggle for this playlist.
  void saveLiveGuideGrid(int playlistId, bool on) =>
      _savePref(playlistId, liveGuideGridScope, {'on': on});

  /// Number of channels of [kind] in a playlist.
  int channelCount(int playlistId, MediaKind kind) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM channels WHERE playlist_id = ? AND kind = ?',
      [playlistId, kind.name],
    );
    return rows.first['n'] as int;
  }

  /// Replaces the whole programme guide of [playlistId] atomically and records
  /// [refreshedAt].
  void replaceEpg(
    int playlistId,
    List<Programme> programmes,
    DateTime refreshedAt,
  ) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM epg WHERE playlist_id = ?', [playlistId]);
      final insert = _db.prepare(
        'INSERT INTO epg (playlist_id, channel_id, start_ms, stop_ms, title, '
        'description) VALUES (?, ?, ?, ?, ?, ?)',
      );
      for (final p in programmes) {
        insert.execute([
          playlistId,
          p.channelId,
          p.start.millisecondsSinceEpoch,
          p.stop.millisecondsSinceEpoch,
          p.title,
          p.description,
        ]);
      }
      insert.close();
      _savePref(playlistId, 'epg/refreshed', {
        'at': refreshedAt.millisecondsSinceEpoch,
      });
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// When the guide of [playlistId] was last replaced, or `null` if never.
  DateTime? epgRefreshedAt(int playlistId) {
    final at = _decode(_pref(playlistId, 'epg/refreshed'))['at'];
    return at is int
        ? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)
        : null;
  }

  /// For each of [channelIds], the programme on air at [now] (`start <= now <
  /// stop`) and the next one to start after it; either may be `null`.
  Map<String, (Programme?, Programme?)> nowNext(
    int playlistId,
    Iterable<String> channelIds,
    DateTime now,
  ) {
    final ms = now.millisecondsSinceEpoch;
    final current = _db.prepare(
      'SELECT * FROM epg WHERE playlist_id = ? AND channel_id = ? '
      'AND start_ms <= ? AND stop_ms > ? ORDER BY start_ms DESC LIMIT 1',
    );
    final next = _db.prepare(
      'SELECT * FROM epg WHERE playlist_id = ? AND channel_id = ? '
      'AND start_ms > ? ORDER BY start_ms LIMIT 1',
    );
    try {
      return {
        for (final id in channelIds)
          id: (
            _firstProgramme(current.select([playlistId, id, ms, ms])),
            _firstProgramme(next.select([playlistId, id, ms])),
          ),
      };
    } finally {
      current.close();
      next.close();
    }
  }

  /// Programmes of [channelIds] overlapping `[from, to)`, grouped by channel in
  /// the order given and sorted by start.
  List<Programme> programmes(
    int playlistId,
    Iterable<String> channelIds,
    DateTime from,
    DateTime to,
  ) {
    final select = _db.prepare(
      'SELECT * FROM epg WHERE playlist_id = ? AND channel_id = ? '
      'AND start_ms < ? AND stop_ms > ? ORDER BY start_ms',
    );
    try {
      return [
        for (final id in channelIds)
          for (final row in select.select([
            playlistId,
            id,
            to.millisecondsSinceEpoch,
            from.millisecondsSinceEpoch,
          ]))
            _programmeFromRow(row),
      ];
    } finally {
      select.close();
    }
  }

  static Programme? _firstProgramme(ResultSet rows) =>
      rows.isEmpty ? null : _programmeFromRow(rows.first);

  static Programme _programmeFromRow(Row row) => Programme(
    channelId: row['channel_id'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(
      row['start_ms'] as int,
      isUtc: true,
    ),
    stop: DateTime.fromMillisecondsSinceEpoch(
      row['stop_ms'] as int,
      isUtc: true,
    ),
    title: row['title'] as String,
    description: row['description'] as String?,
  );

  /// Distinct non-empty EPG ids of the playlist's live channels.
  Set<String> liveEpgIds(int playlistId) {
    final rows = _db.select(
      "SELECT DISTINCT epg_id FROM channels WHERE playlist_id = ? AND kind = 'live' "
      "AND epg_id IS NOT NULL AND epg_id != ''",
      [playlistId],
    );
    return {for (final row in rows) row['epg_id'] as String};
  }

  /// Remembers the guide URL declared by the M3U header; `null` forgets it.
  void saveM3uTvgUrl(int playlistId, String? url) {
    if (url == null) {
      _db.execute('DELETE FROM prefs WHERE playlist_id = ? AND scope = ?', [
        playlistId,
        'epg/m3u-url',
      ]);
    } else {
      _savePref(playlistId, 'epg/m3u-url', {'url': url});
    }
  }

  /// Raw app settings JSON; empty when never saved or unreadable.
  Map<String, Object?> loadSettings() {
    try {
      return _decode(_pref(0, 'settings'));
    } on FormatException {
      return const {};
    }
  }

  /// Saves the raw app settings JSON.
  ///
  /// Marks the settings for sync only when a synced field changed (not when
  /// only parental data or the last playlist did).
  void saveSettings(Map<String, Object?> settings) {
    final before = exportSettings(AppSettings.fromJson(loadSettings()));
    _savePref(0, 'settings', settings);
    if (exportSettings(AppSettings.fromJson(settings)) != before) {
      markDirty(settingsKind, settingsItemId);
    }
  }

  /// Records why the last catalog refresh of [playlistId] failed, or clears it
  /// with `null`. Local only: never synced.
  void saveSyncError(int playlistId, String? message) {
    if (message == null) {
      _db.execute('DELETE FROM prefs WHERE playlist_id = ? AND scope = ?', [
        playlistId,
        'catalog/error',
      ]);
    } else {
      _savePref(playlistId, 'catalog/error', {'message': message});
    }
    _refreshes.add(playlistId);
  }

  /// The error saved by [saveSyncError] if the last refresh failed.
  String? syncError(int playlistId) {
    final message = _decode(_pref(playlistId, 'catalog/error'))['message'];
    return message is String ? message : null;
  }

  /// The guide URL saved by [saveM3uTvgUrl], if any.
  String? m3uTvgUrl(int playlistId) {
    final url = _decode(_pref(playlistId, 'epg/m3u-url'))['url'];
    return url is String ? url : null;
  }

  // --- Sync state -----------------------------------------------------------

  static DateTime _fromMicros(int micros) =>
      DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

  /// Derives the opaque `item_id`s of favorites, progress and preferences;
  /// set while a sync engine holds the data key. Without it those changes are
  /// not tracked (nothing to sync them to); the first sync of the next
  /// session uploads the whole library anyway.
  ItemIds? itemIds;

  /// Called with the `kind` of the element after every [markDirty] (except
  /// inside [quietly]); the account service uses it to schedule a sync.
  void Function(String kind)? onLocalChange;

  int _quiet = 0;

  /// Runs [action] without calling [onLocalChange] for the changes it makes.
  /// Used to apply remote elements, which are marked clean right after being
  /// written and so need no upload.
  Future<T> quietly<T>(Future<T> Function() action) async {
    _quiet++;
    try {
      return await action();
    } finally {
      _quiet--;
    }
  }

  /// Records that the element changed locally at [at] (default now), so the
  /// next sync uploads it; [deleted] marks a removal.
  void markDirty(
    String kind,
    String itemId, {
    bool deleted = false,
    DateTime? at,
  }) {
    _db.execute(
      'INSERT INTO sync_state (kind, item_id, updated_at, dirty, deleted) '
      'VALUES (?, ?, ?, 1, ?) ON CONFLICT (kind, item_id) DO UPDATE SET '
      'updated_at = excluded.updated_at, dirty = 1, deleted = excluded.deleted',
      [
        kind,
        itemId,
        (at ?? DateTime.now()).microsecondsSinceEpoch,
        deleted ? 1 : 0,
      ],
    );
    if (_quiet == 0) onLocalChange?.call(kind);
  }

  static SyncState _syncStateFromRow(Row row) => (
    kind: row['kind'] as String,
    itemId: row['item_id'] as String,
    updatedAt: _fromMicros(row['updated_at'] as int),
    dirty: row['dirty'] == 1,
    deleted: row['deleted'] == 1,
  );

  /// Elements changed locally and not uploaded yet.
  List<SyncState> dirtyItems() => _db
      .select('SELECT * FROM sync_state WHERE dirty = 1 ORDER BY rowid')
      .map(_syncStateFromRow)
      .toList();

  /// Records that the element is in step with the server at [updatedAt]
  /// (inserting it when new); [deleted] says the shared version is a removal.
  void markClean(
    String kind,
    String itemId,
    DateTime updatedAt, {
    bool deleted = false,
  }) {
    _db.execute(
      'INSERT INTO sync_state (kind, item_id, updated_at, dirty, deleted) '
      'VALUES (?, ?, ?, 0, ?) ON CONFLICT (kind, item_id) DO UPDATE SET '
      'updated_at = excluded.updated_at, dirty = 0, deleted = excluded.deleted',
      [kind, itemId, updatedAt.microsecondsSinceEpoch, deleted ? 1 : 0],
    );
  }

  /// What is known about one element, or `null` when never seen.
  SyncState? syncState(String kind, String itemId) {
    final rows = _db.select(
      'SELECT * FROM sync_state WHERE kind = ? AND item_id = ?',
      [kind, itemId],
    );
    return rows.isEmpty ? null : _syncStateFromRow(rows.first);
  }

  /// Makes every known element and each of [localItems] dirty, so the next
  /// sync uploads everything (first sync of an account). Elements not tracked
  /// yet get the epoch as time, so any remote version wins over them.
  void markAllDirty(Iterable<({String kind, String itemId})> localItems) {
    _db.execute('BEGIN');
    try {
      for (final (:kind, :itemId) in localItems) {
        _db.execute(
          'INSERT OR IGNORE INTO sync_state '
          '(kind, item_id, updated_at, dirty, deleted) VALUES (?, ?, 0, 1, 0)',
          [kind, itemId],
        );
      }
      _db.execute('UPDATE sync_state SET dirty = 1');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The `synced_at` of the newest remote element already pulled, if any.
  DateTime? syncCursor() {
    final at = _decode(_pref(0, 'sync/cursor'))['at'];
    return at is int ? _fromMicros(at) : null;
  }

  /// Saves the pull cursor; `null` forgets it.
  void saveSyncCursor(DateTime? cursor) {
    if (cursor == null) {
      _db.execute(
        "DELETE FROM prefs WHERE playlist_id = 0 AND scope = 'sync/cursor'",
      );
    } else {
      _savePref(0, 'sync/cursor', {'at': cursor.microsecondsSinceEpoch});
    }
  }

  /// Id of the account that last synced on this device, if any. Kept after
  /// signing out, to notice when a different account signs in.
  String? syncUserId() {
    final id = _decode(_pref(0, 'sync/user'))['id'];
    return id is String ? id : null;
  }

  /// Remembers the account that syncs on this device; `null` forgets it.
  void saveSyncUserId(String? id) {
    if (id == null) {
      _db.execute(
        "DELETE FROM prefs WHERE playlist_id = 0 AND scope = 'sync/user'",
      );
    } else {
      _savePref(0, 'sync/user', {'id': id});
    }
  }

  /// Whether this device syncs the settings and the per-list preferences (on
  /// by default). Local only: each device chooses for itself.
  bool syncSettingsEnabled() =>
      _decode(_pref(0, 'sync/settings'))['enabled'] != false;

  /// Turns settings sync on or off on this device. Turning it on asks the
  /// next sync to catch up ([syncSettingsCatchUp]), since what arrived while
  /// it was off was skipped.
  void saveSyncSettingsEnabled(bool enabled) {
    if (enabled == syncSettingsEnabled()) return;
    _savePref(0, 'sync/settings', {'enabled': enabled, 'catchUp': enabled});
  }

  /// Whether the next sync must download everything again, to apply the
  /// settings and preferences skipped while settings sync was off.
  bool syncSettingsCatchUp() =>
      _decode(_pref(0, 'sync/settings'))['catchUp'] == true;

  /// Records that the catch-up download of [syncSettingsCatchUp] happened.
  void finishSyncSettingsCatchUp() {
    if (!syncSettingsCatchUp()) return;
    _savePref(0, 'sync/settings', {
      'enabled': syncSettingsEnabled(),
      'catchUp': false,
    });
  }

  /// Whether the welcome screen was already completed on this device. Local
  /// only, like [acceptedTermsVersion].
  bool welcomeDone() => _decode(_pref(0, 'welcome/done'))['done'] == true;

  /// Records that the welcome screen was completed.
  void saveWelcomeDone() => _savePref(0, 'welcome/done', {'done': true});

  /// Version of the terms accepted on this device, 0 when never accepted.
  int acceptedTermsVersion() {
    final version = _decode(_pref(0, 'terms/accepted'))['version'];
    return version is int ? version : 0;
  }

  /// Records that the terms in [version] were accepted.
  void saveAcceptedTermsVersion(int version) =>
      _savePref(0, 'terms/accepted', {'version': version});

  /// Id of the playlist with [syncId], if it exists on this device.
  int? playlistIdForSyncId(String syncId) {
    final rows = _db.select('SELECT id FROM playlists WHERE sync_id = ?', [
      syncId,
    ]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// The sync id of playlist [playlistId], if it exists.
  String? syncIdOfPlaylist(int playlistId) {
    final rows = _db.select('SELECT sync_id FROM playlists WHERE id = ?', [
      playlistId,
    ]);
    return rows.isEmpty ? null : rows.first['sync_id'] as String?;
  }

  /// Every favorite of every playlist.
  List<({int playlistId, MediaKind kind, String key, DateTime addedAt})>
  allFavorites() => [
    for (final row in _db.select(
      'SELECT playlist_id, kind, key, added_at FROM favorites ORDER BY rowid',
    ))
      (
        playlistId: row['playlist_id'] as int,
        kind: MediaKind.values.byName(row['kind'] as String),
        key: row['key'] as String,
        addedAt: _fromMicros(row['added_at'] as int),
      ),
  ];

  /// Every saved progress of every playlist.
  List<({int playlistId, Progress progress})> allProgress() => [
    for (final row in _db.select('SELECT * FROM progress ORDER BY rowid'))
      (playlistId: row['playlist_id'] as int, progress: _progressFromRow(row)),
  ];

  /// Every synced preference (see [isSyncedPrefScope]) of every playlist, with
  /// its decoded JSON value.
  List<({int playlistId, String scope, Map<String, Object?> value})>
  allPrefs() => [
    for (final row in _db.select('SELECT * FROM prefs ORDER BY rowid'))
      if (isSyncedPrefScope(row['scope'] as String))
        (
          playlistId: row['playlist_id'] as int,
          scope: row['scope'] as String,
          value: _decode(row['value'] as String),
        ),
  ];

  /// Saves a preference value under [scope]; `playlistId` 0 is global.
  void savePref(int playlistId, String scope, Map<String, Object?> value) =>
      _savePref(playlistId, scope, value);

  /// Removes a preference.
  void deletePref(int playlistId, String scope) {
    _db.execute('DELETE FROM prefs WHERE playlist_id = ? AND scope = ?', [
      playlistId,
      scope,
    ]);
    if (_db.updatedRows > 0) _markPrefDirty(playlistId, scope, deleted: true);
  }
}

/// What is known locally about one synced element.
typedef SyncState = ({
  String kind,
  String itemId,
  DateTime updatedAt,
  bool dirty,
  bool deleted,
});
