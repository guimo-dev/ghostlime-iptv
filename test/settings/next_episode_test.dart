import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/next_episode.dart';

void main() {
  group('nextAfter', () {
    test('returns the element after the current one', () {
      expect(nextAfter([1, 2, 3], (n) => n == 2), 3);
    });

    test('crosses season boundaries in a flattened list', () {
      final episodes = ['s1e1', 's1e2', 's2e1', 's2e2'];
      expect(nextAfter(episodes, (e) => e == 's1e2'), 's2e1');
    });

    test('returns null after the last element', () {
      expect(nextAfter([1, 2, 3], (n) => n == 3), isNull);
    });

    test('returns null when the current one is not in the list', () {
      expect(nextAfter([1, 2, 3], (n) => n == 9), isNull);
    });

    test('returns null for an empty list', () {
      expect(nextAfter(<int>[], (n) => true), isNull);
    });
  });
}
