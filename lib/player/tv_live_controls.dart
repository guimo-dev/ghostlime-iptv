import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../catalog/catalog_models.dart';
import '../epg/guide_grid.dart' show formatClock;
import '../epg/programme.dart';
import '../tv/remote_keys.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/focus_card.dart';
import 'channel_number.dart';
import 'live_playback.dart';
import 'player_screen.dart' show ChannelStep;

/// How long the info bar stays up on its own.
const tvInfoDuration = Duration(seconds: 5);

/// How long typed channel digits wait for the next one before jumping.
const tvDigitWait = Duration(milliseconds: 1500);

/// How long "Canal N no existe" stays up.
const _messageDuration = Duration(seconds: 3);

/// Most digits a channel number can have.
const _maxDigits = 4;

const _channelRowHeight = 56.0;
const _panelColor = Color(0xE60D0E15);

/// What the TV live player reads from Directo and asks it to do: the
/// channel playing, the groups and their channels (as Directo shows them,
/// parental filters applied) and zapping to a channel. Only
/// `LivePlayback.play`, through Directo, opens streams.
abstract interface class TvLiveSource {
  /// The channel playing now.
  Channel? get currentChannel;

  /// Id of the group the channel playing belongs to in Directo.
  String? get currentGroupId;

  /// The groups to choose from, as `(id, label)`.
  List<(String, String)> get groupChoices;

  /// The channels of group [groupId] that may be shown, in order.
  List<Channel> channelsOf(String groupId);

  /// The name to show for [channel].
  String channelName(Channel channel);

  /// The programmes on air and next of [channels], by guide id.
  Map<String, (Programme?, Programme?)> guideOf(List<Channel> channels);

  /// The current time (fixed in tests).
  DateTime now();

  /// Plays [channel] of group [groupId], which becomes Directo's group.
  void playChannel(Channel channel, String groupId);
}

/// What the TV live player shows over the picture.
enum _Layer { none, info, list, options }

/// TiviMate-style remote controls of the live player on a TV, over a video
/// without media_kit controls.
///
/// Up and Down (and CH+/CH-) zap to the previous and next channel of the
/// group; OK shows the info bar (channel, programme on air with its progress
/// and the next one), and OK again the channel list; Left opens the list
/// with the groups; Right and Menu the audio and subtitle tracks; digits
/// jump to a channel number after [tvDigitWait]; Back closes one layer at a
/// time and, with none left, leaves the player.
///
/// Without a [source] (a channel played from Inicio or the search) there is
/// nothing to zap through: only the info bar and the tracks work.
class TvLiveControls extends StatefulWidget {
  /// Controls for [playback], playing [title].
  const TvLiveControls({
    super.key,
    required this.playback,
    required this.title,
    this.subtitle,
    this.source,
    this.onChannelStep,
  });

  /// The playback shown (its player gives the tracks).
  final LivePlayback playback;

  /// Name shown without a [source].
  final String title;

  /// Programme on air shown without a [source].
  final String? subtitle;

  /// Directo's channels; `null` when not played from Directo.
  final TvLiveSource? source;

  /// Zaps to the channel a number of places away (Directo's).
  final ChannelStep? onChannelStep;

  @override
  State<TvLiveControls> createState() => _TvLiveControlsState();
}

class _TvLiveControlsState extends State<TvLiveControls> {
  final _root = FocusNode(debugLabel: 'TV live player', skipTraversal: true);
  _Layer _layer = _Layer.none;

  /// Whether the channel list shows the groups column.
  bool _listGroups = false;

  /// Group whose channels the list shows.
  String? _listGroupId;

  /// Whether the channel column takes the focus when it appears.
  bool _focusChannels = true;

  /// Channel digits typed so far.
  String _typed = '';

  /// A short notice, such as a number without a channel.
  String? _message;

  Timer? _infoTimer;
  Timer? _digitTimer;
  Timer? _messageTimer;

  @override
  void dispose() {
    _infoTimer?.cancel();
    _digitTimer?.cancel();
    _messageTimer?.cancel();
    _root.dispose();
    super.dispose();
  }

  /// Hides whatever is shown and gives the focus back to the player.
  void _close() {
    _infoTimer?.cancel();
    setState(() => _layer = _Layer.none);
    _root.requestFocus();
  }

  /// Shows the info bar for [tvInfoDuration].
  void _showInfo() {
    _infoTimer?.cancel();
    _infoTimer = Timer(tvInfoDuration, () {
      if (mounted && _layer == _Layer.info) _close();
    });
    setState(() => _layer = _Layer.info);
    _root.requestFocus();
  }

