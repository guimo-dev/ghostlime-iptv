import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/xtream/xtream_credentials.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

void main() {
  group('normalizeServerUrl', () {
    test('adds http scheme and strips trailing slash', () {
      expect(
        normalizeServerUrl('example.com:8080/'),
        'http://example.com:8080',
      );
    });

    test('keeps https and strips trailing slash', () {
      expect(normalizeServerUrl('https://example.com/'), 'https://example.com');
    });

    test('drops path and query of a pasted M3U link', () {
      expect(
        normalizeServerUrl('http://host:8080/get.php?username=u&password=p'),
        'http://host:8080',
      );
      expect(normalizeServerUrl('host/c/'), 'http://host');
    });

    test('trims whitespace', () {
      expect(normalizeServerUrl('  http://a.b  '), 'http://a.b');
    });
  });

  group('liveStreamUrl', () {
    const credentials = XtreamCredentials('http://h:80/', 'u', 'p');

    test('defaults to ts', () {
      expect(liveStreamUrl(credentials, 5), 'http://h:80/live/u/p/5.ts');
    });

    test('supports m3u8', () {
      expect(
        liveStreamUrl(credentials, 5, format: LiveFormat.m3u8),
        endsWith('/5.m3u8'),
      );
    });

    test('encodes special characters in credentials', () {
      const special = XtreamCredentials('http://h', 'a@b/c', 'p#+1');
      expect(
        liveStreamUrl(special, 5),
        'http://h/live/a%40b%2Fc/p%23%2B1/5.ts',
      );
    });
  });

  group('playerApiUri', () {
    test('builds query with credentials, action and params', () {
      const credentials = XtreamCredentials('h:8080', 'u&x', 'p');
      final uri = playerApiUri(
        credentials,
        action: 'get_live_streams',
        params: {'category_id': '7'},
      );
      expect(uri.path, '/player_api.php');
      expect(uri.queryParameters, {
        'username': 'u&x',
        'password': 'p',
        'action': 'get_live_streams',
        'category_id': '7',
      });
    });

    test('omits action when not given', () {
      const credentials = XtreamCredentials('h', 'u', 'p');
      expect(
        playerApiUri(credentials).queryParameters.containsKey('action'),
        isFalse,
      );
    });
  });

  group('xmltvUri', () {
    test('encodes special credentials in the query', () {
      const credentials = XtreamCredentials('host:8080/', 'u&x', 'p w+é');
      final uri = xmltvUri(credentials);
      expect(uri.origin, 'http://host:8080');
      expect(uri.path, '/xmltv.php');
      expect(uri.queryParameters, {'username': 'u&x', 'password': 'p w+é'});
      expect(uri.query, isNot(contains('u&x')));
    });
  });

  group('XtreamCredentials', () {
    test('isComplete requires all fields', () {
      expect(const XtreamCredentials('h', 'u', 'p').isComplete, isTrue);
      expect(const XtreamCredentials('h', '', 'p').isComplete, isFalse);
    });
  });
}
