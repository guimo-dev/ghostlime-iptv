import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../browse/catalog_images.dart';
import '../player/play_target.dart';
import '../player/resume.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/content_filters.dart';
import '../settings/parental_session.dart';
import '../settings/settings_scope.dart';
import '../ui/brand_state.dart';
import '../ui/content_width.dart';
import '../ui/display_title.dart';
import '../vod/movie_detail_screen.dart';
import '../vod/series_detail_screen.dart';

const _minQueryLength = 2;

const _kindLabels = {
  MediaKind.live: 'Directo',
  MediaKind.movie: 'Película',
  MediaKind.series: 'Serie',
};

/// Every item of a playlist whose name contains [query] (case and accent
/// insensitive), minus those in categories the settings hide and, when the
/// settings say so, live separators. Live channels are named as in Live.
/// Live channels and M3U episodes play when tapped; movies and Xtream series
/// open their detail page. Follows the settings and the parental unlock.
class SearchResults extends StatefulWidget {
  const SearchResults({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    required this.query,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;
  final String query;

  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  late final int _playlistId = widget.playlist.id!;
  late String _query;
  List<Channel> _results = const [];

  /// Name shown for each of [_results], in the same order.
  List<String> _titles = const [];
  Set<String> _favorites = const {};

  @override
  void initState() {
    super.initState();
    ParentalSession.unlocked.addListener(_onUnlockChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs first and on every settings change.
    SettingsScope.of(context);
    _search();
  }

  @override
  void dispose() {
    ParentalSession.unlocked.removeListener(_onUnlockChanged);
    super.dispose();
  }

  void _onUnlockChanged() => setState(_search);

  @override
  void didUpdateWidget(SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _search();
  }

  /// The `(kind, categoryId)` pairs of the categories the settings hide.
  Set<(MediaKind, String)> _hiddenCategories() {
    final settings = SettingsScope.read(context).value;
    return {
      for (final kind in MediaKind.values)
        for (final id in hiddenCategoryIds(
          settings: settings,
          unlocked: ParentalSession.unlocked.value,
          playlistId: _playlistId,
          kind: kind,
          categories: widget.db.categories(_playlistId, kind),
        ))
          (kind, id),
    };
  }

  /// Runs the search for the current query; call inside `setState` or
  /// before the first build.
  void _search() {
    final settings = SettingsScope.read(context).value;
    _query = widget.query.trim();
    final hidden = _hiddenCategories();
    bool hiddenSeparator(Channel c) =>
        c.kind == MediaKind.live &&
        settings.hideSeparators &&
        isSeparatorName(c.name);
    _results = _query.length < _minQueryLength
        ? const []
        : widget.db
              .searchChannels(_playlistId, _query)
              .where(
                (c) =>
                    !hidden.contains((c.kind, c.categoryId)) &&
                    !hiddenSeparator(c),
              )
              .toList();
    _titles = _displayNames(settings);
    _favorites = widget.db.favoriteKeys(_playlistId, MediaKind.live);
  }

  /// Names for [_results]: live channels as Live shows them (the clean title
  /// when the setting asks, a suffix for names repeated within their group);
  /// other items as they come.
  List<String> _displayNames(AppSettings settings) {
    final titles = [for (final c in _results) c.name];
    final groups = <String, List<int>>{};
    for (final (index, c) in _results.indexed) {
      if (c.kind != MediaKind.live) continue;
      groups.putIfAbsent(c.categoryId, () => []).add(index);
    }
    for (final indexes in groups.values) {
      final names = distinctNames([
        for (final i in indexes)
          settings.stripChannelPrefix
              ? displayTitle(_results[i].name).title
              : _results[i].name,
      ]);
      for (final (n, i) in indexes.indexed) {
        titles[i] = names[n];
      }
    }
    return titles;
  }

  /// Favorite toggling applies to live channels only.
  void _toggleFavorite(Channel channel) {
    widget.db.setFavorite(
      _playlistId,
      channel.kind,
      channel.key,
      !_favorites.contains(channel.key),
    );
    setState(_search);
  }

  /// Live channels and M3U episodes play; movies and Xtream series open
  /// their detail page.
  Future<void> _open(Channel channel) async {
    final Widget? page = switch (channel.kind) {
      MediaKind.movie => MovieDetailScreen(
        db: widget.db,
        playlist: widget.playlist,
        passwords: widget.passwords,
        movie: channel,
      ),
      MediaKind.series when channel.streamId != null => SeriesDetailScreen(
        db: widget.db,
        playlist: widget.playlist,
        passwords: widget.passwords,
        series: channel,
      ),
      _ => null,
    };
    if (page != null) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    } else {
      await playWithResume(
        context,
        db: widget.db,
        playlist: widget.playlist,
        passwords: widget.passwords,
        target: PlayTarget.fromChannel(channel),
      );
    }
    if (mounted) setState(_search);
  }

  @override
  Widget build(BuildContext context) {
    if (_query.length < _minQueryLength) {
      return const Center(child: Text('Escribe al menos 2 letras'));
    }
    if (_results.isEmpty) {
      return const Center(child: BrandMessage(title: 'Nada encontrado'));
    }
    // The rows paint their ink on the nearest Material; the app background
    // sits between this and the page's, so bring one of our own.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView.builder(
          padding: ContentWidth.paddingFor(
            constraints.maxWidth,
            const EdgeInsets.fromLTRB(32, 0, 32, 32),
          ),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final channel = _results[index];
            final isLive = channel.kind == MediaKind.live;
            final favorite = _favorites.contains(channel.key);
            return ListTile(
              leading: ChannelLogo(url: channel.iconUrl),
              title: Text(_titles[index]),
              subtitle: Text(_kindLabels[channel.kind]!),
              onTap: () => _open(channel),
              trailing: isLive
                  ? IconButton(
                      tooltip: favorite
                          ? 'Quitar de favoritos'
                          : 'Añadir a favoritos',
                      icon: Icon(favorite ? Icons.star : Icons.star_border),
                      onPressed: () => _toggleFavorite(channel),
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}
