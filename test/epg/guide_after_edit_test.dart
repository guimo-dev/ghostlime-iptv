import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_refresh.dart';
import 'package:iptv_player/playlists/playlist.dart';

const _base = Playlist(
  id: 1,
  name: 'A',
  type: PlaylistType.xtream,
  serverUrl: 'http://h',
  username: 'u',
);

void main() {
  test('a new playlist needs its guide', () {
    expect(guideChangedByEdit(null, _base, passwordChanged: false), isTrue);
  });

  test('renaming does not touch the guide', () {
    expect(
      guideChangedByEdit(
        _base,
        _base.copyWith(name: 'B'),
        passwordChanged: false,
      ),
      isFalse,
    );
  });

  test('a new guide URL, source or password refreshes it', () {
    expect(
      guideChangedByEdit(
        _base,
        _base.copyWith(epgUrl: 'http://g/e.xml'),
        passwordChanged: false,
      ),
      isTrue,
    );
    expect(
      guideChangedByEdit(
        _base,
        _base.copyWith(serverUrl: 'http://x'),
        passwordChanged: false,
      ),
      isTrue,
    );
    expect(guideChangedByEdit(_base, _base, passwordChanged: true), isTrue);
  });
}
