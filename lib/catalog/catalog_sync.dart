import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../m3u/m3u_parser.dart';
import '../playlists/playlist.dart';
import '../xtream/xtream_client.dart';
import '../xtream/xtream_credentials.dart';
import 'catalog_db.dart';
import 'catalog_models.dart';
import 'channel_key.dart';

/// Age after which a cached catalog is refreshed automatically.
const refreshInterval = Duration(hours: 24);

/// Name used for M3U entries without `group-title`.
const uncategorized = 'Sin categoría';

/// Whether a catalog last refreshed at [refreshedAt] is stale at [now].
bool needsRefresh(DateTime? refreshedAt, DateTime now) =>
    refreshedAt == null || now.difference(refreshedAt) > refreshInterval;

/// Error recorded when a refresh fails for a reason other than an
/// [XtreamException], whose text may hold URLs or credentials.
const syncFailedMessage = 'No se ha podido actualizar la lista.';

/// Item counts of a successful sync.
class SyncResult {
  const SyncResult({this.live = 0, this.movies = 0, this.series = 0});

  final int live;
  final int movies;
  final int series;
}

/// Downloads [playlist]'s catalog and replaces the cached one in [db].
///
/// [password] is required for Xtream playlists. Throws [XtreamException]
/// (Spanish message, no URL) on failure, leaving the previous catalog intact
/// and recording the message (see [CatalogDb.syncError]); any other failure
/// records [syncFailedMessage] and rethrows. A success clears the error.
Future<SyncResult> syncPlaylist(
  CatalogDb db,
  Playlist playlist, {
  String? password,
  http.Client? httpClient,
  DateTime Function() now = DateTime.now,
}) async {
  final playlistId = playlist.id;
  if (playlistId == null) throw ArgumentError('Playlist must be saved first');
  final client = httpClient ?? http.Client();
  try {
    final m3u = playlist.type == PlaylistType.xtream
        ? null
        : await _readM3u(playlist, client);
    final (categories, channels) = m3u == null
        ? await _fetchXtream(playlist, password ?? '', client)
        : _buildFromM3u(m3u);
    db.replaceCatalog(playlistId, categories, channels, now().toUtc());
    if (m3u != null) db.saveM3uTvgUrl(playlistId, parseM3uTvgUrl(m3u));
    db.saveSyncError(playlistId, null);
    int count(MediaKind kind) => channels.where((c) => c.kind == kind).length;
    return SyncResult(
      live: count(MediaKind.live),
      movies: count(MediaKind.movie),
      series: count(MediaKind.series),
    );
  } on XtreamException catch (e) {
    _recordSyncError(db, playlistId, e.message);
    rethrow;
  } catch (_) {
    _recordSyncError(db, playlistId, syncFailedMessage);
    rethrow;
  } finally {
    if (httpClient == null) client.close();
  }
}

/// Saves [message] as the refresh error of [playlistId], unless the playlist
/// was deleted meanwhile (its id could be reused by a new one).
void _recordSyncError(CatalogDb db, int playlistId, String message) {
  if (db.playlists().any((p) => p.id == playlistId)) {
    db.saveSyncError(playlistId, message);
  }
}

/// Longest [checkPlaylistSource] waits, so the form never hangs on a server
/// that does not answer.
const sourceCheckTimeout = Duration(seconds: 15);

/// Checks that [playlist] can be reached before saving it: for Xtream, that
/// the server accepts the credentials. Returns the Spanish error to show, or
/// `null` when it is fine. M3U playlists are not checked (that would mean
/// downloading the whole list twice). Gives up after [timeout].
Future<String?> checkPlaylistSource(
  Playlist playlist, {
  String? password,
  http.Client? httpClient,
  Duration timeout = sourceCheckTimeout,
}) async {
  if (playlist.type != PlaylistType.xtream) return null;
  final xtream = XtreamClient(
    XtreamCredentials(
      playlist.serverUrl ?? '',
      playlist.username ?? '',
      password ?? '',
    ),
    httpClient: httpClient,
    userAgent: playlist.userAgent,
  );
  try {
    await xtream.authenticate().timeout(timeout);
    return null;
  } on XtreamException catch (e) {
    return e.message;
  } on TimeoutException {
    return 'El servidor no responde (tiempo agotado).';
  } catch (_) {
    // Anything else comes from building the request from the address (e.g.
    // a bad port); its text may hold the password, so it is never shown.
    return 'La dirección del servidor no es válida.';
  } finally {
    if (httpClient == null) xtream.close();
  }
}

