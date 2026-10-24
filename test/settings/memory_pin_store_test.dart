import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';

void main() {
  test('memory pin store sets, verifies and clears', () async {
    final store = MemoryPinStore();
    expect(await store.hasPin(), isFalse);
    expect(await store.verify('1234'), isFalse);
    await store.setPin('1234');
    expect(await store.hasPin(), isTrue);
    expect(await store.verify('1234'), isTrue);
    expect(await store.verify('0000'), isFalse);
    await store.clear();
    expect(await store.hasPin(), isFalse);
  });
}
