import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playlists/playlist.dart';

const _base = Playlist(
  id: 1,
  name: 'A',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
);

void main() {
  test('sourceChanged ignores name, user agent and format', () {
    expect(
      _base.sourceChanged(_base.copyWith(name: 'B', userAgent: 'UA')),
      isFalse,
    );
  });

  test('sourceChanged detects type, server, user and source changes', () {
    expect(
      _base.sourceChanged(_base.copyWith(type: PlaylistType.m3uUrl)),
      isTrue,
    );
    expect(_base.sourceChanged(_base.copyWith(serverUrl: 'http://x')), isTrue);
    expect(_base.sourceChanged(_base.copyWith(username: 'v')), isTrue);
    expect(_base.sourceChanged(_base.copyWith(source: 'http://l.m3u')), isTrue);
  });
}
