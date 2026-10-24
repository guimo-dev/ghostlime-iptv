import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:media_kit_video/media_kit_video.dart';

import '../browse/catalog_actions.dart';
import '../browse/catalog_images.dart';
import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../catalog/sorting.dart';
import '../epg/guide_grid.dart';
import '../epg/programme.dart';
import '../player/mpv_options.dart';
import '../player/play_target.dart';
import '../player/playback_log.dart';
import '../player/resume.dart';
import '../player/stream_url.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/content_filters.dart';
import '../settings/parental_session.dart';
import '../settings/settings_scope.dart';
import '../sync/account_scope.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/brand_state.dart';
import '../ui/display_title.dart';
import '../ui/focus_card.dart';

const _favoritesId = '__favorites__';
const _recentsId = '__recents__';
const _kind = MediaKind.live;
const _rowHeight = 64.0;
const _panelMinHeight = 250.0;
const _panelPadding = 24.0;

/// Width of the live preview inside a now panel [panelWidth] wide: about a
/// third of the panel, never tiny and never taking over a huge window.
double previewWidthFor(double panelWidth) =>
    ((panelWidth - 2 * _panelPadding) * 0.32).clamp(240.0, 640.0);

/// TV-first live view: groups on the left; on the right, the selected
/// channel's programme for the rest of the day and a live preview above the
/// channel rows, or above the guide grid when the "Guía" toggle is on (saved
/// per playlist).
///
/// A first click/Enter selects a channel and previews it; a second one (or
/// "Pantalla completa") opens the full player. Only one connection is ever
/// open: the preview stops before the full player starts and whenever this
/// screen is hidden.
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    this.previewStartTimeout = streamStartTimeout,
    this.clock = DateTime.now,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;

  /// How long the preview may take to start before it shows an error
  /// (shorter in tests).
  final Duration previewStartTimeout;

  /// The time used to read the guide (fixed in tests).
  final DateTime Function() clock;

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  late final int _playlistId = widget.playlist.id!;
  late final Future<String?> _password =
      widget.playlist.type == PlaylistType.xtream
      ? widget.passwords.read(_playlistId)
      : Future.value(null);
  late final List<Category> _allCategories = _db.categories(_playlistId, _kind);
  late CategorySort _categorySort = _db.categorySort(_playlistId, _kind);
  late List<Category> _categories = sortCategories(
    _allCategories,
    _categorySort,
  );
  String? _groupId;
  List<Channel> _channels = const [];
  Set<String> _favorites = const {};
  Map<String, (Programme?, Programme?)> _guide = const {};

  /// Bumped every time the guide is read again, so the grid re-reads it too.
  int _guideRevision = 0;

  /// The selected channel's programmes after the one on air, today.
  List<Programme> _upcoming = const [];

  /// Whether the guide grid replaces the channel rows.
  late bool _guideGrid = _db.liveGuideGrid(_playlistId);
  String _filter = '';
  Channel? _selected;
  Timer? _clock;

  Player? _preview;
  VideoController? _previewController;
  bool _muted = true;

  /// Bumped to cancel preview starts still awaiting.
  int _previewGeneration = 0;

  /// Fires when the preview has not started within
  /// [LiveTvScreen.previewStartTimeout].
  Timer? _previewStartTimer;
  StreamSubscription<Duration>? _previewPosition;

  /// Generation whose `open` has returned: only its positions mean the
  /// preview started (the reused player may still report the old channel).
  int? _previewOpenedGeneration;

  /// Generation that last called `open`: an older start that is no longer
  /// wanted may only stop the player while no newer one has opened it.
  int? _previewOpeningGeneration;

  /// Whether the current preview gave up because it never started.
  bool _previewFailed = false;
  bool _fullScreenOpen = false;
  bool _visible = true;

  CatalogDb get _db => widget.db;

  bool get _isRealGroup =>
      _groupId != null && _groupId != _favoritesId && _groupId != _recentsId;

  @override
  void initState() {
    super.initState();
    _muted = !SettingsScope.read(context).value.previewSound;
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _visible) setState(_loadGuide);
    });
    // Start where the user's channels are: favorites, recents, else the first group.
    final start = _db.favoriteChannels(_playlistId, _kind).isNotEmpty
        ? _favoritesId
        : _db.recentChannels(_playlistId, _kind).isNotEmpty
        ? _recentsId
        : _visibleCategories(SettingsScope.read(context).value).firstOrNull?.id;
    if (start != null) _selectGroup(start);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the account brings us here after every sync, which may
    // have applied the (synced) guide toggle.
    AccountScope.of(context);
    _guideGrid = _db.liveGuideGrid(_playlistId);
    // Hidden by the shell (another section shown): free the connection.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      // Favorites, recents or guide may have changed in other sections.
      setState(_loadChannels);
      _startPreview();
    } else {
      _previewGeneration++;
      _preview?.stop();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _previewStartTimer?.cancel();
    _previewPosition?.cancel();
    _preview?.dispose();
    super.dispose();
  }

  void _selectGroup(String id) {
    setState(() {
      _groupId = id;
      _loadChannels();
    });
  }

  void _loadChannels() {
    final id = _groupId;
    _favorites = _db.favoriteKeys(_playlistId, _kind);
    _channels = switch (id) {
      null => const [],
      _favoritesId => _db.favoriteChannels(_playlistId, _kind),
      _recentsId => _db.recentChannels(_playlistId, _kind),
      _ => sortChannels(
        _db.channels(_playlistId, id),
        _db.channelSort(_playlistId, _kind, id),
        _favorites,
      ),
    };
    _loadGuide();
  }

  void _loadGuide() {
    final now = widget.clock().toUtc();
    _guide = _db.nowNext(_playlistId, {
      for (final c in _channels)
        if (c.epgId != null) c.epgId!,
      if (_selected?.epgId != null) _selected!.epgId!,
    }, now);
    _upcoming = _upcomingToday(now);
    _guideRevision++;
  }

  /// Programmes of the selected channel starting after [now] and before
  /// midnight (local); at least the next one when there is any.
  List<Programme> _upcomingToday(DateTime now) {
    final epgId = _selected?.epgId;
    if (epgId == null) return const [];
    final local = now.toLocal();
    final midnight = DateTime(local.year, local.month, local.day + 1).toUtc();
    final today = [
      for (final p in _db.programmes(_playlistId, {epgId}, now, midnight))
        if (p.start.isAfter(now)) p,
    ];
    final next = _guide[epgId]?.$2;
    return today.isEmpty && next != null ? [next] : today;
  }

  /// Switches between the channel rows and the guide grid, and remembers it.
  void _toggleGuideGrid() {
    setState(() => _guideGrid = !_guideGrid);
    _db.saveLiveGuideGrid(_playlistId, _guideGrid);
  }

  /// The sorted categories the settings allow to show.
  List<Category> _visibleCategories(AppSettings settings) {
    final hidden = _hiddenCategoryIds(settings);
    return _categories.where((c) => !hidden.contains(c.id)).toList();
  }

  Set<String> _hiddenCategoryIds(AppSettings settings) => hiddenCategoryIds(
    settings: settings,
    unlocked: ParentalSession.unlocked.value,
    playlistId: _playlistId,
    kind: _kind,
    categories: _allCategories,
  );

  /// Display names of the current group's channels by key: the provider's
  /// name, with a suffix on same-named ones, keyed by channel so filtering
  /// does not renumber them.
  Map<String, String> _namesByKey() => {
    for (final (index, name) in distinctNames([
      for (final c in _channels) c.name,
    ]).indexed)
      _channels[index].key: name,
  };

  /// Channels of the current group that the settings and the filter box allow.
  List<Channel> _visibleChannels(AppSettings settings) {
    final hidden = _hiddenCategoryIds(settings);
    final query = foldText(_filter.trim());
    return _channels
        .where(
          (c) =>
              !hidden.contains(c.categoryId) &&
              (query.isEmpty || foldText(c.name).contains(query)),
        )
        .toList();
  }

  /// First tap previews; tapping the selected channel again goes full screen.
  void _onChannel(Channel channel) {
    if (_selected?.key == channel.key) {
      _fullScreen();
      return;
    }
    setState(() {
      _selected = channel;
      _loadGuide();
    });
    _startPreview();
  }

  /// Starts previewing the selected channel. Every await re-checks that this
  /// request is still current ([_previewGeneration]), visible and not
  /// replaced by the full player, so two streams are never open at once.
  Future<void> _startPreview() async {
    final channel = _selected;
    if (channel == null || !_visible || _fullScreenOpen) return;
    final generation = ++_previewGeneration;
    bool stillWanted() =>
        mounted &&
        generation == _previewGeneration &&
        _visible &&
        !_fullScreenOpen &&
        _selected?.key == channel.key;

    final url = playTargetUrl(
      widget.playlist,
      PlayTarget.fromChannel(channel),
      await _password,
    );
    if (url == null || !stillWanted()) return;
    final player = _preview ??= Player();
    _previewController ??= VideoController(player);
    _previewPosition ??= player.stream.position.listen((position) {
      if (position > Duration.zero &&
          _previewOpenedGeneration == _previewGeneration) {
        _previewStartTimer?.cancel();
      }
    });
    final userAgent = widget.playlist.userAgent;
    await player.setVolume(_muted ? 0 : 100);
    await useSafeDemuxerOptions(player);
    _previewOpenedGeneration = null;
    await player.stop();
    if (!stillWanted()) return;
    if (_previewFailed) setState(() => _previewFailed = false);
    _previewStartTimer?.cancel();
    _previewStartTimer = Timer(widget.previewStartTimeout, () {
      if (!stillWanted()) return;
      PlaybackLogScope.read(context)
          ?.record(PlaybackEvent.startTimeout, detail: 'preview');
      player.stop();
      setState(() => _previewFailed = true);
    });
    _previewOpeningGeneration = generation;
    await player.open(
      Media(
        url,
        httpHeaders: userAgent == null ? null : {'User-Agent': userAgent},
      ),
    );
    // Hidden or replaced while opening: the stop issued then may have landed
    // before the open, so close the stream now.
    if (!stillWanted()) {
      if (mounted && _previewOpeningGeneration == generation) {
        await player.stop();
      }
      return;
    }
    if (generation == _previewGeneration) _previewOpenedGeneration = generation;
    if (mounted) setState(() {});
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _preview?.setVolume(_muted ? 0 : 100);
  }

  Future<void> _fullScreen() async {
    final channel = _selected;
    if (channel == null || _fullScreenOpen) return;
    // One connection only: cancel any pending preview start and close the
    // preview stream before the full player.
    _fullScreenOpen = true;
    _previewGeneration++;
    await _preview?.stop();
    if (!mounted) return;
    await playWithResume(
      context,
      db: _db,
      playlist: widget.playlist,
      passwords: widget.passwords,
      target: PlayTarget.fromChannel(channel),
      subtitle: _guide[channel.epgId]?.$1?.title,
    );
    _fullScreenOpen = false;
    if (!mounted) return;
    setState(_loadChannels);
    _startPreview();
  }

  void _toggleFavorite(Channel channel) {
    _db.setFavorite(
      _playlistId,
      _kind,
      channel.key,
      !_favorites.contains(channel.key),
    );
    setState(_loadChannels);
  }

  Future<void> _sort() async {
    final changed = await editChannelSort(
      context,
      db: _db,
      playlistId: _playlistId,
      kind: _kind,
      categoryId: _groupId!,
      favorites: _favorites,
    );
    if (changed && mounted) setState(_loadChannels);
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

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context).value;
    if (_allCategories.isEmpty) {
      return const Center(
        child: BrandMessage(title: 'No hay canales. Actualiza la lista.'),
      );
    }
    return Row(
      children: [
        SizedBox(width: 250, child: _buildGroups(settings)),
        Expanded(
          child: Column(
            children: [
              NowPanel(
                channel: _selected,
                channelName: _selected == null
                    ? ''
                    : _namesByKey()[_selected!.key] ?? _selected!.name,
                now: _guide[_selected?.epgId]?.$1,
                upcoming: _upcoming,
                controller: _preview == null ? null : _previewController,
                failed: _previewFailed,
                muted: _muted,
                favorite: _favorites.contains(_selected?.key),
                onFullScreen: _fullScreen,
                onToggleSound: _toggleSound,
                onToggleFavorite: _selected == null
                    ? null
                    : () => _toggleFavorite(_selected!),
                clock: widget.clock,
              ),
              _buildToolbar(),
              Expanded(
                child: _guideGrid
                    ? _buildGuideGrid(settings)
                    : _buildChannels(settings),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroups(AppSettings settings) {
    final categories = _visibleCategories(settings);
    Widget tile(String id, String label, {IconData? icon}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: FocusCard(
        grow: false,
        selected: id == _groupId,
        onTap: () => _selectGroup(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        border: const Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Grupos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Organizar grupos',
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: _organize,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length + 2,
              itemBuilder: (context, index) => switch (index) {
                0 => tile(_favoritesId, 'Favoritos', icon: Icons.star_outline),
                1 => tile(_recentsId, 'Recientes', icon: Icons.history),
                _ => tile(categories[index - 2].id, categories[index - 2].name),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Filtrar canales',
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _guideGrid
                ? 'Volver a la lista de canales'
                : 'Ver la guía de los canales',
            child: _guideGrid
                ? FilledButton.icon(
                    onPressed: _toggleGuideGrid,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('Guía'),
                  )
                : OutlinedButton.icon(
                    onPressed: _toggleGuideGrid,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('Guía'),
                  ),
          ),
          if (_isRealGroup) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _sort,
              icon: const Icon(Icons.sort, size: 18),
              label: const Text('Orden'),
            ),
          ],
        ],
      ),
    );
  }

  /// The guide grid over the current group's visible channels.
  Widget _buildGuideGrid(AppSettings settings) {
    final channels = _visibleChannels(settings);
    if (channels.isEmpty) {
      return const Center(
        child: BrandMessage(title: 'No hay canales en este grupo'),
      );
    }
    return GuideGrid(
      db: _db,
      playlistId: _playlistId,
      channels: channels,
      names: _namesByKey(),
      selectedKey: _selected?.key,
      onChannel: _onChannel,
      revision: _guideRevision,
      clock: widget.clock,
    );
  }

  Widget _buildChannels(AppSettings settings) {
    final channels = _visibleChannels(settings);
    if (channels.isEmpty) {
      return const Center(
        child: BrandMessage(title: 'No hay canales en este grupo'),
      );
    }
    final names = _namesByKey();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemExtent: _rowHeight,
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final (now, next) = _guide[channel.epgId] ?? (null, null);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ChannelRow(
            number: index + 1,
            channel: channel,
            name: names[channel.key] ?? channel.name,
            now: now,
            next: next,
            selected: channel.key == _selected?.key,
            favorite: _favorites.contains(channel.key),
            onTap: () => _onChannel(channel),
            onToggleFavorite: () => _toggleFavorite(channel),
            clock: widget.clock,
          ),
        );
      },
    );
  }
}

