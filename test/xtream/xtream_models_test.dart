import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/xtream/xtream_models.dart';

void main() {
  group('LiveStream.fromJson', () {
    test('accepts string ids and empty icon', () {
      final stream = LiveStream.fromJson({
        'stream_id': '42',
        'name': 'A',
        'category_id': 7,
        'stream_icon': '',
      });
      expect(stream.streamId, 42);
      expect(stream.name, 'A');
      expect(stream.categoryId, '7');
      expect(stream.iconUrl, isNull);
    });

    test('accepts int ids, null icon and empty epg id', () {
      final stream = LiveStream.fromJson({
        'stream_id': 42,
        'name': 'A',
        'category_id': '7',
        'stream_icon': null,
        'epg_channel_id': '',
      });
      expect(stream.streamId, 42);
      expect(stream.categoryId, '7');
      expect(stream.iconUrl, isNull);
      expect(stream.epgChannelId, isNull);
    });

    test('keeps non-empty icon and epg id', () {
      final stream = LiveStream.fromJson({
        'stream_id': 1,
        'name': 'B',
        'category_id': '1',
        'stream_icon': 'http://x/logo.png',
        'epg_channel_id': 'b.es',
      });
      expect(stream.iconUrl, 'http://x/logo.png');
      expect(stream.epgChannelId, 'b.es');
    });
  });

  group('LiveCategory.fromJson', () {
    test('accepts int category id', () {
      final category = LiveCategory.fromJson({
        'category_id': 3,
        'category_name': 'Deportes',
      });
      expect(category.id, '3');
      expect(category.name, 'Deportes');
    });
  });
}
