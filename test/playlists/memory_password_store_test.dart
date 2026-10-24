import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';

void main() {
  test('memory store round-trips and deletes', () async {
    final store = MemoryPasswordStore();
    await store.write(1, 'p');
    expect(await store.read(1), 'p');
    await store.delete(1);
    expect(await store.read(1), isNull);
  });
}
