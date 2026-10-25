import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browse/catalog_images.dart';
import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../epg/programme.dart';
import '../player/play_target.dart';
import '../player/resume.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../search/search_results.dart';
import '../settings/app_settings.dart';
import '../settings/content_filters.dart';
import '../settings/parental_session.dart';
import '../settings/settings_scope.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/content_width.dart';
import '../ui/display_title.dart';
import '../ui/focus_card.dart';
import '../ui/form_factor.dart';
import '../ui/ghostlime_logo.dart';
import '../ui/rail_row.dart';
import '../vod/movie_detail_screen.dart';
import '../vod/series_detail_screen.dart';

const _channelCardWidth = 300.0;

/// How long typing must pause before the search runs.
const _searchDebounce = Duration(milliseconds: 250);

/// Poster width of home rails for the "poster size" setting.
double _posterWidth(PosterSize size) => switch (size) {
  PosterSize.small => 120,
  PosterSize.medium => 150,
  PosterSize.large => 190,
};

/// Height of the hero banner in a window [windowHeight] tall: 420 at most, and
/// never more than 45 % of the window so the rails below stay in view.
double heroHeightFor(double windowHeight) =>
    (windowHeight * 0.45).clamp(280.0, 420.0);

/// Playlist home: a search box over everything, then the last unfinished item
/// as a hero and rails for continue watching, favorite channels, movies and
/// series, and recent channels. While the box has text its results replace
/// the rails; `Esc` empties it. [onOpenSection] jumps to a side-bar section
/// (1 = live).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    required this.onOpenSection,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;
  final ValueChanged<int> onOpenSection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final int _playlistId = widget.playlist.id!;
  late List<Progress> _continue;
  late List<Channel> _favoriteChannels;
  late List<Channel> _recentChannels;
  late List<Channel> _favoriteMovies;
  late List<Channel> _favoriteSeries;
  late Map<String, (Programme?, Programme?)> _guide;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchTimer;

  /// Text the results are shown for; empty shows the rails.
  String _query = '';

  CatalogDb get _db => widget.db;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Searches once typing pauses; an emptied box shows the rails at once.
  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(_showRails);
      return;
    }
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) setState(() => _query = value);
    });
  }

  /// Leaves the results for the rails, reloaded: favorites or progress may
  /// have changed from the results.
  void _showRails() {
    _query = '';
    _load();
  }

  /// Empties the search box and goes back to the rails, focusing the box
  /// (the focused result, if any, goes away).
  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    _searchFocus.requestFocus();
    setState(_showRails);
  }

  /// Handles Esc (or Back on a remote) while the search box has text; other
  /// keys, and Esc with an empty box, carry on. Back acts on its release, as
  /// Android does: a release left unhandled would also leave Inicio.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final escape =
        event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
    final back =
        event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.goBack;
    if (!(escape || back) || _searchController.text.isEmpty) {
      return KeyEventResult.ignored;
    }
    _clearSearch();
    return KeyEventResult.handled;
  }

  /// [channels] of [kind] minus those in categories the settings hide.
  List<Channel> _allowed(List<Channel> channels, MediaKind kind) {
    final hidden = hiddenCategoryIds(
      settings: SettingsScope.read(context).value,
      unlocked: ParentalSession.unlocked.value,
      playlistId: _playlistId,
      kind: kind,
      categories: _db.categories(_playlistId, kind),
    );
    return channels.where((c) => !hidden.contains(c.categoryId)).toList();
  }

  /// Unfinished items of [kind] minus those in categories the settings hide.
  List<Progress> _allowedProgress(MediaKind kind) {
    final hidden = hiddenCategoryIds(
      settings: SettingsScope.read(context).value,
      unlocked: ParentalSession.unlocked.value,
      playlistId: _playlistId,
      kind: kind,
      categories: _db.categories(_playlistId, kind),
    );
    return visibleProgress(
      _db.continueWatching(_playlistId, kind),
      _db,
      _playlistId,
      hidden,
    );
  }

  void _load() {
    _continue = [
      ..._allowedProgress(MediaKind.movie),
      ..._allowedProgress(MediaKind.series),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _favoriteChannels = _allowed(
      _db.favoriteChannels(_playlistId, MediaKind.live),
      MediaKind.live,
    );
    _recentChannels = _allowed(
      _db.recentChannels(_playlistId, MediaKind.live),
      MediaKind.live,
    );
    _favoriteMovies = _allowed(
      _db.favoriteChannels(_playlistId, MediaKind.movie),
      MediaKind.movie,
    );
    _favoriteSeries = _allowed(
      _db.favoriteChannels(_playlistId, MediaKind.series),
      MediaKind.series,
    );
    _guide = _db.nowNext(_playlistId, {
      for (final c in [..._favoriteChannels, ..._recentChannels])
        if (c.epgId != null) c.epgId!,
    }, DateTime.now().toUtc());
  }

  Future<void> _after(Future<void> action) async {
    await action;
    if (mounted) setState(_load);
  }

  void _play(PlayTarget target, {String? subtitle}) => _after(
    playWithResume(
      context,
      db: _db,
      playlist: widget.playlist,
      passwords: widget.passwords,
      target: target,
      subtitle: subtitle,
    ),
  );

  void _openMovie(Channel movie) => _after(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieDetailScreen(
          db: _db,
          playlist: widget.playlist,
          passwords: widget.passwords,
          movie: movie,
        ),
      ),
    ),
  );

  void _openSeries(Channel series) => _after(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(
          db: _db,
          playlist: widget.playlist,
          passwords: widget.passwords,
          series: series,
        ),
      ),
    ),
  );

  void _playChannel(Channel channel) => _play(
    PlayTarget.fromChannel(channel),
    subtitle: _guide[channel.epgId]?.$1?.title,
  );

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context).value;
    // Esc from the field or from a result empties the search.
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Padding(
            padding: usesPhoneLayout(context)
                ? const EdgeInsets.fromLTRB(
                    phonePageMargin,
                    12,
                    phonePageMargin,
                    8,
                  )
                : const EdgeInsets.fromLTRB(32, 20, 32, 12),
            child: ContentWidth(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar en directo, películas y series',
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  _searchTimer?.cancel();
                  setState(() => _query = value);
                },
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? _buildRails(settings)
                : SearchResults(
                    db: _db,
                    playlist: widget.playlist,
                    passwords: widget.passwords,
                    query: _query,
                  ),
          ),
        ],
      ),
    );
  }

  /// The hero and the rails, or the first-run invitation when all are empty.
  Widget _buildRails(AppSettings settings) {
    bool shown(HomeRail rail) => !settings.hiddenHomeRails.contains(rail);
    final posterWidth = _posterWidth(settings.posterSize);
    final posterRailHeight = posterWidth * 290 / 150;
    final continueWatching = shown(HomeRail.continueWatching)
        ? _continue
        : const <Progress>[];
    final favoriteChannels = shown(HomeRail.favoriteChannels)
        ? _favoriteChannels
        : const <Channel>[];
    final favoriteMovies = shown(HomeRail.favoriteMovies)
        ? _favoriteMovies
        : const <Channel>[];
    final favoriteSeries = shown(HomeRail.favoriteSeries)
        ? _favoriteSeries
        : const <Channel>[];
    final recentChannels = shown(HomeRail.recentChannels)
        ? _recentChannels
        : const <Channel>[];
    final hasAnything =
        continueWatching.isNotEmpty ||
        favoriteChannels.isNotEmpty ||
        recentChannels.isNotEmpty ||
        favoriteMovies.isNotEmpty ||
        favoriteSeries.isNotEmpty;
    if (!hasAnything) return _EmptyHome(onOpenSection: widget.onOpenSection);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (continueWatching.isNotEmpty)
          _Hero(
            label: 'Continuar viendo',
            name: continueWatching.first.target.title,
            imageUrl: continueWatching.first.target.iconUrl,
            progress: continueWatching.first,
            actionLabel:
                'Reanudar desde ${formatDuration(continueWatching.first.position)}',
            onAction: () => _play(continueWatching.first.target),
          )
        else if (favoriteMovies.isNotEmpty)
          _Hero(
            label: 'De tus favoritas',
            name: favoriteMovies.first.name,
            imageUrl: favoriteMovies.first.iconUrl,
            actionLabel: 'Ver ficha',
            onAction: () => _openMovie(favoriteMovies.first),
          ),
        if (continueWatching.length > 1)
          RailRow(
            title: 'Continuar viendo',
            height: posterRailHeight,
            children: [
              for (final p in continueWatching.skip(1))
                _PosterItem(
                  width: posterWidth,
                  title: p.target.title,
                  imageUrl: p.target.iconUrl,
                  progress:
                      p.position.inMilliseconds / p.duration.inMilliseconds,
                  onTap: () => _play(p.target),
                ),
            ],
          ),
        if (favoriteChannels.isNotEmpty)
          RailRow(
            title: 'Canales favoritos',
            height: 112,
            children: [
              for (final c in favoriteChannels)
                _ChannelCard(
                  channel: c,
                  now: _guide[c.epgId]?.$1,
                  onTap: () => _playChannel(c),
                ),
            ],
          ),
        if (favoriteMovies.isNotEmpty)
          RailRow(
            title: 'Películas favoritas',
            height: posterRailHeight,
            children: [
              for (final m in favoriteMovies)
                _PosterItem(
                  width: posterWidth,
                  title: m.name,
                  imageUrl: m.iconUrl,
                  onTap: () => _openMovie(m),
                ),
            ],
          ),
        if (favoriteSeries.isNotEmpty)
          RailRow(
            title: 'Series favoritas',
            height: posterRailHeight,
            children: [
              for (final s in favoriteSeries)
                _PosterItem(
                  width: posterWidth,
                  title: s.name,
                  imageUrl: s.iconUrl,
                  onTap: () => _openSeries(s),
                ),
            ],
          ),
        if (recentChannels.isNotEmpty)
          RailRow(
            title: 'Vistos recientemente',
            height: 112,
            children: [
              for (final c in recentChannels)
                _ChannelCard(
                  channel: c,
                  now: _guide[c.epgId]?.$1,
                  onTap: () => _playChannel(c),
                ),
            ],
          ),
      ],
    );
  }
}