  /// Opens the channel list on the group playing, with the groups column
  /// (and the focus in it) when [groups] is set.
  void _openList({required bool groups}) {
    final groupId = widget.source?.currentGroupId;
    if (groupId == null) return;
    _infoTimer?.cancel();
    setState(() {
      _layer = _Layer.list;
      _listGroups = groups;
      _listGroupId = groupId;
      _focusChannels = !groups;
    });
  }

  void _openOptions() {
    _infoTimer?.cancel();
    setState(() => _layer = _Layer.options);
  }

  /// Zaps [step] channels away and shows where it landed.
  void _step(int step) {
    if (widget.onChannelStep?.call(step) == null) return;
    _showInfo();
  }

  /// Plays [channel] of [groupId] (when it is not the one playing).
  void _play(Channel channel, String groupId) {
    final source = widget.source;
    if (source == null) return;
    if (channel.key != source.currentChannel?.key ||
        groupId != source.currentGroupId) {
      source.playChannel(channel, groupId);
    }
    _showInfo();
  }

  /// Adds [digit] to the number typed and waits [tvDigitWait] for more.
  void _typeDigit(int digit) {
    if (widget.source == null) return;
    _digitTimer?.cancel();
    setState(() {
      _typed = _typed.length < _maxDigits ? '$_typed$digit' : '$digit';
    });
    _digitTimer = Timer(tvDigitWait, _jumpToTyped);
  }

  /// Plays the channel with the number typed, or says it does not exist.
  void _jumpToTyped() {
    if (!mounted || _typed.isEmpty) return;
    final number = int.parse(_typed);
    setState(() => _typed = '');
    final source = widget.source;
    final groupId = source?.currentGroupId;
    if (source == null || groupId == null) return;
    final channels = source.channelsOf(groupId);
    final index = channelIndexForNumber(number, channels);
    if (index == null) {
      _messageTimer?.cancel();
      setState(() => _message = 'Canal $number no existe');
      _messageTimer = Timer(_messageDuration, () {
        if (mounted) setState(() => _message = null);
      });
      return;
    }
    _play(channels[index], groupId);
  }

  /// OK on the player: the info bar, or the list when the bar is up.
  void _activate() {
    switch (_layer) {
      case _Layer.none:
        _showInfo();
      case _Layer.info:
        _openList(groups: false);
      case _Layer.list:
      case _Layer.options:
        break;
    }
  }

  /// Back: cancels the number being typed, else closes the top layer.
  void _back() {
    _digitTimer?.cancel();
    if (_typed.isNotEmpty) {
      setState(() => _typed = '');
      return;
    }
    _close();
  }

