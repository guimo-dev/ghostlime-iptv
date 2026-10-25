import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/channel_number.dart';

Channel _channel(String key) => Channel(
  key: key,
  name: key,
  categoryId: 'c',
  kind: MediaKind.live,
  url: 'http://h/$key.ts',
);

void main() {
  final visible = [_channel('a'), _channel('b'), _channel('c')];

  test('a channel is numbered by its 1-based place in the list shown', () {
    expect(channelNumberOf(visible[0], visible), 1);
    expect(channelNumberOf(visible[2], visible), 3);
  });

  test('a channel missing from the list has no number (0)', () {
    expect(channelNumberOf(_channel('z'), visible), 0);
  });

  test('a number gives the index of its channel in the list shown', () {
    expect(channelIndexForNumber(1, visible), 0);
    expect(channelIndexForNumber(3, visible), 2);
  });

  test('a number without a channel gives null', () {
    expect(channelIndexForNumber(0, visible), isNull);
    expect(channelIndexForNumber(4, visible), isNull);
    expect(channelIndexForNumber(99, visible), isNull);
    expect(channelIndexForNumber(1, const []), isNull);
  });
}
