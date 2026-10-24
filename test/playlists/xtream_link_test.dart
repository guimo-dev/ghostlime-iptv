import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playlists/xtream_link.dart';

void main() {
  test('extracts credentials from a get.php link', () {
    final c = parseXtreamLink(
      'http://h:8080/get.php?username=u&password=p&type=m3u_plus',
    );
    expect(c?.serverUrl, 'http://h:8080');
    expect(c?.username, 'u');
    expect(c?.password, 'p');
  });

  test('accepts player_api.php links', () {
    final c = parseXtreamLink('https://h/player_api.php?username=u&password=p');
    expect(c?.serverUrl, 'https://h');
  });

  test('decodes encoded credentials', () {
    final c = parseXtreamLink('http://h/get.php?username=a%40b&password=p%2B1');
    expect(c?.username, 'a@b');
    expect(c?.password, 'p+1');
  });

  test('returns null without username', () {
    expect(parseXtreamLink('http://h/get.php?password=p'), isNull);
  });

  test('returns null for free text', () {
    expect(parseXtreamLink('mi lista'), isNull);
  });
}
