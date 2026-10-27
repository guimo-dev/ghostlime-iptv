import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../catalog/sorting.dart';
import '../m3u/episode_title.dart';
import '../player/play_target.dart';
import '../player/resume.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/content_filters.dart';
import '../settings/parental_session.dart';
import '../settings/settings_scope.dart';
import '../tv/tv_text_input.dart';
import '../ui/app_theme.dart';
import '../ui/brand_state.dart';
import '../ui/backdrop.dart';
import '../ui/category_chips.dart';
import '../ui/display_title.dart';
import '../ui/focus_card.dart';
import '../ui/form_factor.dart';
import '../vod/movie_detail_screen.dart';
import '../vod/series_detail_screen.dart';
import 'catalog_actions.dart';
import 'catalog_images.dart';

const _continueId = '__continue__';
const _favoritesId = '__favorites__';
const _recentsId = '__recents__';

const _titles = {MediaKind.movie: 'Películas', MediaKind.series: 'Series'};

/// One tile of the browser: a catalog item, a "continue watching" entry or,
/// for M3U series, a show built from its episodes.
class _Item {
  const _Item({
    required this.key,
    required this.title,
    this.imageUrl,
    this.channel,
    this.progress,
    this.episodes,
  });

  final String key;
  final String title;
  final String? imageUrl;
  final Channel? channel;
  final Progress? progress;

  /// Episodes of an M3U show (series of M3U playlists only).
  final List<Channel>? episodes;

  /// Whether the item can be a favorite (stored by its catalog key).
  bool get canFavorite => channel != null && episodes == null;
}

