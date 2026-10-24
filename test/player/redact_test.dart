import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/stream_info.dart';

void main() {
  test('redactUrls hides stream URLs and their credentials', () {
    final text = redactUrls(
      'Failed to open http://h:8080/live/user/secret/123.ts. (403)',
    );
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('user')));
    expect(text, contains('(403)'));
  });

  test('redactUrls leaves text without URLs untouched', () {
    expect(redactUrls('Connection refused'), 'Connection refused');
  });
}
