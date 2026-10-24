/// The user's encryption profile as stored on the server (`profiles` table):
/// the Argon2id salt and the data key wrapped with the password-derived key.
/// Both are base64 text.
class RemoteProfile {
  const RemoteProfile({required this.kdfSalt, required this.wrappedKey});

  /// base64 of the Argon2id salt.
  final String kdfSalt;

  /// `base64(nonce | ciphertext | mac)` of the data key sealed with the
  /// password-derived key.
  final String wrappedKey;
}

/// One row of the server's `sync_items` table. Only [payload] is secret and it
/// is always encrypted; the rest travels in clear.
class RemoteItem {
  const RemoteItem({
    required this.kind,
    required this.itemId,
    required this.payload,
    required this.updatedAt,
    required this.deleted,
    this.syncedAt,
  });

  /// `playlist`, `favorite`, `progress`, `pref` or `settings`.
  final String kind;

  /// Opaque id: a UUID or a hash.
  final String itemId;

  /// `base64(nonce | ciphertext | mac)` of the JSON data (empty for a
  /// deletion), sealed with the element's identity and version as associated
  /// data. `null` only on foreign or tampered rows.
  final String? payload;

  /// When the change was made on the device (the newest wins).
  final DateTime updatedAt;

  /// Whether this is a deletion mark.
  final bool deleted;

  /// When the server stored it (drives incremental downloads); `null` on items
  /// not stored yet.
  final DateTime? syncedAt;
}

/// Where encrypted elements are kept between devices.
abstract class SyncBackend {
  /// The signed-in user's encryption profile, or `null` when none exists yet.
  Future<RemoteProfile?> loadProfile();

  /// Creates or replaces the encryption profile.
  Future<void> saveProfile(RemoteProfile profile);

  /// Stores [profile] only if the user has none yet; returns whether it did.
  /// `false` means another device got there first and nothing was changed.
  Future<bool> createProfile(RemoteProfile profile);

  /// Elements stored after [since] (all of them when `null`), oldest first.
  /// Implementations page by keyset `(synced_at, kind, item_id)`, so rows
  /// written while paging are neither skipped nor repeated.
  Future<List<RemoteItem>> pull(DateTime? since);

  /// Creates or replaces elements; the server stamps `syncedAt`. The server
  /// keeps the newest by `updatedAt`: an element that is not newer than the
  /// stored one is ignored.
  Future<void> push(List<RemoteItem> items);

  /// Removes every element of the user (the profile stays).
  Future<void> deleteAll();
}

/// A [SyncBackend] that keeps everything in memory, for tests. Sharing one
/// instance between engines simulates several devices on one account.
class InMemorySyncBackend implements SyncBackend {
  /// [pageSize] is how many rows [pull] fetches per page, to exercise paging.
  InMemorySyncBackend({this.pageSize = 1000});

  /// Rows per page in [pull].
  final int pageSize;

  /// Runs between two pages of [pull], to simulate other devices writing
  /// while a download is in progress.
  Future<void> Function()? betweenPages;

  RemoteProfile? _profile;
  final Map<String, RemoteItem> _items = {};
  int _clock = 0;

  /// The stored elements, in no particular order.
  List<RemoteItem> get items => _items.values.toList();

  /// Replaces a stored element as is, to simulate tampering or foreign data.
  void overwrite(RemoteItem item) =>
      _items['${item.kind}|${item.itemId}'] = item;

  @override
  Future<RemoteProfile?> loadProfile() async => _profile;

  @override
  Future<void> saveProfile(RemoteProfile profile) async => _profile = profile;

  @override
  Future<bool> createProfile(RemoteProfile profile) async {
    if (_profile != null) return false;
    _profile = profile;
    return true;
  }

  /// Total order of the server: `(synced_at, kind, item_id)`.
  static int _compare(RemoteItem a, RemoteItem b) {
    final byTime = a.syncedAt!.compareTo(b.syncedAt!);
    if (byTime != 0) return byTime;
    final byKind = a.kind.compareTo(b.kind);
    return byKind != 0 ? byKind : a.itemId.compareTo(b.itemId);
  }

  @override
  Future<List<RemoteItem>> pull(DateTime? since) async {
    final found = <RemoteItem>[];
    RemoteItem? last;
    while (true) {
      // Keyset paging: continue after the last row seen, never by offset.
      final after = last;
      final page =
          _items.values
              .where(
                (i) => after == null
                    ? since == null || i.syncedAt!.isAfter(since)
                    : _compare(i, after) > 0,
              )
              .toList()
            ..sort(_compare);
      if (page.isEmpty) return found;
      final taken = page.take(pageSize).toList();
      found.addAll(taken);
      last = taken.last;
      await betweenPages?.call();
    }
  }

  @override
  Future<void> push(List<RemoteItem> items) async {
    final syncedAt = DateTime.utc(2026).add(Duration(seconds: ++_clock));
    for (final item in items) {
      // Same rule as the server's `push_items`: only a newer change wins.
      final stored = _items['${item.kind}|${item.itemId}'];
      if (stored != null && !item.updatedAt.isAfter(stored.updatedAt)) continue;
      overwrite(
        RemoteItem(
          kind: item.kind,
          itemId: item.itemId,
          payload: item.payload,
          updatedAt: item.updatedAt,
          deleted: item.deleted,
          syncedAt: syncedAt,
        ),
      );
    }
  }

  @override
  Future<void> deleteAll() async => _items.clear();
}
