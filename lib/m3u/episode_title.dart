import '../catalog/catalog_models.dart';

final _episodePattern = RegExp(
  r'^(.+?)[\s\-–_.:]+S(\d{1,3})\s*E(\d{1,3})(?!\d)',
  caseSensitive: false,
);

/// Splits an episode title like `Dark S01E02`, `Dark S1 E2` or
/// `ES - Dark - S02 E10 - Título` into show, season and episode number.
/// Returns `null` when the title has no season/episode marker.
({String show, int season, int episode})? parseEpisodeTitle(String name) {
  final match = _episodePattern.firstMatch(name.trim());
  if (match == null) return null;
  final show = match[1]!.trim();
  if (show.isEmpty) return null;
  return (
    show: show,
    season: int.parse(match[2]!),
    episode: int.parse(match[3]!),
  );
}

/// Groups M3U episode rows by show name, shows in order of first appearance
/// and episodes by (season, episode). A title that does not parse becomes its
/// own show, keyed by the full title.
Map<String, List<Channel>> groupM3uEpisodes(List<Channel> episodes) {
  final shows = <String, List<(int, int, int, Channel)>>{};
  for (var i = 0; i < episodes.length; i++) {
    final channel = episodes[i];
    final parsed = parseEpisodeTitle(channel.name);
    shows.putIfAbsent(parsed?.show ?? channel.name, () => []).add((
      parsed?.season ?? 0,
      parsed?.episode ?? 0,
      i,
      channel,
    ));
  }
  return {
    for (final entry in shows.entries)
      entry.key: [
        for (final (_, _, _, channel)
            in entry.value.toList()..sort((a, b) {
              final bySeason = a.$1.compareTo(b.$1);
              if (bySeason != 0) return bySeason;
              final byEpisode = a.$2.compareTo(b.$2);
              return byEpisode != 0 ? byEpisode : a.$3.compareTo(b.$3);
            }))
          channel,
      ],
  };
}

/// Completes each show of [partial] (e.g. grouped recent episodes) with all its
/// episodes, loaded from the show's category through [loadCategory]. A show no
/// longer in its category keeps its partial list.
Map<String, List<Channel>> expandShows(
  Map<String, List<Channel>> partial,
  List<Channel> Function(String categoryId) loadCategory,
) {
  final byCategory = <String, Map<String, List<Channel>>>{};
  return {
    for (final MapEntry(key: show, value: episodes) in partial.entries)
      show:
          byCategory.putIfAbsent(
            episodes.first.categoryId,
            () => groupM3uEpisodes(loadCategory(episodes.first.categoryId)),
          )[show] ??
          episodes,
  };
}
