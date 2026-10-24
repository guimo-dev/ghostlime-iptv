import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sync/auth_gateway.dart';

/// Whether [link] is accepted while a Google sign-in is pending.
bool _accepted(String link) =>
    acceptsGoogleCallback(Uri.parse(link), pending: true);

void main() {
  test('a PKCE code or an error from the browser is accepted', () {
    expect(_accepted('ghostlime://login-callback?code=abc'), isTrue);
    expect(_accepted('ghostlime://login-callback/?code=abc'), isTrue);
    expect(
      _accepted(
        'ghostlime://login-callback?error=access_denied'
        '&error_description=denied',
      ),
      isTrue,
    );
  });

  test('nothing is accepted without a pending Google sign-in', () {
    expect(
      acceptsGoogleCallback(
        Uri.parse('ghostlime://login-callback?code=abc'),
        pending: false,
      ),
      isFalse,
    );
  });

  test('links with tokens are refused, in the query or the fragment', () {
    expect(
      _accepted('ghostlime://login-callback#access_token=a&refresh_token=r'),
      isFalse,
    );
    expect(_accepted('ghostlime://login-callback#refresh_token=r'), isFalse);
    expect(
      _accepted('ghostlime://login-callback?code=abc#access_token=a'),
      isFalse,
    );
    expect(
      _accepted('ghostlime://login-callback?code=abc&access_token=a'),
      isFalse,
    );
    expect(
      _accepted('ghostlime://login-callback?error=x&refresh_token=r'),
      isFalse,
    );
  });

  test('other schemes, hosts, paths or links without code are refused', () {
    expect(_accepted('ghostlime://login-callback'), isFalse);
    expect(_accepted('ghostlime://login-callback?type=recovery'), isFalse);
    expect(_accepted('ghostlime://other?code=abc'), isFalse);
    expect(_accepted('ghostlime://login-callback/extra?code=abc'), isFalse);
    expect(_accepted('https://login-callback?code=abc'), isFalse);
    expect(_accepted('evil://login-callback?code=abc'), isFalse);
  });

  test('a malformed query is refused, not thrown', () {
    expect(_accepted('ghostlime://login-callback?code=%E0%A4%A'), isFalse);
  });
}