/// Movies or series browser: category chips (Continue watching, Favorites,
/// Recents, then the playlist's categories) over a poster grid, sorted by the
/// user's per-category preferences.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    required this.kind,
  }) : assert(kind != MediaKind.live, 'Live TV uses LiveTvScreen');

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;
  final MediaKind kind;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final int _playlistId = widget.playlist.id!;
  late final MediaKind _kind = widget.kind;
  late final List<Category> _allCategories = _db.categories(_playlistId, _kind);
  late CategorySort _categorySort = _db.categorySort(_playlistId, _kind);
  late List<Category> _categories = sortCategories(
    _allCategories,
    _categorySort,
  );
  String? _selectedId;
  List<_Item> _items = const [];
  Set<String> _favorites = const {};
  String _filter = '';
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when shown again: progress or favorites may have changed elsewhere.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) setState(_loadItems);
  }

  CatalogDb get _db => widget.db;

  /// M3U series rows are episodes and are shown grouped by show.
  bool get _groupsEpisodes =>
      _kind == MediaKind.series && widget.playlist.type != PlaylistType.xtream;

  bool get _isRealCategory =>
      _selectedId != null &&
      !{_continueId, _favoritesId, _recentsId}.contains(_selectedId);

  @override
  void initState() {
    super.initState();
    // Open on "continue watching" when there is something, else the first category.
    final settings = SettingsScope.read(context).value;
    final hasProgress = visibleProgress(
      _db.continueWatching(_playlistId, _kind),
      _db,
      _playlistId,
      _hiddenCategoryIds(settings),
    ).isNotEmpty;
    final first = hasProgress
        ? _continueId
        : _visibleCategories(settings).firstOrNull?.id;
    if (first != null) {
      _selectedId = first;
      _loadItems();
    }
  }

  _Item _fromChannel(Channel c) =>
      _Item(key: c.key, title: c.name, imageUrl: c.iconUrl, channel: c);

  /// Items for [channels]; M3U episodes are grouped by show and, with
  /// [completeShows], each show gets all its episodes (recents only hold some).
  List<_Item> _fromChannels(
    List<Channel> channels, {
    bool completeShows = false,
  }) {
    if (!_groupsEpisodes) return channels.map(_fromChannel).toList();
    var shows = groupM3uEpisodes(channels);
    if (completeShows) {
      shows = expandShows(shows, (id) => _db.channels(_playlistId, id));
    }
    return [
      for (final MapEntry(key: show, value: episodes) in shows.entries)
        _Item(
          key: 'show:$show',
          title: show,
          imageUrl: episodes.first.iconUrl,
          channel: episodes.first,
          episodes: episodes,
        ),
    ];
  }

  /// Reloads the items of the current selection with its sort.
  void _loadItems() {
    final id = _selectedId;
    _favorites = _db.favoriteKeys(_playlistId, _kind);
    if (id == null) {
      _items = const [];
    } else if (id == _continueId) {
      _items = [
        for (final p in visibleProgress(
          _db.continueWatching(_playlistId, _kind),
          _db,
          _playlistId,
          _hiddenCategoryIds(SettingsScope.read(context).value),
        ))
          _Item(
            key: p.target.key,
            title: p.target.title,
            imageUrl: p.target.iconUrl,
            progress: p,
          ),
      ];
    } else if (id == _favoritesId) {
      _items = _db
          .favoriteChannels(_playlistId, _kind)
          .map(_fromChannel)
          .toList();
    } else if (id == _recentsId) {
      _items = _fromChannels(
        _db.recentChannels(_playlistId, _kind),
        completeShows: true,
      );
    } else {
      _items = _fromChannels(
        sortChannels(
          _db.channels(_playlistId, id),
          _db.channelSort(_playlistId, _kind, id),
          _favorites,
        ),
      );
    }
  }

  void _select(String id) {
    setState(() {
      _selectedId = id;
      _loadItems();
    });
  }

  void _toggleFavorite(_Item item) {
    _db.setFavorite(
      _playlistId,
      _kind,
      item.key,
      !_favorites.contains(item.key),
    );
    setState(_loadItems);
  }

  /// Continue-watching entries play; movies and series open their page.
  Future<void> _open(_Item item) async {
    final progress = item.progress;
    final channel = item.channel;
    if (progress != null) {
      await playWithResume(
        context,
        db: _db,
        playlist: widget.playlist,
        passwords: widget.passwords,
        target: progress.target,
      );
    } else if (channel == null) {
      return;
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _kind == MediaKind.movie
              ? MovieDetailScreen(
                  db: _db,
                  playlist: widget.playlist,
                  passwords: widget.passwords,
                  movie: channel,
                )
              : SeriesDetailScreen(
                  db: _db,
                  playlist: widget.playlist,
                  passwords: widget.passwords,
                  series: item.episodes == null
                      ? channel
                      : _showChannel(item, channel),
                  m3uEpisodes: item.episodes,
                ),
        ),
      );
    }
    if (mounted) setState(_loadItems);
  }

  /// A stand-in catalog row named after an M3U show, for the detail header.
  Channel _showChannel(_Item item, Channel first) => Channel(
    key: item.key,
    name: item.title,
    categoryId: first.categoryId,
    kind: MediaKind.series,
    iconUrl: first.iconUrl,
  );

  Future<void> _sort() async {
    final changed = await editChannelSort(
      context,
      db: _db,
      playlistId: _playlistId,
      kind: _kind,
      categoryId: _selectedId!,
      favorites: _favorites,
    );
    if (changed && mounted) setState(_loadItems);
  }

  Future<void> _organize() async {
    final sort = await editCategorySort(
      context,
      db: _db,
      playlistId: _playlistId,
      kind: _kind,
      allCategories: _allCategories,
      current: _categorySort,
    );
    if (sort == null || !mounted) return;
    setState(() {
      _categorySort = sort;
      _categories = sortCategories(_allCategories, sort);
    });
  }

  Set<String> _hiddenCategoryIds(AppSettings settings) => hiddenCategoryIds(
    settings: settings,
    unlocked: ParentalSession.unlocked.value,
    playlistId: _playlistId,
    kind: _kind,
    categories: _allCategories,
  );

  /// The sorted categories the settings allow to show.
  List<Category> _visibleCategories(AppSettings settings) {
    final hidden = _hiddenCategoryIds(settings);
    return _categories.where((c) => !hidden.contains(c.id)).toList();
  }

  /// Items the settings and the filter box allow. Entries without a catalog
  /// row (continue watching) have no category and are kept.
  List<_Item> _visibleItems(AppSettings settings) {
    final hidden = _hiddenCategoryIds(settings);
    final query = foldText(_filter.trim());
    return _items
        .where(
          (i) =>
              !hidden.contains(i.channel?.categoryId) &&
              (query.isEmpty || foldText(i.title).contains(query)),
        )
        .toList();
  }

  /// Widest poster tile for the "poster size" setting.
  static double _posterExtent(PosterSize size) => switch (size) {
    PosterSize.small => 150,
    PosterSize.medium => 190,
    PosterSize.large => 240,
  };

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context).value;
    if (_allCategories.isEmpty) {
      return Center(
        child: BrandMessage(
          title: 'No hay ${_titles[_kind]!.toLowerCase()} en esta lista.',
        ),
      );
    }
    final items = _visibleItems(settings);
    final phone = usesPhoneLayout(context);
    final side = phone ? phonePageMargin : 32.0;
    final filter = TvKeyboardGate(
      builder: (context, locked) => TextField(
        readOnly: locked,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, size: 20),
          hintText: 'Filtrar',
        ),
        onChanged: (value) => setState(() => _filter = value),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, phone ? 12 : 28, side, 12),
          child: Row(
            children: [
              Text(
                _titles[_kind]!,
                style: phone
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.displaySmall,
              ),
              // On phones the filter takes the rest of the row.
              if (phone) ...[
                const SizedBox(width: 12),
                Expanded(child: filter),
              ] else ...[
                const Spacer(),
                SizedBox(width: 280, child: filter),
              ],
            ],
          ),
        ),
        CategoryChips(
          items: [
            (
              id: _continueId,
              label: 'Continuar viendo',
              icon: Icons.play_circle_outline,
            ),
            (id: _favoritesId, label: 'Favoritos', icon: Icons.star_outline),
            (id: _recentsId, label: 'Recientes', icon: Icons.history),
            for (final c in _visibleCategories(settings))
              (id: c.id, label: c.name, icon: null),
          ],
          selectedId: _selectedId,
          onSelected: _select,
          trailing: [
            if (_isRealCategory)
              IconButton(
                tooltip: 'Orden',
                icon: const Icon(Icons.sort),
                onPressed: _sort,
              ),
            IconButton(
              tooltip: 'Organizar categorías',
              icon: const Icon(Icons.tune),
              onPressed: _organize,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: BrandMessage(
                    title: _selectedId == _continueId
                        ? 'Lo que dejes a medias aparecerá aquí.'
                        : 'No hay nada aquí.',
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(side, 12, side, 32),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _posterExtent(settings.posterSize),
                    childAspectRatio: 0.54,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 20,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _PosterCard(
                    item: items[index],
                    favorite: _favorites.contains(items[index].key),
                    onTap: () => _open(items[index]),
                    onToggleFavorite: items[index].canFavorite
                        ? () => _toggleFavorite(items[index])
                        : null,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Poster grid tile: poster with shadow, favorite badge and progress, then
/// the clean title and its details (year, tags).
/// Long press toggles the favorite (keyboard: the detail page's button).
class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.favorite,
    required this.onTap,
    this.onToggleFavorite,
  });

  final _Item item;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress;
    final (:title, :details) = displayTitle(item.title);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusCard(
          onTap: onTap,
          onLongPress: onToggleFavorite,
          shadow: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Poster(url: item.imageUrl, radius: 0),
                if (onToggleFavorite != null && favorite)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.star, color: Colors.amber, size: 20),
                  ),
                if (progress != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: GradientProgress(
                      value:
                          progress.position.inMilliseconds /
                          progress.duration.inMilliseconds,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (details.isNotEmpty)
          Text(
            details.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
      ],
    );
  }
}
