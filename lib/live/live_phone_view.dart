import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../browse/catalog_images.dart';
import '../catalog/catalog_models.dart';
import '../epg/programme.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/brand_state.dart';
import '../ui/focus_card.dart';
import 'live_tv_screen.dart';

const _rowHeight = 64.0;

/// Directo on a phone (or a portrait tablet), held upright for zapping: a
/// top bar with the group, "Guía" and "Orden"; the preview pinned at full
/// width below it; and under that, scrolling, the selected channel's
/// programme for the rest of the day and the group's channels (or the guide
/// grid, when "Guía" is on).
///
/// Tapping the preview opens full screen. The state lives in `LiveTvScreen`;
/// this view only lays it out.
class LivePhoneView extends StatelessWidget {
  const LivePhoneView({
    super.key,
    required this.groupName,
    required this.onPickGroup,
    required this.guideGrid,
    required this.onToggleGuideGrid,
    required this.onSort,
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
    required this.channels,
    required this.names,
    required this.guide,
    required this.favorites,
    required this.onChannel,
    required this.onToggleChannelFavorite,
    required this.guideView,
    this.clock = DateTime.now,
  });

  /// Name of the group shown, on the group button.
  final String groupName;
  final VoidCallback onPickGroup;

  /// Whether the guide grid replaces the schedule and the channel list.
  final bool guideGrid;
  final VoidCallback onToggleGuideGrid;

  /// Opens the sort sheet; `null` hides "Orden" (favorites and recents).
  final VoidCallback? onSort;

  /// The channel in the preview, if any.
  final Channel? channel;
  final String channelName;

  /// Programme on air on [channel], if the guide has it.
  final Programme? now;

  /// [channel]'s programmes after [now] today.
  final List<Programme> upcoming;
  final VideoController? controller;

  /// The preview did not start in time.
  final bool failed;
  final bool muted;

  /// Whether [channel] is a favorite.
  final bool favorite;
  final VoidCallback onFullScreen;
  final VoidCallback onToggleSound;
  final VoidCallback? onToggleFavorite;

  /// The group's channels to list, already filtered.
  final List<Channel> channels;

  /// Display names by channel key.
  final Map<String, String> names;

  /// Programme on air and next one by guide id.
  final Map<String, (Programme?, Programme?)> guide;

  /// Keys of the favorite channels.
  final Set<String> favorites;
  final ValueChanged<Channel> onChannel;
  final ValueChanged<Channel> onToggleChannelFavorite;

  /// The guide grid, shown instead of the schedule and list when
  /// [guideGrid] is on.
  final Widget guideView;