  /// The arrows while nothing focusable is shown: Up and Down zap, Left
  /// opens the list with the groups and Right the tracks. In the list and
  /// the options they move the focus as usual.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_layer == _Layer.list || _layer == _Layer.options) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _step(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent) _openList(groups: true);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _openOptions();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final source = widget.source;
    final listGroupId = _listGroupId;
    return PopScope(
      canPop: _layer == _Layer.none && _typed.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _activate(),
          ),
          ChannelStepIntent: CallbackAction<ChannelStepIntent>(
            onInvoke: (intent) => _step(intent.step),
          ),
          ChannelDigitIntent: CallbackAction<ChannelDigitIntent>(
            onInvoke: (intent) => _typeDigit(intent.digit),
          ),
          QuickOptionsIntent: CallbackAction<QuickOptionsIntent>(
            onInvoke: (_) =>
                _layer == _Layer.options ? _close() : _openOptions(),
          ),
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(
            onInvoke: (_) => widget.playback.player.playOrPause(),
          ),
        },
        child: Focus(
          focusNode: _root,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_layer == _Layer.info)
                Positioned(
                  left: padding.left,
                  right: padding.right,
                  bottom: padding.bottom,
                  child: _InfoBar(
                    source: source,
                    title: widget.title,
                    subtitle: widget.subtitle,
                  ),
                ),
              if (_layer == _Layer.list &&
                  source != null &&
                  listGroupId != null)
                Positioned(
                  left: padding.left,
                  top: padding.top,
                  bottom: padding.bottom,
                  child: FocusTraversalGroup(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_listGroups)
                          _GroupColumn(
                            groups: source.groupChoices,
                            selectedId: listGroupId,
                            onGroup: (id) => setState(() {
                              _listGroupId = id;
                              _focusChannels = true;
                            }),
                          ),
                        _ChannelColumn(
                          key: ValueKey('tv-channels-$listGroupId'),
                          source: source,
                          groupId: listGroupId,
                          takeFocus: _focusChannels,
                          onChannel: (channel) => _play(channel, listGroupId),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_layer == _Layer.options)
                Positioned(
                  right: padding.right,
                  top: padding.top,
                  bottom: padding.bottom,
                  child: FocusTraversalGroup(
                    child: _OptionsPanel(player: widget.playback.player),
                  ),
                ),
              if (_typed.isNotEmpty || _message != null)
                Positioned(
                  right: padding.right,
                  top: padding.top,
                  child: _Notice(
                    key: ValueKey(_typed.isNotEmpty ? 'tv-typed' : 'tv-msg'),
                    text: _typed.isNotEmpty ? _typed : _message!,
                    big: _typed.isNotEmpty,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar at the bottom: number and name of the channel, the programme on
/// air with its times and progress, and the next one ("Sin guía" without
/// guide).
class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.source, required this.title, this.subtitle});

  final TvLiveSource? source;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted);
    final accent = AccentPalette.of(context).accent;
    final source = this.source;
    final channel = source?.currentChannel;
    final groupId = source?.currentGroupId;
    final number = channel == null || groupId == null
        ? 0
        : channelNumberOf(channel, source!.channelsOf(groupId));
    final (now, next) = channel == null
        ? (null, null)
        : source!.guideOf([channel])[channel.epgId] ?? (null, null);
    final time = source?.now() ?? DateTime.now();
    return Container(
      key: const ValueKey('tv-info'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Row(
            spacing: 16,
            children: [
              if (number > 0)
                Text(
                  '$number',
                  style: text.headlineMedium?.copyWith(color: accent),
                ),
              Expanded(
                child: Text(
                  channel == null ? title : source!.channelName(channel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall,
                ),
              ),
            ],
          ),
          if (now != null) ...[
            Row(
              spacing: 12,
              children: [
                Text(
                  '${formatClock(now.start)}–${formatClock(now.stop)}',
                  style: muted,
                ),
                Expanded(
                  child: Text(
                    now.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            GradientProgress(
              key: const ValueKey('tv-info-progress'),
              value: _share(now, time),
            ),
          ] else if (channel == null && subtitle != null)
            Text(subtitle!, style: text.titleMedium)
          else
            Text('Sin guía', style: muted),
          if (next != null)
            Text(
              'A continuación: ${formatClock(next.start)} ${next.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
        ],
      ),
    );
  }

  /// How much of [programme] has gone by at [time], 0 to 1.
  static double _share(Programme programme, DateTime time) {
    final total = programme.stop.difference(programme.start).inSeconds;
    final done = time.toUtc().difference(programme.start).inSeconds;
    return total > 0 ? (done / total).clamp(0.0, 1.0) : 0;
  }
}

/// The groups column of the channel list; OK on a group shows its
/// channels. The group shown takes the focus when it appears.
class _GroupColumn extends StatefulWidget {
  const _GroupColumn({
    required this.groups,
    required this.selectedId,
    required this.onGroup,
  });

  final List<(String, String)> groups;
  final String selectedId;
  final ValueChanged<String> onGroup;

  @override
  State<_GroupColumn> createState() => _GroupColumnState();
}

class _GroupColumnState extends State<_GroupColumn> {
  final _selectedNode = FocusNode(debugLabel: 'TV group shown');
  late final _scroll = ScrollController(
    initialScrollOffset: _offsetFor(
      widget.groups.indexWhere((g) => g.$1 == widget.selectedId),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectedNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _selectedNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('tv-group-list'),
      width: 260,
      decoration: const BoxDecoration(
        color: _panelColor,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemExtent: _channelRowHeight,
        itemCount: widget.groups.length,
        itemBuilder: (context, index) {
          final (id, label) = widget.groups[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FocusCard(
              grow: false,
              selected: id == widget.selectedId,
              focusNode: id == widget.selectedId ? _selectedNode : null,
              onTap: () => widget.onGroup(id),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The channels of one group with their number and programme on air,
/// scrolled to (and, with [takeFocus], focused on) the channel playing, or
/// the first one when it is in another group.
class _ChannelColumn extends StatefulWidget {
  const _ChannelColumn({
    super.key,
    required this.source,
    required this.groupId,
    required this.takeFocus,
    required this.onChannel,
  });

  final TvLiveSource source;
  final String groupId;
  final bool takeFocus;
  final ValueChanged<Channel> onChannel;

  @override
  State<_ChannelColumn> createState() => _ChannelColumnState();
}

class _ChannelColumnState extends State<_ChannelColumn> {
  late final List<Channel> _channels = widget.source.channelsOf(widget.groupId);
  late final _guide = widget.source.guideOf(_channels);
  late final int _target = () {
    final current = widget.source.currentChannel?.key;
    final index = _channels.indexWhere((c) => c.key == current);
    return index < 0 ? 0 : index;
  }();
  final _targetNode = FocusNode(debugLabel: 'TV channel to focus');
  late final _scroll = ScrollController(
    initialScrollOffset: _offsetFor(_target),
  );

  @override
  void initState() {
    super.initState();
    if (widget.takeFocus) _focusTarget();
  }

  @override
  void didUpdateWidget(_ChannelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.takeFocus && !oldWidget.takeFocus) _focusTarget();
  }

  void _focusTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _targetNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _targetNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted);
    final currentKey = widget.source.currentChannel?.key;
    return Container(
      key: const ValueKey('tv-channel-list'),
      width: 440,
      color: _panelColor,
      child: _channels.isEmpty
          ? Center(child: Text('No hay canales en este grupo', style: muted))
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemExtent: _channelRowHeight,
              itemCount: _channels.length,
              itemBuilder: (context, index) {
                final channel = _channels[index];
                final now = _guide[channel.epgId]?.$1;
                return Padding(
                  key: ValueKey('tv-channel-${channel.key}'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: FocusCard(
                    grow: false,
                    selected: channel.key == currentKey,
                    focusNode: index == _target ? _targetNode : null,
                    onTap: () => widget.onChannel(channel),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        spacing: 12,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${index + 1}',
                              style: muted,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.source.channelName(channel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (now != null)
                                  Text(
                                    now.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: muted,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Scroll offset that shows row [index] with two rows above it.
double _offsetFor(int index) =>
    index <= 2 ? 0 : (index - 2) * _channelRowHeight;

/// The quick options: the audio and subtitle tracks of [player]; OK picks
/// one.
class _OptionsPanel extends StatefulWidget {
  const _OptionsPanel({required this.player});

  final Player player;

  @override
  State<_OptionsPanel> createState() => _OptionsPanelState();
}

class _OptionsPanelState extends State<_OptionsPanel> {
  final _firstNode = FocusNode(debugLabel: 'TV first option');

  /// Tracks picked here, shown as selected before the player reports them.
  String? _audioId;
  String? _subtitleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstNode.dispose();
    super.dispose();
  }

  /// The label of an audio or subtitle track.
  static String _label(String id, String? title, String? language) =>
      switch (id) {
        'auto' => 'Automático',
        'no' => 'Desactivados',
        _ => title ?? language ?? 'Pista $id',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = widget.player.state;
    final audioId = _audioId ?? state.track.audio.id;
    final subtitleId = _subtitleId ?? state.track.subtitle.id;
    final audio = [
      for (final track in state.tracks.audio)
        if (track.id != 'no') track,
    ];
    final subtitles = state.tracks.subtitle;
    var first = true;
    Widget option(String label, bool selected, VoidCallback onTap) {
      final node = first ? _firstNode : null;
      first = false;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FocusCard(
          grow: false,
          selected: selected,
          focusNode: node,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                Icon(
                  selected ? Icons.check : null,
                  size: 18,
                  color: AccentPalette.of(context).accent,
                ),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('tv-options'),
      width: 340,
      color: _panelColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Audio', style: text.titleMedium),
          if (audio.isEmpty)
            Text('Sin pistas', style: text.bodySmall)
          else
            for (final track in audio)
              option(
                _label(track.id, track.title, track.language),
                track.id == audioId,
                () {
                  setState(() => _audioId = track.id);
                  widget.player.setAudioTrack(track);
                },
              ),
          const SizedBox(height: 16),
          Text('Subtítulos', style: text.titleMedium),
          if (subtitles.isEmpty)
            Text('Sin pistas', style: text.bodySmall)
          else
            for (final track in subtitles)
              option(
                _label(track.id, track.title, track.language),
                track.id == subtitleId,
                () {
                  setState(() => _subtitleId = track.id);
                  widget.player.setSubtitleTrack(track);
                },
              ),
        ],
      ),
    );
  }
}

/// A box at the top right: the channel number being typed ([big]) or a
/// short notice.
class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, required this.big});

  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: big
            ? theme.displaySmall?.copyWith(
                color: AccentPalette.of(context).accent,
              )
            : theme.titleMedium,
      ),
    );
  }
}
