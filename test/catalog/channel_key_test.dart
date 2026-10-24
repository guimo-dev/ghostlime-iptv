import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/channel_key.dart';
import 'package:iptv_player/m3u/m3u_parser.dart';

M3uEntry _entry(String name, String url, {String? tvgId}) =>
    M3uEntry(name: name, url: url, tvgId: tvgId);

void main() {
  test('fnv1a64Hex matches reference values', () {
    expect(fnv1a64Hex(''), 'cbf29ce484222325');
    expect(fnv1a64Hex('a'), 'af63dc4c8601ec8c');
  });

  group('m3uChannelKeys', () {
    test('uses unique tvg-id', () {
      final keys = m3uChannelKeys([_entry('A', 'http://h/1', tvgId: 'a.es')]);
      expect(keys, ['t:a.es']);
    });

    test('hashes repeated tvg-ids into distinct keys', () {
      final keys = m3uChannelKeys([
        _entry('A', 'http://h/1', tvgId: 'dup'),
        _entry('B', 'http://h/2', tvgId: 'dup'),
      ]);
      expect(keys[0], startsWith('h:'));
      expect(keys[1], startsWith('h:'));
      expect(keys[0], isNot(keys[1]));
    });

    test('hashes entries without tvg-id', () {
      expect(
        m3uChannelKeys([_entry('A', 'http://h/1')]).single,
        startsWith('h:'),
      );
    });

    test('is stable across calls', () {
      final entries = [_entry('A', 'http://h/1')];
      expect(m3uChannelKeys(entries), m3uChannelKeys(entries));
    });
  });
}
