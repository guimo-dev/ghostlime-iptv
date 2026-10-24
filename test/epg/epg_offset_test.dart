import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_refresh.dart';
import 'package:iptv_player/epg/programme.dart';

final _start = DateTime.utc(2026, 10, 19, 12);

Programme _prog() => Programme(
  channelId: 'a.es',
  start: _start,
  stop: _start.add(const Duration(hours: 1)),
  title: 'News',
  description: 'Daily',
);

void main() {
  group('shiftProgrammes', () {
    test('moves start and stop by the offset', () {
      final shifted = shiftProgrammes([_prog()], const Duration(minutes: 90));
      expect(shifted.single.start, DateTime.utc(2026, 10, 19, 13, 30));
      expect(shifted.single.stop, DateTime.utc(2026, 10, 19, 14, 30));
    });

    test('supports negative offsets and keeps the other fields', () {
      final shifted = shiftProgrammes([_prog()], const Duration(hours: -2));
      expect(shifted.single.start, DateTime.utc(2026, 10, 19, 10));
      expect(shifted.single.channelId, 'a.es');
      expect(shifted.single.title, 'News');
      expect(shifted.single.description, 'Daily');
    });

    test('returns the same list for a zero offset', () {
      final programmes = [_prog()];
      expect(shiftProgrammes(programmes, Duration.zero), same(programmes));
    });
  });

  group('needsEpgRefresh interval', () {
    final now = DateTime.utc(2026, 10, 19, 12);

    test('uses the given interval', () {
      final seven = now.subtract(const Duration(hours: 7));
      expect(needsEpgRefresh(seven, now, const Duration(hours: 6)), isTrue);
      expect(needsEpgRefresh(seven, now), isFalse);
    });
  });
}
