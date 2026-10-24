import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../catalog/catalog_models.dart';
import 'sync_crypto.dart';

/// `kind` of each synced element, as stored in `sync_state` and on the server.
const playlistKind = 'playlist';
const favoriteKind = 'favorite';
const progressKind = 'progress';
const prefKind = 'pref';
const settingsKind = 'settings';

/// `item_id` of the single settings element.
const settingsItemId = 'settings';

/// A new random opaque id (UUID v4 shape) for a playlist.
String newSyncId() {
  final bytes = SyncCrypto.randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// Opaque `item_id`s for favorites, progress and preferences. The real key
/// (channel, scope) travels only inside the encrypted payload; the id is an
/// HMAC-SHA256 of it under a sub-key of the data key, so the server cannot
/// confirm a guess about what an id stands for, and ids of different accounts
/// are unrelated. Playlist ids are random instead (see [newSyncId]).
class ItemIds {
  /// Derives the id sub-key `HMAC(dataKey, "item-ids")` from [dataKey].
  ItemIds(List<int> dataKey) : _key = SecretKeyData(_hmac(dataKey, 'item-ids'));

  final SecretKeyData _key;

  static final _sha256 = Hmac.sha256().toSync();

  static List<int> _hmac(List<int> key, String text) => _sha256
      .calculateMacSync(
        utf8.encode(text),
        secretKeyData: SecretKeyData(key),
        nonce: const [],
      )
      .bytes;

  /// First 32 hex characters (128 bits) of the HMAC of [text].
  String _digest(String text) {
    final bytes = _sha256
        .calculateMacSync(
          utf8.encode(text),
          secretKeyData: _key,
          nonce: const [],
        )
        .bytes;
    return [for (final b in bytes.take(16)) b.toRadixString(16).padLeft(2, '0')]
        .join();
  }

  /// `item_id` of the favorite [key] of [kind] in the playlist
  /// [playlistSyncId].
  String favorite(String playlistSyncId, MediaKind kind, String key) =>
      '$playlistSyncId:${_digest('item|${kind.name}|$key')}';

  /// `item_id` of the saved progress of [key]; same shape as [favorite].
  String progress(String playlistSyncId, MediaKind kind, String key) =>
      favorite(playlistSyncId, kind, key);

  /// `item_id` of the preference [scope] of a playlist, or of the global ones
  /// when [playlistSyncId] is `null`.
  String pref(String? playlistSyncId, String scope) =>
      '${playlistSyncId ?? 'global'}:${_digest('pref|$scope')}';
}

/// Preference scope of the live view's guide toggle (see
/// `CatalogDb.liveGuideGrid`).
const liveGuideGridScope = 'live/guide-grid';

/// Whether a `prefs` scope is synced (sort orders, hidden categories and the
/// live guide toggle); settings have their own kind and guide data stays
/// local.
bool isSyncedPrefScope(String scope) =>
    scope.startsWith('channels/') ||
    scope.startsWith('categories/') ||
    scope == liveGuideGridScope;
