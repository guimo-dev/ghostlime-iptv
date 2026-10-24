import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/player/stream_url.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

const _xtream = Playlist(
  id: 1,
  name: 'X',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
);

const _xtreamChannel = Channel(
  key: 'x:7',
  name: 'A',
  categoryId: '1',
  kind: MediaKind.live,
  streamId: 7,
);

void main() {
  final target = PlayTarget.fromChannel(_xtreamChannel);

  test('Xtream builds the live URL with the playlist format', () {
    expect(playTargetUrl(_xtream, target, 'p'), 'http://h/live/u/p/7.ts');
    expect(
      playTargetUrl(_xtream.copyWith(liveFormat: LiveFormat.m3u8), target, 'p'),
      'http://h/live/u/p/7.m3u8',
    );
  });

  test('Xtream without password gives null', () {
    expect(playTargetUrl(_xtream, target, null), isNull);
  });

  test('M3U uses the stored URL', () {
    const playlist = Playlist(
      id: 2,
      name: 'M',
      type: PlaylistType.m3uUrl,
      source: 's',
    );
    const channel = Channel(
      key: 't:a',
      name: 'A',
      categoryId: 'c',
      kind: MediaKind.live,
      url: 'http://h/a.ts',
    );
    expect(
      playTargetUrl(playlist, PlayTarget.fromChannel(channel), null),
      'http://h/a.ts',
    );
  });
}
