import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/main.dart';

void main() {
  test('isolatedDataDir reads GHOSTLIME_DATA_DIR', () {
    expect(isolatedDataDir({'GHOSTLIME_DATA_DIR': 'C:/t'}), 'C:/t');
    expect(isolatedDataDir({}), isNull);
    expect(isolatedDataDir({'GHOSTLIME_DATA_DIR': ''}), isNull);
  });
}
