/// Kind of content a category or channel belongs to.
enum MediaKind { live, movie, series }

/// Classifies an Xtream-style stream URL by its path:
/// `/movie/` → movie, `/series/` → series, anything else → live.
MediaKind classifyStreamUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  if (path.contains('/movie/')) return MediaKind.movie;
  if (path.contains('/series/')) return MediaKind.series;
  return MediaKind.live;
}

/// A category of a playlist's catalog.
class Category {
  const Category({required this.id, required this.name, required this.kind});

  final String id;
  final String name;
  final MediaKind kind;
}

/// A playable item of a playlist's catalog.
///
/// Exactly one of [streamId] (Xtream) and [url] (M3U) is set.
class Channel {
  const Channel({
    required this.key,
    required this.name,
    required this.categoryId,
    required this.kind,
    this.iconUrl,
    this.epgId,
    this.streamId,
    this.url,
    this.extension,
    this.rating,
  });

  /// Stable identity that survives refreshes (see `channel_key.dart`).
  final String key;
  final String name;
  final String categoryId;
  final MediaKind kind;
  final String? iconUrl;
  final String? epgId;
  final int? streamId;
  final String? url;

  /// Container extension of an Xtream movie or episode (`mp4`, `mkv`…).
  final String? extension;

  /// Provider rating of a movie or series, when known.
  final double? rating;
}
