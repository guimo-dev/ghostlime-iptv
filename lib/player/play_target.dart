import '../catalog/catalog_models.dart';
import '../xtream/xtream_models.dart';

/// Which Xtream URL family a target belongs to.
enum XtreamStreamType { live, movie, series }

/// Everything needed to play something and to remember it in "Continuar viendo"
/// without looking it up in the catalog again.
///
/// Xtream targets carry [xtreamType] and [xtreamId] (the URL is built from the
/// credentials); M3U targets carry [url].
class PlayTarget {
  const PlayTarget({
    required this.kind,
    required this.key,
    required this.title,
    this.iconUrl,
    this.xtreamType,
    this.xtreamId,
    this.extension,
    this.url,
    this.seriesKey,
  });

  /// Target for a live channel, movie or M3U item of the catalog.
  factory PlayTarget.fromChannel(Channel c) {
    final streamId = c.streamId;
    return PlayTarget(
      kind: c.kind,
      key: c.key,
      title: c.name,
      iconUrl: c.iconUrl,
      xtreamType: streamId == null
          ? null
          : XtreamStreamType.values.byName(c.kind.name),
      xtreamId: streamId,
      extension: c.extension,
      url: c.url,
    );
  }

  /// Target for an Xtream [episode] of [series]; its key is `xe:<episode id>`.
  factory PlayTarget.episode({
    required Channel series,
    required Episode episode,
  }) {
    final label = 'T${episode.season}E${episode.number}';
    return PlayTarget(
      kind: MediaKind.series,
      key: 'xe:${episode.id}',
      title: episode.title.isEmpty
          ? '${series.name} $label'
          : '${series.name} $label - ${episode.title}',
      iconUrl: episode.imageUrl ?? series.iconUrl,
      xtreamType: XtreamStreamType.series,
      xtreamId: episode.id,
      extension: episode.extension,
      seriesKey: series.key,
    );
  }

  final MediaKind kind;
  final String key;
  final String title;
  final String? iconUrl;
  final XtreamStreamType? xtreamType;
  final int? xtreamId;
  final String? extension;
  final String? url;

  /// Key of the series an episode belongs to, so it counts as a recent of it.
  final String? seriesKey;
}

/// Saved playback position of a [PlayTarget].
class Progress {
  const Progress({
    required this.target,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final PlayTarget target;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// Whether it is worth resuming: past the first minute and before 95 %.
  bool get isUnfinished =>
      position > const Duration(seconds: 60) &&
      position.inMilliseconds < duration.inMilliseconds * 0.95;
}
