import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';
import 'sync_backend.dart';

/// Rows fetched per request when pulling, and rows sent per request when
/// pushing.
const _pullPageSize = 1000;
const _pushBatchSize = 200;

/// [SyncBackend] over the Supabase tables `profiles` and `sync_items` defined
/// in `supabase/schema.sql`. Row level security limits every query to the
/// signed-in user. Needs `Supabase.initialize` to have run.
class SupabaseSyncBackend implements SyncBackend {
  SupabaseClient get _client => Supabase.instance.client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AccountException('La sesión ha caducado. Vuelve a entrar.');
    }
    return id;
  }

  @override
  Future<RemoteProfile?> loadProfile() async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return RemoteProfile(
      kdfSalt: row['kdf_salt'] as String,
      wrappedKey: row['wrapped_key'] as String,
    );
  }

  @override
  Future<void> saveProfile(RemoteProfile profile) =>
      _client.from('profiles').upsert({
        'user_id': _userId,
        'kdf_salt': profile.kdfSalt,
        'wrapped_key': profile.wrappedKey,
      }, onConflict: 'user_id');

  @override
  Future<bool> createProfile(RemoteProfile profile) async {
    try {
      await _client.from('profiles').insert({
        'user_id': _userId,
        'kdf_salt': profile.kdfSalt,
        'wrapped_key': profile.wrappedKey,
      });
      return true;
    } on PostgrestException catch (e) {
      // unique_violation: the profile already exists.
      if (e.code == '23505') return false;
      rethrow;
    }
  }

  @override
  Future<List<RemoteItem>> pull(DateTime? since) async {
    final userId = _userId;
    final items = <RemoteItem>[];
    while (true) {
      var query = _client.from('sync_items').select().eq('user_id', userId);
      final last = items.isEmpty ? null : items.last;
      if (last != null) {
        query = query.or(_after(last));
      } else if (since != null) {
        query = query.gt('synced_at', since.toUtc().toIso8601String());
      }
      // Keyset paging over the total order (rows of one batch share
      // synced_at): a row written between two pages cannot shift the next
      // page the way an offset would.
      final rows = await query
          .order('synced_at', ascending: true)
          .order('kind', ascending: true)
          .order('item_id', ascending: true)
          .limit(_pullPageSize);
      // Stops only on an empty page: the server may cap rows per response
      // (`max_rows`) below the page size, so a short page is not the end.
      if (rows.isEmpty) return items;
      items.addAll(rows.map(_itemFromRow));
    }
  }

  /// PostgREST filter for the rows ordered after [last] by
  /// `(synced_at, kind, item_id)`.
  static String _after(RemoteItem last) {
    final at = _quote(last.syncedAt!.toUtc().toIso8601String());
    final kind = _quote(last.kind);
    final itemId = _quote(last.itemId);
    return 'synced_at.gt.$at,'
        'and(synced_at.eq.$at,kind.gt.$kind),'
        'and(synced_at.eq.$at,kind.eq.$kind,item_id.gt.$itemId)';
  }

  /// [value] as a double-quoted PostgREST filter value.
  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  @override
  Future<void> push(List<RemoteItem> items) async {
    for (var start = 0; start < items.length; start += _pushBatchSize) {
      final batch = items.skip(start).take(_pushBatchSize);
      // The RPC takes the user from the session, keeps the newest version of
      // each element and leaves synced_at to the trigger.
      await _client.rpc<void>(
        'push_items',
        params: {
          'items': [
            for (final item in batch)
              {
                'kind': item.kind,
                'item_id': item.itemId,
                'payload': item.payload,
                'updated_at': item.updatedAt.toUtc().toIso8601String(),
                'deleted': item.deleted,
              },
          ],
        },
      );
    }
  }

  @override
  Future<void> deleteAll() =>
      _client.from('sync_items').delete().eq('user_id', _userId);

  static RemoteItem _itemFromRow(Map<String, dynamic> row) => RemoteItem(
    kind: row['kind'] as String,
    itemId: row['item_id'] as String,
    payload: row['payload'] as String?,
    updatedAt: DateTime.parse(row['updated_at'] as String),
    deleted: row['deleted'] as bool,
    syncedAt: DateTime.parse(row['synced_at'] as String),
  );
}
