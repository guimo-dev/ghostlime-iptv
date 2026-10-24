import '../catalog/catalog_db.dart';
import '../playlists/playlist.dart';
import '../xtream/xtream_client.dart';
import '../xtream/xtream_credentials.dart';
import '../xtream/xtream_urls.dart';
import 'programme.dart';
import 'xmltv.dart';

/// Age after which the stored guide is refreshed automatically.
const epgRefreshInterval = Duration(hours: 12);

/// How far back from now programmes are kept.
const epgPast = Duration(hours: 6);

/// How far ahead of now programmes are kept.
const epgFuture = Duration(hours: 72);

/// Signature of [fetchXmltv], injectable for tests.
typedef EpgFetcher = Future<List<Programme>> Function(
  Uri url, {
  required Set<String> channelIds,
  required DateTime from,
  required DateTime to,
  String? userAgent,
});

/// Whether saving [after] (edited from [before], `null` when new) changes
/// where its guide comes from, so it should be downloaded right away.
bool guideChangedByEdit(
  Playlist? before,
  Playlist after, {
  required bool passwordChanged,
}) =>
    before == null ||
    passwordChanged ||
    before.sourceChanged(after) ||
    before.epgUrl != after.epgUrl;

/// Whether a guide last refreshed at [refreshedAt] is stale at [now], that is
/// older than [interval].
bool needsEpgRefresh(
  DateTime? refreshedAt,
  DateTime now, [
  Duration interval = epgRefreshInterval,
]) => refreshedAt == null || now.difference(refreshedAt) > interval;

/// [programmes] with start and stop moved by [offset], to correct a provider
/// guide that runs early or late. Returns [programmes] itself for no offset.
List<Programme> shiftProgrammes(List<Programme> programmes, Duration offset) {
  if (offset == Duration.zero) return programmes;
  return [
    for (final p in programmes)
      Programme(
        channelId: p.channelId,
        start: p.start.add(offset),
        stop: p.stop.add(offset),
        title: p.title,
        description: p.description,
      ),
  ];
}

/// Where [playlist]'s guide comes from, by priority: its own `epgUrl`, the
/// Xtream `xmltv.php` (needs [password]), the `url-tvg` saved from the M3U
/// header. `null` when there is none.
Uri? epgSource(CatalogDb db, Playlist playlist, String? password) {
  final own = playlist.epgUrl?.trim();
  if (own != null && own.isNotEmpty) return Uri.tryParse(own);
  if (playlist.type == PlaylistType.xtream) {
    return xmltvUri(
      XtreamCredentials(
        playlist.serverUrl ?? '',
        playlist.username ?? '',
        password ?? '',
      ),
    );
  }
  final id = playlist.id;
  final saved = id == null ? null : db.m3uTvgUrl(id);
  return saved == null ? null : Uri.tryParse(saved);
}

/// Downloads [playlist]'s guide for its live channels and stores it in [db],
/// keeping programmes from [epgPast] before to [epgFuture] after now.
///
/// Returns the number of programmes stored. Throws [XtreamException] when
/// there is no guide source or the download fails, leaving the previous guide
/// intact. Playlists without live EPG ids store nothing and download nothing.
/// Programmes are shifted by [offset] before being stored.
Future<int> refreshEpg(
  CatalogDb db,
  Playlist playlist, {
  String? password,
  Duration offset = Duration.zero,
  DateTime Function() now = DateTime.now,
  EpgFetcher fetch = fetchXmltv,
}) async {
  final playlistId = playlist.id;
  if (playlistId == null) throw ArgumentError('Playlist must be saved first');
  final source = epgSource(db, playlist, password);
  if (source == null) {
    throw const XtreamException('La lista no tiene guía de programación.');
  }
  final channelIds = db.liveEpgIds(playlistId);
  if (channelIds.isEmpty) return 0;
  final current = now().toUtc();
  final programmes = await fetch(
    source,
    channelIds: channelIds,
    from: current.subtract(epgPast),
    to: current.add(epgFuture),
    userAgent: playlist.userAgent,
  );
  // An empty answer (busy server, error page) must not wipe a good guide.
  if (programmes.isEmpty) {
    throw const XtreamException(
      'La guía ha llegado vacía; se mantiene la anterior.',
    );
  }
  db.replaceEpg(playlistId, shiftProgrammes(programmes, offset), current);
  return programmes.length;
}
