import 'xtream_credentials.dart';

/// Container requested for live streams.
enum LiveFormat { ts, m3u8 }

/// Normalises a server address to `scheme://host[:port]` with no trailing slash.
///
/// Adds `http://` when [raw] has no scheme and drops any path, query or
/// fragment (e.g. a pasted `get.php?...` link). An explicit port is kept as
/// written, even when it is the scheme's default.
String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (!url.contains('://')) url = 'http://$url';
  final authorityStart = url.indexOf('://') + 3;
  final authorityEnd = url.indexOf(RegExp(r'[/?#]'), authorityStart);
  return authorityEnd == -1 ? url : url.substring(0, authorityEnd);
}

/// Builds the playback URL of a live channel:
/// `{server}/live/{user}/{pass}/{streamId}.{format}`.
String liveStreamUrl(
  XtreamCredentials credentials,
  int streamId, {
  LiveFormat format = LiveFormat.ts,
}) {
  final server = normalizeServerUrl(credentials.serverUrl);
  final user = Uri.encodeComponent(credentials.username);
  final pass = Uri.encodeComponent(credentials.password);
  return '$server/live/$user/$pass/$streamId.${format.name}';
}

/// Builds the playback URL of a movie: `{server}/movie/{user}/{pass}/{id}.{ext}`.
/// A null or empty [extension] defaults to `mp4`.
String movieUrl(
  XtreamCredentials credentials,
  int streamId,
  String? extension,
) => _vodUrl('movie', credentials, streamId, extension);

/// Builds the playback URL of an episode:
/// `{server}/series/{user}/{pass}/{id}.{ext}`. A null or empty [extension]
/// defaults to `mp4`.
String episodeUrl(
  XtreamCredentials credentials,
  int episodeId,
  String? extension,
) => _vodUrl('series', credentials, episodeId, extension);

String _vodUrl(
  String path,
  XtreamCredentials credentials,
  int id,
  String? extension,
) {
  final server = normalizeServerUrl(credentials.serverUrl);
  final user = Uri.encodeComponent(credentials.username);
  final pass = Uri.encodeComponent(credentials.password);
  final ext = extension == null || extension.isEmpty ? 'mp4' : extension;
  return '$server/$path/$user/$pass/$id.$ext';
}

/// Builds the XMLTV guide URI: `{server}/xmltv.php?username=…&password=…`.
Uri xmltvUri(XtreamCredentials credentials) {
  final server = Uri.parse(normalizeServerUrl(credentials.serverUrl));
  return server.replace(
    path: '/xmltv.php',
    queryParameters: {
      'username': credentials.username,
      'password': credentials.password,
    },
  );
}

/// Builds a `player_api.php` request URI with credentials, optional [action]
/// and extra query [params].
Uri playerApiUri(
  XtreamCredentials credentials, {
  String? action,
  Map<String, String> params = const {},
}) {
  final server = Uri.parse(normalizeServerUrl(credentials.serverUrl));
  return server.replace(
    path: '/player_api.php',
    queryParameters: {
      'username': credentials.username,
      'password': credentials.password,
      'action': ?action,
      ...params,
    },
  );
}
