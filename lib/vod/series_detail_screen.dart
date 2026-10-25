import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../m3u/episode_title.dart';
import '../player/play_target.dart';
import '../player/resume.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/next_episode.dart';
import '../ui/app_theme.dart';
import '../ui/category_chips.dart';
import '../ui/content_width.dart';
import '../ui/focus_card.dart';
import '../ui/form_factor.dart';
import '../ui/backdrop.dart';
import '../ui/back_on_escape.dart';
import '../ui/brand_state.dart';
import 'detail_header.dart';
import 'xtream_info.dart';

/// One playable episode row.
typedef _EpisodeRow = ({String label, PlayTarget target});

/// Series page: poster, plot (Xtream), season selector and episode list with
/// progress. Xtream episodes come from `get_series_info`; M3U episodes are
/// passed in as [m3uEpisodes].
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    required this.series,
    this.m3uEpisodes,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;

  /// The catalog row of the show (or a stand-in for M3U shows).
  final Channel series;
  final List<Channel>? m3uEpisodes;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late final int _playlistId = widget.playlist.id!;
  late final Future<(String?, Map<int, List<_EpisodeRow>>)> _data = _load();
  int? _season;
  late bool _favorite = _isFavorite();

  bool get _canFavorite => widget.m3uEpisodes == null;

  bool _isFavorite() => widget.db
      .favoriteKeys(_playlistId, MediaKind.series)
      .contains(widget.series.key);

  /// Plot and episodes by season, from the panel (Xtream) or the M3U rows.
  Future<(String?, Map<int, List<_EpisodeRow>>)> _load() async {
    final episodes = widget.m3uEpisodes;
    if (episodes != null) {
      final seasons = <int, List<_EpisodeRow>>{};
      for (final episode in episodes) {
        final parsed = parseEpisodeTitle(episode.name);
        final label = parsed == null
            ? episode.name
            : 'Episodio ${parsed.episode}';
        seasons.putIfAbsent(parsed?.season ?? 1, () => []).add((
          label: label,
          target: PlayTarget.fromChannel(episode),
        ));
      }
      return (null, seasons);
    }
    final seriesId = widget.series.streamId;
    if (seriesId == null) return (null, <int, List<_EpisodeRow>>{});
    final info = await loadSeriesInfo(
      widget.playlist,
      widget.passwords,
      seriesId,
    );
    if (info == null) return (null, <int, List<_EpisodeRow>>{});
    return (
      info.plot,
      {
        for (final MapEntry(key: season, value: list) in info.seasons.entries)
          season: [
            for (final episode in list)
              (
                label: episode.title.isEmpty
                    ? 'Episodio ${episode.number}'
                    : '${episode.number}. ${episode.title}',
                target: PlayTarget.episode(
                  series: widget.series,
                  episode: episode,
                ),
              ),
          ],
      },
    );
  }

  void _toggleFavorite() {
    widget.db.setFavorite(
      _playlistId,
      MediaKind.series,
      widget.series.key,
      !_favorite,
    );
    setState(() => _favorite = _isFavorite());
  }

  /// Plays [target]; [ordered] lists every episode (seasons in order) so the
  /// one after it can follow when it ends.
  Future<void> _play(PlayTarget target, List<PlayTarget> ordered) async {
    PlayTarget? following(PlayTarget current) =>
        nextAfter(ordered, (t) => t.key == current.key);
    await playWithResume(
      context,
      db: widget.db,
      playlist: widget.playlist,
      passwords: widget.passwords,
      target: target,
      next: following(target),
      nextOf: following,
    );
    if (mounted) setState(() {});
  }

  /// Fraction watched of an episode, or `null` when never played.
  double? _watched(PlayTarget target) {
    final progress = widget.db.progress(_playlistId, target.kind, target.key);
    if (progress == null || progress.duration == Duration.zero) return null;
    return progress.position.inMilliseconds / progress.duration.inMilliseconds;
  }

  /// Next thing to play: the most recently watched unfinished episode, else
  /// the first episode of the first season.
  _EpisodeRow? _nextUp(Map<int, List<_EpisodeRow>> seasons) {
    _EpisodeRow? best;
    DateTime? bestAt;
    for (final row in seasons.values.expand((list) => list)) {
      final progress = widget.db.progress(
        _playlistId,
        row.target.kind,
        row.target.key,
      );
      if (progress != null &&
          progress.isUnfinished &&
          (bestAt == null || progress.updatedAt.isAfter(bestAt))) {
        best = row;
        bestAt = progress.updatedAt;
      }
    }
    if (best != null) return best;
    final first = (seasons.keys.toList()..sort()).firstOrNull;
    return first == null ? null : seasons[first]!.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return BackOnEscape(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Backdrop(
          imageUrl: widget.series.iconUrl,
          child: FutureBuilder(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: BrandLoader());
              }
              // Any failure (not only Xtream errors) shows the page without episodes.
              final (plot, seasons) =
                  snapshot.data ?? (null, <int, List<_EpisodeRow>>{});
              final seasonNumbers = seasons.keys.toList()..sort();
              final season = _season ?? seasonNumbers.firstOrNull;
              final rows = season == null
                  ? const <_EpisodeRow>[]
                  : seasons[season]!;
              final ordered = [
                for (final number in seasonNumbers)
                  for (final row in seasons[number]!) row.target,
              ];
              final nextUp = _nextUp(seasons);
              final nextResumes =
                  nextUp != null &&
                  (widget.db
                          .progress(
                            _playlistId,
                            nextUp.target.kind,
                            nextUp.target.key,
                          )
                          ?.isUnfinished ??
                      false);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  DetailHeader(
                    title: widget.series.name,
                    posterUrl: widget.series.iconUrl,
                    chips: [
                      if (seasonNumbers.isNotEmpty)
                        seasonNumbers.length == 1
                            ? '1 temporada'
                            : '${seasonNumbers.length} temporadas',
                    ],
                    actions: [
                      if (nextUp != null)
                        FilledButton.icon(
                          autofocus: true,
                          onPressed: () => _play(nextUp.target, ordered),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            nextResumes
                                ? 'Continuar: ${nextUp.label}'
                                : 'Reproducir',
                          ),
                        ),
                      if (_canFavorite)
                        OutlinedButton.icon(
                          onPressed: _toggleFavorite,
                          icon: Icon(
                            _favorite ? Icons.star : Icons.star_border,
                          ),
                          label: Text(_favorite ? 'En favoritos' : 'Favorito'),
                        ),
                    ],
                    body: plot == null || plot.isEmpty
                        ? null
                        : Text(
                            plot,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                  ),
                  if (seasonNumbers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: BrandMessage(
                        title: 'No se han podido cargar los episodios.',
                        dimmed: true,
                      ),
                    )
                  else
                    // Same width as the episode list below, so they line up.
                    ContentWidth(
                      child: CategoryChips(
                        items: [
                          for (final number in seasonNumbers)
                            (
                              id: '$number',
                              label: 'Temporada $number',
                              icon: null,
                            ),
                        ],
                        selectedId: '$season',
                        onSelected: (id) =>
                            setState(() => _season = int.parse(id)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ContentWidth(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: usesPhoneLayout(context)
                            ? phonePageMargin
                            : 32,
                      ),
                      // One solid surface, so no strip of the blurred backdrop
                      // shows between rows.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: AppColors.surface,
                          child: Column(
                            children: [
                              for (final (index, row) in rows.indexed) ...[
                                if (index > 0) const Divider(height: 1),
                                FocusCard(
                                  grow: false,
                                  onTap: () => _play(row.target, ordered),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.play_circle_outline,
                                          color: AppColors.accent,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(row.label),
                                              if (_watched(row.target)
                                                  case final value?)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 6,
                                                      ),
                                                  child:
                                                      LinearProgressIndicator(
                                                        value: value.clamp(
                                                          0,
                                                          1,
                                                        ),
                                                        minHeight: 3,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