/// Top panel: the selected channel's programme on air with its progress, the
/// rest of today's programmes (scrolling when they do not fit) and its
/// preview.
class NowPanel extends StatelessWidget {
  const NowPanel({
    super.key,
    required this.channel,
    required this.channelName,
    required this.now,
    required this.upcoming,
    required this.controller,
    required this.failed,
    required this.muted,
    required this.favorite,
    required this.onFullScreen,
    required this.onToggleSound,
    required this.onToggleFavorite,
    this.clock = DateTime.now,
  });

  final Channel? channel;
  final String channelName;

  /// Programme on air, if the guide has it.
  final Programme? now;

  /// Programmes after [now], in order; the first one is "A continuación".
  final List<Programme> upcoming;
  final VideoController? controller;

  /// The preview did not start in time; shows a message over the black box.
  final bool failed;
  final bool muted;
  final bool favorite;
  final VoidCallback onFullScreen;
  final VoidCallback onToggleSound;
  final VoidCallback? onToggleFavorite;

  /// The current time, for the minutes left and the progress (fixed in tests).
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = channel;
    final now = this.now;
    final time = clock().toUtc();
    final controller = this.controller;
    final mutedText = text.bodySmall?.copyWith(color: AppColors.textMuted);
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = previewWidthFor(constraints.maxWidth);
        return Container(
          height: max(
            _panelMinHeight,
            previewWidth * 9 / 16 + _panelPadding * 2,
          ),
          margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          padding: const EdgeInsets.all(_panelPadding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.selected.withValues(alpha: 0.9),
                AppColors.surfaceHigh.withValues(alpha: 0.9),
              ],
            ),
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: current == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        shaderCallback: AppStyle.accentGradient.createShader,
                        child: const Icon(
                          Icons.live_tv_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Elige un canal para ver qué echan',
                        style: text.titleMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Programme on air and the rest of the day (else
                          // its description); scrolls when it does not fit.
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                Row(
                                  children: [
                                    ChannelLogo(url: current.iconUrl),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        channelName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelLarge?.copyWith(
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  now?.title ?? 'Sin información',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.headlineMedium,
                                ),
                                if (now != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${formatClock(now.start)}–${formatClock(now.stop)}'
                                    ' · quedan ${now.stop.difference(time).inMinutes} min',
                                    style: mutedText,
                                  ),
                                  const SizedBox(height: 6),
                                  GradientProgress(
                                    value: _elapsed(now, time),
                                    height: 3,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                if ((upcoming.isEmpty ? now?.description : null)
                                    case final description?)
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall,
                                  ),
                                if (upcoming.isNotEmpty)
                                  Text(
                                    'A continuación',
                                    style: text.labelSmall?.copyWith(
                                      color: AppColors.accent,
                                    ),
                                  ),
                                for (final programme in upcoming)
                                  _UpcomingRow(
                                    programme: programme,
                                    timeStyle: mutedText,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: onFullScreen,
                                icon: const Icon(Icons.fullscreen),
                                label: const Text(
                                  'Pantalla completa',
                                  softWrap: false,
                                ),
                              ),
                              IconButton.outlined(
                                tooltip: favorite
                                    ? 'Quitar de favoritos'
                                    : 'Añadir a favoritos',
                                onPressed: onToggleFavorite,
                                icon: Icon(
                                  favorite ? Icons.star : Icons.star_border,
                                ),
                              ),
                              IconButton.outlined(
                                tooltip: muted ? 'Activar sonido' : 'Silenciar',
                                onPressed: onToggleSound,
                                icon: Icon(
                                  muted ? Icons.volume_off : Icons.volume_up,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: previewWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppStyle.cardShadow,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: ColoredBox(
                              color: Colors.black,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: controller == null
                                        ? const SizedBox.shrink()
                                        : Video(
                                            controller: controller,
                                            controls: NoVideoControls,
                                          ),
                                  ),
                                  if (failed)
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: BrandMessage(
                                            title: 'No se ha podido abrir el canal',
                                            logoSize: 48,
                                            dimmed: true,
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (controller != null)
                                    _PreviewLoader(controller: controller),
                                  const Positioned(
                                    top: 10,
                                    left: 10,
                                    child: LiveBadge(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Share of [programme] already aired at [time], from 0 to 1.
double _elapsed(Programme programme, DateTime time) {
  final total = programme.stop.difference(programme.start).inSeconds;
  final done = time.toUtc().difference(programme.start).inSeconds;
  return total > 0 ? (done / total).clamp(0.0, 1.0) : 0;
}

/// A later programme in the now panel: start time and title.
class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.programme, required this.timeStyle});

  final Programme programme;
  final TextStyle? timeStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(formatClock(programme.start), style: timeStyle),
          ),
          Expanded(
            child: Text(
              programme.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// One channel row: number, logo, name, programme on air with progress,
/// next programme and favorite star.
class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.number,
    required this.channel,
    required this.name,
    required this.now,
    required this.next,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.clock = DateTime.now,
  });

  final int number;
  final Channel channel;
  final String name;
  final Programme? now;
  final Programme? next;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  /// The current time, for the progress of [now] (fixed in tests).
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted);
    final current = now;
    double? progress;
    if (current != null) {
      final total = current.stop.difference(current.start).inSeconds;
      final done = clock().toUtc().difference(current.start).inSeconds;
      progress = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    }
    return FocusCard(
      grow: false,
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text('$number', style: muted, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 12),
            Container(
              width: 52,
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ChannelLogo(url: channel.iconUrl),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: current == null
                  ? Text('—', style: muted)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      // Stretch so the progress track spans the whole column.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        if (progress != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: GradientProgress(value: progress, height: 3),
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Text(
                next == null
                    ? ''
                    : '${formatClock(next!.start)} ${next!.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            IconButton(
              tooltip: favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onPressed: onToggleFavorite,
              icon: Icon(
                favorite ? Icons.star : Icons.star_border,
                color: favorite ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the live preview shows over the video box.
enum PreviewOverlay { loading, audioOnly, none }

/// Overlay for the preview given the decoded video [width] and playback
/// [position]: loading until something plays, a decoded picture needs none,
/// and playback without a picture is an audio-only stream (radio).
PreviewOverlay previewOverlay({
  required int? width,
  required Duration position,
}) {
  if ((width ?? 0) > 0) return PreviewOverlay.none;
  if (position > Duration.zero) return PreviewOverlay.audioOnly;
  return PreviewOverlay.loading;
}

/// Branded loader over the preview until playback starts, or a static
/// "Solo audio" state when the stream has no picture.
class _PreviewLoader extends StatefulWidget {
  const _PreviewLoader({required this.controller});

  final VideoController controller;

  @override
  State<_PreviewLoader> createState() => _PreviewLoaderState();
}

class _PreviewLoaderState extends State<_PreviewLoader> {
  late final Player _player = widget.controller.player;
  late int? _width = _player.state.width;
  late Duration _position = _player.state.position;
  late final List<StreamSubscription<Object?>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      _player.stream.width.listen((width) => setState(() => _width = width)),
      _player.stream.position.listen(
        (position) => setState(() => _position = position),
      ),
    ];
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (previewOverlay(width: _width, position: _position)) {
      PreviewOverlay.none => const SizedBox.shrink(),
      PreviewOverlay.loading => const Center(child: BrandLoader(size: 48)),
      PreviewOverlay.audioOnly => const Center(
        child: BrandMessage(title: 'Solo audio', logoSize: 48),
      ),
    };
  }
}