/// Large banner over the poster's blurred backdrop: a small label, the clean
/// title with its details, optional progress and one primary action.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.label,
    required this.name,
    required this.actionLabel,
    required this.onAction,
    this.imageUrl,
    this.progress,
  });

  final String label;
  final String name;
  final String? imageUrl;
  final Progress? progress;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (:title, :details) = displayTitle(name);
    final progress = this.progress;
    final height = heroHeightFor(MediaQuery.sizeOf(context).height);
    final compact = height < 380;
    // Phones have no room for the poster beside the text.
    final phone = usesPhoneLayout(context);
    final side = phone ? phonePageMargin : 40.0;
    return SizedBox(
      height: height,
      child: Backdrop(
        imageUrl: imageUrl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, compact ? 24 : 40, side, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: AccentPalette.of(context)
                          .gradient
                          .createShader,
                      child: Text(
                        label.toUpperCase(),
                        style: text.labelLarge?.copyWith(
                          color: Colors.white,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.displaySmall,
                    ),
                    if (details.isNotEmpty || progress != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          ...details,
                          if (progress != null)
                            'Quedan ${formatDuration(progress.duration - progress.position)}',
                        ].join('  ·  '),
                        style: text.bodyLarge?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (progress != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 360,
                        child: GradientProgress(
                          value:
                              progress.position.inMilliseconds /
                              progress.duration.inMilliseconds,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: onAction,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(actionLabel),
                    ),
                  ],
                ),
              ),
              if (!phone) ...[
                const SizedBox(width: 40),
                SizedBox(
                  width: 190,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppStyle.cardShadow,
                    ),
                    child: Poster(url: imageUrl, cacheWidth: 380, radius: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Poster with clean title (and optional progress) for a home rail.
class _PosterItem extends StatelessWidget {
  const _PosterItem({
    required this.title,
    required this.width,
    required this.onTap,
    this.imageUrl,
    this.progress,
  });

  final String title;
  final double width;
  final String? imageUrl;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final clean = displayTitle(title);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FocusCard(
            onTap: onTap,
            shadow: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Poster(url: imageUrl, radius: 0),
                  if (value != null)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: GradientProgress(value: value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            clean.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (clean.details.isNotEmpty)
            Text(
              clean.details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Channel card: logo tile, name and the programme on air with progress.
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.onTap, this.now});

  final Channel channel;
  final Programme? now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = now;
    double? progress;
    if (current != null) {
      final total = current.stop.difference(current.start).inSeconds;
      final done = DateTime.now().toUtc().difference(current.start).inSeconds;
      progress = total > 0 ? done / total : null;
    }
    return SizedBox(
      width: _channelCardWidth,
      child: FocusCard(
        onTap: onTap,
        color: Colors.white.withValues(alpha: 0.05),
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ChannelLogo(url: channel.iconUrl),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Raw name: prefixes and tags tell variants apart.
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    if (current != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        GradientProgress(value: progress, height: 3),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First-run home: invites to browse live TV, movies or series.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onOpenSection});

  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GhostlimeLogo(size: 88, tile: false),
          const SizedBox(height: 12),
          Text('Empieza a ver algo', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Tus favoritos y lo que dejes a medias aparecerán aquí.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                autofocus: true,
                onPressed: () => onOpenSection(1),
                icon: const Icon(Icons.live_tv),
                label: const Text('Directo'),
              ),
              OutlinedButton.icon(
                onPressed: () => onOpenSection(2),
                icon: const Icon(Icons.movie_outlined),
                label: const Text('Películas'),
              ),
              OutlinedButton.icon(
                onPressed: () => onOpenSection(3),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Series'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
