import '../xtream/xtream_credentials.dart';
import '../xtream/xtream_urls.dart';

/// Extracts Xtream credentials from a pasted provider link such as
/// `http://host:8080/get.php?username=u&password=p&type=m3u_plus`
/// (also `player_api.php`). Returns `null` when [text] is not such a link.
XtreamCredentials? parseXtreamLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final username = uri.queryParameters['username'];
  final password = uri.queryParameters['password'];
  if (username == null || username.isEmpty || password == null) return null;
  return XtreamCredentials(normalizeServerUrl(text), username, password);
}
