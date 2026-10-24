import 'dart:convert';
import 'dart:math';

import '../catalog/catalog_db.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import 'sync_backend.dart';
import 'sync_crypto.dart';
import 'sync_ids.dart';
import 'sync_items.dart';

/// How far before the cursor each download starts. A row can become visible
/// on the server after a later one (slow transaction); re-reading a minute is
/// harmless because an element with the same `updatedAt` is ignored.
const syncOverlap = Duration(seconds: 60);

/// What a sealed payload is bound to: the element's identity, version and
/// kind of change. A payload moved to another row, or a row whose time or
/// deletion flag was altered, no longer opens.
List<int> _aadOf(
  String kind,
  String itemId,
  DateTime updatedAt,
  bool deleted,
) => utf8.encode(
  '$kind|$itemId|${updatedAt.millisecondsSinceEpoch}|${deleted ? 1 : 0}',
);

/// When [item] is applied: playlists first so their favorites find them, and
/// among those the live ones before the deletions, so a duplicate deleted by
/// another device can still be rebound to the playlist that replaced it.
int _applyOrder(SyncItem item) => item.kind != playlistKind
    ? 2
    : item.deleted
    ? 1
    : 0;

/// Whether elements of [kind] follow the device's "sync settings" switch
/// ([CatalogDb.syncSettingsEnabled]): the global settings and the per-list
/// preferences.
bool followsSettingsSwitch(String kind) =>
    kind == settingsKind || kind == prefKind;

/// What one [SyncEngine.syncNow] did.
class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.skipped = 0,
    this.settingsApplied = false,
    this.createdPlaylists = const [],
    this.changedPlaylists = const [],
  });

  /// Local changes uploaded.
  final int pushed;

  /// Remote elements downloaded.
  final int pulled;

  /// Remote elements that changed this device (the rest were older).
  final int applied;

  /// Remote elements that could not be read (undecryptable, malformed) and
  /// were left out.
  final int skipped;

  /// Whether remote settings were applied, so the settings in memory are
  /// stale.
  final bool settingsApplied;

  /// Playlists that arrived from another device; their catalog still has to be
  /// downloaded.
  final List<Playlist> createdPlaylists;

  /// Existing playlists whose source or password changed remotely; their old
  /// catalog was dropped and has to be downloaded again.
  final List<Playlist> changedPlaylists;
}

/// Synchronises the local database with a [SyncBackend], encrypting
/// everything with the data key.
///
/// Remote elements are applied first (the newest `updatedAt` wins, deletions
/// included) so that uploading never overwrites a newer remote change.
///
/// With settings sync off on this device ([CatalogDb.syncSettingsEnabled]),
/// settings and preferences are neither applied nor uploaded; local changes
/// stay dirty. Turning it back on downloads everything once, so whichever
/// side changed last wins as in any other sync.
class SyncEngine {
  /// Starts using [_dataKey] on [_db]: from now on the database derives the
  /// opaque ids of favorites, progress and preferences from it
  /// ([CatalogDb.itemIds]); clear that field when the key is forgotten.
  SyncEngine(this._db, this._backend, this._dataKey, this._passwords) {
    _db.itemIds = ItemIds(_dataKey);
  }

  final CatalogDb _db;
  final SyncBackend _backend;
  final List<int> _dataKey;
  final PasswordStore _passwords;
  Future<SyncReport>? _running;
  bool _closed = false;

  /// Stops this engine for good (the account signed out or switched key): a
  /// pass in flight finishes without applying, uploading or saving a cursor
  /// from then on, so it cannot leak into the next session.
  void close() => _closed = true;

  /// Downloads and applies newer remote elements, then uploads local changes.
  /// A call made while another pass runs returns that pass.
  ///
  /// Elements that cannot be read (tampered, malformed) are skipped and
  /// counted in [SyncReport.skipped]. When none of the downloaded elements can
  /// be decrypted the key is taken as wrong: throws a [SyncCryptoException]
  /// applying and uploading nothing, cursor unchanged.
  Future<SyncReport> syncNow() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<SyncReport> _sync() async {
    if (_closed) return const SyncReport();
    // First sync of this account on this device: upload everything we have.
    if (_db.syncCursor() == null) {
      _db.markAllDirty(SyncLocalIndex(_db).allItems());
    }
    final syncSettings = _db.syncSettingsEnabled();
    final catchUp = syncSettings && _db.syncSettingsCatchUp();
    final pulled = await _pullAndApply(
      syncSettings: syncSettings,
      fromStart: catchUp,
    );
    if (_closed) return pulled;
    if (catchUp) _db.finishSyncSettingsCatchUp();
    final pushed = await _push(syncSettings: syncSettings);
    // Moves the cursor past what was just uploaded (and picks up whatever
    // other devices uploaded meanwhile).
    final after = pushed > 0
        ? await _pullAndApply(syncSettings: syncSettings)
        : null;
    return SyncReport(
      pushed: pushed,
      pulled: pulled.pulled + (after?.pulled ?? 0),
      applied: pulled.applied + (after?.applied ?? 0),
      // The second download re-reads (overlap) the same unreadable elements.
      skipped: max(pulled.skipped, after?.skipped ?? 0),
      settingsApplied:
          pulled.settingsApplied || (after?.settingsApplied ?? false),
      createdPlaylists: [
        ...pulled.createdPlaylists,
        ...?after?.createdPlaylists,
      ],
      changedPlaylists: [
        ...pulled.changedPlaylists,
        ...?after?.changedPlaylists,
      ],
    );
  }

