import '../xtream/xtream_urls.dart';

/// Where a playlist's catalog comes from.
enum PlaylistType { xtream, m3uUrl, m3uFile }

/// A user-configured source of channels.
///
/// The Xtream password is not stored here; it lives in the OS secure storage.
class Playlist {
  const Playlist({
    this.id,
    required this.name,
    required this.type,
    this.serverUrl,
    this.username,
    this.source,
    this.userAgent,
    this.liveFormat = LiveFormat.ts,
    this.refreshedAt,
    this.epgUrl,
    this.syncId,
  });

  /// Database id; `null` until saved.
  final int? id;

  /// Opaque id shared by every device the playlist is synced to; `null` until
  /// saved. Unlike [id] it is the same on all devices.
  final String? syncId;
  final String name;
  final PlaylistType type;

  /// Xtream server address.
  final String? serverUrl;

  /// Xtream username.
  final String? username;

  /// M3U URL or local file path.
  final String? source;

  /// User-Agent sent to the API and the player; `null` uses the default.
  final String? userAgent;

  /// Container requested for Xtream live channels.
  final LiveFormat liveFormat;

  /// When the catalog was last refreshed successfully.
  final DateTime? refreshedAt;

  /// Optional XMLTV guide URL; wins over the provider's own guide. Changing it
  /// does not make the catalog stale, so [sourceChanged] ignores it.
  final String? epgUrl;

  /// Whether [other] points at a different catalog source than this playlist
  /// (type, server, username or M3U source), so its cached catalog is stale.
  bool sourceChanged(Playlist other) =>
      type != other.type ||
      serverUrl != other.serverUrl ||
      username != other.username ||
      source != other.source;

  /// Returns a copy with the given fields replaced.
  Playlist copyWith({
    int? id,
    String? name,
    PlaylistType? type,
    String? serverUrl,
    String? username,
    String? source,
    String? userAgent,
    LiveFormat? liveFormat,
    DateTime? refreshedAt,
    String? epgUrl,
    String? syncId,
  }) {
    return Playlist(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      type: type ?? this.type,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      source: source ?? this.source,
      userAgent: userAgent ?? this.userAgent,
      liveFormat: liveFormat ?? this.liveFormat,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      epgUrl: epgUrl ?? this.epgUrl,
    );
  }
}