  /// The current time, for the progress bars (fixed in tests).
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Upright: everything in one column. Sideways (a phone just back
        // from full screen): preview and schedule beside the list.
        if (constraints.maxWidth <= constraints.maxHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              _buildPreview(),
              Expanded(
                child: guideGrid ? guideView : _buildList(withSchedule: true),
              ),
            ],
          );
        }
        final schedule = _buildSchedule();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth * 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(),
                  _buildPreview(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: schedule ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: guideGrid ? guideView : _buildList(withSchedule: false),
            ),
          ],
        );
      },
    );
  }

  /// The 16:9 preview; tapping it opens full screen.
  Widget _buildPreview() {
    return GestureDetector(
      onTap: channel == null ? null : onFullScreen,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: channel == null
            ? const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Text(
                    'Elige un canal',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            : LivePreviewBox(controller: controller, failed: failed, radius: 0),
      ),
    );
  }

  /// The schedule of the channel in the preview, or `null` without one.
  Widget? _buildSchedule() {
    final current = channel;
    if (current == null) return null;
    return PhoneSchedule(
      channel: current,
      channelName: channelName,
      now: now,
      upcoming: upcoming,
      muted: muted,
      favorite: favorite,
      onToggleSound: onToggleSound,
      onToggleFavorite: onToggleFavorite,
      clock: clock,
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Elegir grupo',
              child: TextButton.icon(
                onPressed: onPickGroup,
                icon: const Icon(Icons.arrow_drop_down),
                label: Text(
                  groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              ),
            ),
          ),
          // Icons only: labels would not fit beside the group on a phone.
          guideGrid
              ? IconButton.filled(
                  tooltip: 'Guía',
                  onPressed: onToggleGuideGrid,
                  icon: const Icon(Icons.calendar_month),
                )
              : IconButton.outlined(
                  tooltip: 'Guía',
                  onPressed: onToggleGuideGrid,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
          if (onSort != null) ...[
            const SizedBox(width: 4),
            IconButton.outlined(
              tooltip: 'Orden',
              onPressed: onSort,
              icon: const Icon(Icons.sort),
            ),
          ],
        ],
      ),
    );
  }

  /// The channel rows, below the schedule when [withSchedule].
  Widget _buildList({required bool withSchedule}) {
    final current = channel;
    final schedule = withSchedule ? _buildSchedule() : null;
    return CustomScrollView(
      slivers: [
        if (schedule != null) SliverToBoxAdapter(child: schedule),
        if (channels.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: BrandMessage(title: 'No hay canales en este grupo'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            sliver: SliverFixedExtentList.builder(
              itemExtent: _rowHeight,
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final item = channels[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: PhoneChannelRow(
                    number: index + 1,
                    channel: item,
                    name: names[item.key] ?? item.name,
                    now: guide[item.epgId]?.$1,
                    selected: item.key == current?.key,
                    favorite: favorites.contains(item.key),
                    onTap: () => onChannel(item),
                    onToggleFavorite: () => onToggleChannelFavorite(item),
                    clock: clock,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The phone's schedule of the channel in the preview: its name, favorite
/// and sound buttons, the programme on air with its progress and the rest
/// of today; "Sin guía" when the guide has nothing for it.
class PhoneSchedule extends StatelessWidget {
  const PhoneSchedule({
    super.key,
    required this.channel,
    required this.channelName,
    required this.now,
    required this.upcoming,
    required this.muted,
    required this.favorite,
    required this.onToggleSound,
    required this.onToggleFavorite,
    this.clock = DateTime.now,
  });

  final Channel channel;
  final String channelName;
  final Programme? now;
  final List<Programme> upcoming;
  final bool muted;
  final bool favorite;
  final VoidCallback onToggleSound;
  final VoidCallback? onToggleFavorite;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mutedText = text.bodySmall?.copyWith(color: AppColors.textMuted);
    final now = this.now;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: ChannelLogo(url: channel.iconUrl),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ),
              IconButton(
                tooltip: favorite
                    ? 'Quitar de favoritos'
                    : 'Añadir a favoritos',
                onPressed: onToggleFavorite,
                icon: Icon(
                  favorite ? Icons.star : Icons.star_border,
                  color: favorite ? AccentPalette.of(context).accent : null,
                ),
              ),
              IconButton(
                tooltip: muted ? 'Activar sonido' : 'Silenciar',
                onPressed: onToggleSound,
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (now == null && upcoming.isEmpty)
            Text('Sin guía', style: mutedText)
          else
            OnAirDetails(
              now: now,
              upcoming: upcoming,
              titleStyle: text.titleLarge,
              titleMaxLines: 2,
              clock: clock,
            ),
        ],
      ),
    );
  }
}

/// A channel row narrow enough for a phone: number, logo, name with the
/// programme on air below it, and the favorite star.
class PhoneChannelRow extends StatelessWidget {
  const PhoneChannelRow({
    super.key,
    required this.number,
    required this.channel,
    required this.name,
    required this.now,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.clock = DateTime.now,
  });

  final int number;
  final Channel channel;
  final String name;

  /// Programme on air, if the guide has it.
  final Programme? now;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted);
    final now = this.now;
    return FocusCard(
      grow: false,
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('$number', style: muted, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ChannelLogo(url: channel.iconUrl),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  if (now != null) ...[
                    Text(
                      now.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                    const SizedBox(height: 2),
                    GradientProgress(
                      value: elapsedShare(now, clock().toUtc()),
                      height: 2,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onPressed: onToggleFavorite,
              icon: Icon(
                favorite ? Icons.star : Icons.star_border,
                color: favorite
                    ? AccentPalette.of(context).accent
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to choose the group shown on a phone, like the sort sheets.
/// [groups] are `(id, label)` pairs; returns the chosen id, or `null` when
/// dismissed. "Organizar grupos" closes it and calls [onOrganize].
Future<String?> showGroupSheet(
  BuildContext context, {
  required List<(String, String)> groups,
  required String? selectedId,
  required VoidCallback onOrganize,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                  onPressed: () {
                    Navigator.pop(context);
                    onOrganize();
                  },
                ),
              ],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (id, label) in groups)
                    ListTile(
                      selected: id == selectedId,
                      title: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