/// Fetches live, movie and series categories and items from an Xtream server.
/// An empty live list is an error; empty movies or series are not.
Future<(List<Category>, List<Channel>)> _fetchXtream(
  Playlist playlist,
  String password,
  http.Client client,
) async {
  final xtream = XtreamClient(
    XtreamCredentials(
      playlist.serverUrl ?? '',
      playlist.username ?? '',
      password,
    ),
    httpClient: client,
    userAgent: playlist.userAgent,
  );
  await xtream.authenticate();
  final categories = await xtream.getLiveCategories();
  final streams = await xtream.getLiveStreams();
  if (streams.isEmpty) {
    throw const XtreamException('El servidor no ha devuelto canales.');
  }
  final vodCategories = await xtream.getVodCategories();
  final vodStreams = await xtream.getVodStreams();
  final seriesCategories = await xtream.getSeriesCategories();
  final seriesItems = await xtream.getSeries();
  // Movie and series category ids are prefixed with their kind (as in M3U) so
  // they never collide with live ids, which are looked up by id alone.
  return (
    [
      for (final c in categories)
        Category(id: c.id, name: c.name, kind: MediaKind.live),
      for (final c in vodCategories)
        Category(id: 'movie:${c.id}', name: c.name, kind: MediaKind.movie),
      for (final c in seriesCategories)
        Category(id: 'series:${c.id}', name: c.name, kind: MediaKind.series),
    ],
    [
      for (final s in streams)
        Channel(
          key: 'x:${s.streamId}',
          name: s.name,
          categoryId: s.categoryId,
          kind: MediaKind.live,
          iconUrl: s.iconUrl,
          epgId: s.epgChannelId,
          streamId: s.streamId,
        ),
      for (final m in vodStreams)
        Channel(
          key: 'xm:${m.streamId}',
          name: m.name,
          categoryId: 'movie:${m.categoryId}',
          kind: MediaKind.movie,
          iconUrl: m.iconUrl,
          streamId: m.streamId,
          extension: m.extension,
          rating: m.rating,
        ),
      for (final s in seriesItems)
        Channel(
          key: 'xs:${s.seriesId}',
          name: s.name,
          categoryId: 'series:${s.categoryId}',
          kind: MediaKind.series,
          iconUrl: s.coverUrl,
          streamId: s.seriesId,
          rating: s.rating,
        ),
    ],
  );
}

/// Reads the M3U text from the playlist URL or local file.
Future<String> _readM3u(Playlist playlist, http.Client client) async {
  final source = playlist.source ?? '';
  if (playlist.type == PlaylistType.m3uFile) {
    try {
      return await File(source).readAsString();
    } on FileSystemException {
      throw const XtreamException('No se puede leer el fichero de la lista.');
    }
  }
  final http.Response response;
  try {
    response = await client
        .get(Uri.parse(source), headers: {'User-Agent': ?playlist.userAgent})
        .timeout(const Duration(seconds: 60));
  } catch (_) {
    // Network errors embed the URL (which may hold credentials).
    throw const XtreamException('No se puede descargar la lista.');
  }
  if (response.statusCode != 200) {
    throw XtreamException(
      'La lista ha respondido con un error (HTTP ${response.statusCode}).',
    );
  }
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

/// Turns M3U text into categories (first-appearance order) and channels.
(List<Category>, List<Channel>) _buildFromM3u(String content) {
  final entries = parseM3u(content);
  if (entries.isEmpty) {
    throw const XtreamException('La lista no contiene canales.');
  }
  final keys = m3uChannelKeys(entries);
  final categories = <String, Category>{};
  final channels = <Channel>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final kind = classifyStreamUrl(entry.url);
    final group = entry.groupTitle ?? uncategorized;
    // Ids are per kind so a group name shared by live and VOD stays separate.
    final categoryId = '${kind.name}:$group';
    categories.putIfAbsent(
      categoryId,
      () => Category(id: categoryId, name: group, kind: kind),
    );
    channels.add(
      Channel(
        key: keys[i],
        name: entry.name,
        categoryId: categoryId,
        kind: kind,
        iconUrl: entry.tvgLogo,
        epgId: entry.tvgId,
        url: entry.url,
      ),
    );
  }
  return (categories.values.toList(), channels);
}
