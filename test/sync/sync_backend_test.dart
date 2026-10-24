import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sync/sync_backend.dart';

RemoteItem _item(String id, String payload, DateTime updatedAt) => RemoteItem(
  kind: 'favorite',
  itemId: id,
  payload: payload,
  updatedAt: updatedAt,
  deleted: false,
);

void main() {
  final t1 = DateTime.utc(2026, 10, 20, 10);
  final t2 = DateTime.utc(2026, 10, 20, 11);

  group('createProfile', () {
    test('creates once and never overwrites an existing profile', () async {
      final backend = InMemorySyncBackend();
      const first = RemoteProfile(kdfSalt: 'a', wrappedKey: 'b');
      const second = RemoteProfile(kdfSalt: 'c', wrappedKey: 'd');

      expect(await backend.createProfile(first), isTrue);
      expect(await backend.createProfile(second), isFalse);

      expect((await backend.loadProfile())!.wrappedKey, 'b');
    });
  });

  group('push', () {
    test('an older push does not overwrite a newer row', () async {
      final backend = InMemorySyncBackend();
      await backend.push([_item('a', 'newer', t2)]);
      final stamped = backend.items.single.syncedAt;

      await backend.push([_item('a', 'older', t1)]);

      expect(backend.items.single.payload, 'newer');
      expect(backend.items.single.syncedAt, stamped);
    });

    test('a push with the same updatedAt is ignored too', () async {
      final backend = InMemorySyncBackend();
      await backend.push([_item('a', 'first', t1)]);

      await backend.push([_item('a', 'second', t1)]);

      expect(backend.items.single.payload, 'first');
    });

    test('a newer push replaces the row', () async {
      final backend = InMemorySyncBackend();
      await backend.push([_item('a', 'old', t1)]);

      await backend.push([_item('a', 'new', t2)]);

      expect(backend.items.single.payload, 'new');
    });
  });

  group('pull paging', () {
    test('an item updated between pages is still received', () async {
      final backend = InMemorySyncBackend(pageSize: 2);
      await backend.push([
        for (var i = 1; i <= 5; i++) _item('i$i', 'old', t1),
      ]);
      var pages = 0;
      backend.betweenPages = () async {
        // After the first page, the first item changes and moves to the end.
        if (++pages == 1) await backend.push([_item('i1', 'new', t2)]);
      };

      final received = await backend.pull(null);

      expect(received.map((i) => i.itemId).toSet(), {
        'i1',
        'i2',
        'i3',
        'i4',
        'i5',
      });
      expect(
        received.where((i) => i.itemId == 'i1').last.payload,
        'new',
        reason: 'the updated version arrives in a later page',
      );
    });

    test('pull(since) returns only rows stamped after it', () async {
      final backend = InMemorySyncBackend(pageSize: 2);
      await backend.push([_item('a', 'x', t1)]);
      final first = (await backend.pull(null)).single.syncedAt!;
      await backend.push([_item('b', 'x', t1)]);

      final later = await backend.pull(first);

      expect(later.map((i) => i.itemId), ['b']);
    });
  });
}
