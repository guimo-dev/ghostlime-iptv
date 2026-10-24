import '../playlists/playlist.dart';
import '../xtream/xtream_credentials.dart';
import '../xtream/xtream_urls.dart';
import 'play_target.dart';

/// Playback URL of [target]: built from the Xtream id for Xtream targets (needs
/// [password]; `null` without it), or the stored URL for M3U.
String? playTargetUrl(Playlist playlist, PlayTarget target, String? password) {
  final type = target.xtreamType;
  final id = target.xtreamId;
  if (type == null || id == null) return target.url;
  if (password == null) return null;
  final credentials = XtreamCredentials(
    playlist.serverUrl ?? '',
    playlist.username ?? '',
    password,
  );
  return switch (type) {
    XtreamStreamType.live => liveStreamUrl(
      credentials,
      id,
      format: playlist.liveFormat,
    ),
    XtreamStreamType.movie => movieUrl(credentials, id, target.extension),
    XtreamStreamType.series => episodeUrl(credentials, id, target.extension),
  };
}