  /// Whether the data key opens what is stored: true when some remote element
  /// decrypts (or is sealed but malformed) or when there is nothing stored.
  /// Downloads everything, so it is for rare checks only.
  Future<bool> keyOpensRemoteData() async {
    final remote = await _backend.pull(null);
    for (final r in remote) {
      if (r.payload == null) continue;
      try {
        await _decrypt(r);
        return true;
      } on SyncCryptoException {
        continue;
      } on FormatException {
        return true;
      }
    }
    return remote.isEmpty;
  }

  /// Decrypts one remote element. Throws [SyncCryptoException] when its
  /// sealed content cannot be opened (wrong key or tampered) and
  /// [FormatException] when it is missing or not the expected JSON.
  Future<SyncItem> _decrypt(RemoteItem r) async {
    Map<String, Object?>? data;
    final payload = r.payload;
    if (payload == null) {
      throw const FormatException('Elemento remoto sin contenido.');
    }
    // Tombstones carry a sealed empty payload, so a deletion is authenticated
    // like any other change.
    final plain = await SyncCrypto.open(
      _dataKey,
      payload,
      aad: _aadOf(r.kind, r.itemId, r.updatedAt, r.deleted),
    );
    if (!r.deleted) {
      try {
        data = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
      } on Object {
        throw const FormatException('Contenido remoto ilegible.');
      }
    }
    return (
      kind: r.kind,
      itemId: r.itemId,
      data: data,
      updatedAt: r.updatedAt,
      deleted: r.deleted,
    );
  }

  /// Downloads from the cursor ([fromStart]: everything), applies what is
  /// newer than the local copy and moves the cursor (also past unreadable
  /// elements, which are skipped). Playlists go first so their favorites find
  /// them. Without [syncSettings], settings and preferences are left out.
  Future<SyncReport> _pullAndApply({
    required bool syncSettings,
    bool fromStart = false,
  }) async {
    final remote = await _backend.pull(
      fromStart ? null : _db.syncCursor()?.subtract(syncOverlap),
    );
    if (_closed) return const SyncReport();
    final items = <SyncItem>[];
    var skipped = 0;
    var failedToOpen = 0;
    for (final r in remote) {
      try {
        items.add(await _decrypt(r));
      } on SyncCryptoException {
        skipped++;
        failedToOpen++;
      } on FormatException {
        skipped++;
      }
    }
    // Nothing opened with this key: it is the wrong one, not a bad element.
    if (failedToOpen > 0 && items.isEmpty) {
      throw const SyncCryptoException(
        'No se pueden descifrar los datos: clave incorrecta o datos alterados.',
      );
    }
    items.sort((x, y) => _applyOrder(x).compareTo(_applyOrder(y)));
    final index = SyncLocalIndex(_db);
    final created = <Playlist>[];
    final changed = <Playlist>[];
    var applied = 0;
    var settingsApplied = false;
    // Applying writes through the normal API; those writes are marked clean
    // right after, so they must not schedule another sync.
    await _db.quietly(() async {
      for (final item in items) {
        if (_closed) break;
        if (!syncSettings && followsSettingsSwitch(item.kind)) continue;
        final local = _db.syncState(item.kind, item.itemId);
        if (local != null && !item.updatedAt.isAfter(local.updatedAt)) continue;
        try {
          final result = await applyItem(_db, _passwords, item, index: index);
          applied++;
          if (item.kind == settingsKind) settingsApplied = true;
          if (result != null) {
            (result.created ? created : changed).add(result.playlist);
          }
        } on TypeError {
          skipped++;
        } on FormatException {
          skipped++;
        } on ArgumentError {
          skipped++;
        }
      }
      if (!_closed) await mergeDuplicatePlaylists(_db, _passwords);
    });
    final stamps = remote.map((r) => r.syncedAt).whereType<DateTime>();
    if (stamps.isNotEmpty && !_closed) {
      _db.saveSyncCursor(stamps.reduce((a, b) => a.isAfter(b) ? a : b));
    }
    return SyncReport(
      pulled: remote.length,
      applied: applied,
      skipped: skipped,
      settingsApplied: settingsApplied,
      createdPlaylists: created,
      changedPlaylists: changed,
    );
  }

  /// Encrypts and uploads the dirty elements; returns how many. Elements that
  /// changed again while uploading stay dirty, and so do settings and
  /// preferences without [syncSettings].
  Future<int> _push({required bool syncSettings}) async {
    final dirty = [
      for (final state in _db.dirtyItems())
        if (syncSettings || !followsSettingsSwitch(state.kind)) state,
    ];
    if (dirty.isEmpty) return 0;
    final index = SyncLocalIndex(_db);
    final sent = <SyncItem>[];
    final upload = <RemoteItem>[];
    for (final state in dirty) {
      final item = await exportItem(_db, _passwords, state, index: index);
      final data = item.data;
      upload.add(
        RemoteItem(
          kind: item.kind,
          itemId: item.itemId,
          payload: await SyncCrypto.seal(
            _dataKey,
            item.deleted || data == null
                ? const []
                : utf8.encode(jsonEncode(data)),
            aad: _aadOf(item.kind, item.itemId, item.updatedAt, item.deleted),
          ),
          updatedAt: item.updatedAt,
          deleted: item.deleted,
        ),
      );
      sent.add(item);
    }
    if (_closed) return 0;
    await _backend.push(upload);
    for (final item in sent) {
      final now = _db.syncState(item.kind, item.itemId);
      if (now != null && now.updatedAt == item.updatedAt) {
        _db.markClean(
          item.kind,
          item.itemId,
          item.updatedAt,
          deleted: item.deleted,
        );
      }
    }
    return sent.length;
  }
}
