import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../tv/remote_keys.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import 'live_playback.dart';
import 'resume.dart' show formatDuration;
import 'tv_track_options.dart';

/// How long the controls stay up on their own.
const tvControlsDuration = Duration(seconds: 4);

/// How far Left and Right jump.
const tvSeekStep = Duration(seconds: 10);

/// How far each repeat jumps once Left or Right has been held
/// [tvFastSeekAfter].
const tvFastSeekStep = Duration(seconds: 30);

/// How long Left or Right must be held to jump [tvFastSeekStep].
const tvFastSeekAfter = Duration(seconds: 2);

/// Shortest time between two jumps of a held Left or Right: the remote
/// repeats a key about every 50 ms, far too fast to jump on each.
const tvSeekRepeatGap = Duration(milliseconds: 250);

/// How close to the end a jump may land, so holding Right does not end the
/// movie (nor start the next episode).
const tvSeekEndMargin = Duration(seconds: 2);

/// How long the bar shows where a jump goes when the player does not get
/// there sooner.
const _seekTargetTime = Duration(seconds: 1);

/// How close the position must be to a jump's target to count as there.
const _targetReached = Duration(seconds: 2);

/// Remote controls of a movie or episode on a TV, over a video without
/// media_kit controls.
///
/// OK (and play/pause) pauses and resumes; Left and Right jump
/// [tvSeekStep], and while held once every [tvSeekRepeatGap]
/// ([tvFastSeekStep] once held [tvFastSeekAfter]), never closer than
/// [tvSeekEndMargin] to the end; fast forward and rewind jump too; Up and
/// Down show the title and the progress for [tvControlsDuration] (jumps
/// show them as well); Menu opens the audio and subtitle tracks. Back
/// closes what is shown and, with nothing left, leaves the player, which
/// saves the position as on every device.
class TvVodControls extends StatefulWidget {
  /// Controls for [playback], playing [title].
  const TvVodControls({
    super.key,
    required this.playback,
    required this.title,
    this.subtitle,
    this.focusNode,
    this.onPanelChanged,
  });

  /// The playback shown.
  final LivePlayback playback;

  /// Name of the movie or episode.
  final String title;

  /// Optional second line under [title].
  final String? subtitle;

  /// The node that takes the remote keys; the player gives it back the
  /// focus after the next episode countdown. `null` makes one.
  final FocusNode? focusNode;

  /// Told whether the options are open (the player hides its error
  /// messages under them).
  final ValueChanged<bool>? onPanelChanged;

  @override
  State<TvVodControls> createState() => _TvVodControlsState();
}

class _TvVodControlsState extends State<TvVodControls> {
  late final FocusNode _root =
      widget.focusNode ??
      FocusNode(debugLabel: 'TV movie player', skipTraversal: true);

  /// Whether the title and progress are shown.
  bool _controls = false;

  /// Whether the audio and subtitle options are open.
  bool _options = false;

  /// Where the last jump went, for [_seekTargetTime] after it: the next
  /// jump starts there, as the player may not have got there yet.
  Duration? _seekTarget;

  /// Whether a repeat of a held Left or Right may jump now.
  bool _repeatMayJump = true;

  /// Whether Left or Right has been held long enough to jump faster.
  bool _fast = false;

  Timer? _hideTimer;
  Timer? _holdTimer;
  Timer? _repeatTimer;
  Timer? _targetTimer;

  Player get _player => widget.playback.player;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _holdTimer?.cancel();
    _repeatTimer?.cancel();
    _targetTimer?.cancel();
    if (widget.focusNode == null) _root.dispose();
    super.dispose();
  }

  /// Shows the controls for [tvControlsDuration], applying [also] first.
  void _showControls([VoidCallback? also]) {
    _hideTimer?.cancel();
    _hideTimer = Timer(tvControlsDuration, _hideControls);
    setState(() {
      _controls = true;
      also?.call();
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _controls = false;
      _seekTarget = null;
    });
  }

  void _setOptions(bool open) {
    if (open == _options) return;
    setState(() => _options = open);
    widget.onPanelChanged?.call(open);
    if (!open) _root.requestFocus();
  }

  void _playOrPause() {
    _player.playOrPause();
    _showControls();
  }

  /// Jumps [offset] from where the last jump went (or the position),
  /// between the start and [tvSeekEndMargin] before the end, and shows
  /// where it lands. Already there, it does not seek again.
  void _seekBy(Duration offset) {
    final state = _player.state;
    final from = _seekTarget ?? state.position;
    var target = from + offset;
    final last = state.duration - tvSeekEndMargin;
    if (state.duration > Duration.zero && target > last) {
      target = last > from ? last : from;
    }
    if (target < Duration.zero) target = Duration.zero;
    if (target != from) _player.seek(target);
    _targetTimer?.cancel();
    _targetTimer = Timer(_seekTargetTime, () {
      if (mounted) setState(() => _seekTarget = null);
    });
    _showControls(() => _seekTarget = target);
  }

  /// Left or Right, fast forward or rewind ([forward]): a press jumps [tvSeekStep]; held, it
  /// jumps again every [tvSeekRepeatGap], [tvFastSeekStep] once held
  /// [tvFastSeekAfter].
  void _seekKey(KeyEvent event, {required bool forward}) {
    if (event is KeyUpEvent) {
      _holdTimer?.cancel();
      _fast = false;
      return;
    }
    if (event is KeyDownEvent) {
      _holdTimer?.cancel();
      _fast = false;
      _holdTimer = Timer(tvFastSeekAfter, () => _fast = true);
    } else if (!_repeatMayJump) {
      return;
    }
    _repeatMayJump = false;
    _repeatTimer?.cancel();
    _repeatTimer = Timer(tvSeekRepeatGap, () => _repeatMayJump = true);
    final step = _fast ? tvFastSeekStep : tvSeekStep;
    _seekBy(forward ? step : -step);
  }

  /// The arrows while the options are closed: Left and Right jump, Up and
  /// Down show the controls. In the options they move the focus as usual.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_options) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Fast forward and rewind are handled here, not as a [SeekIntent], so a
    // held key is throttled like Left and Right.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekKey(
        event,
        forward:
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.mediaFastForward,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is! KeyUpEvent) _showControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Back: closes the options, else hides the controls.
  void _back() {
    if (_options) {
      _setOptions(false);
    } else {
      _hideControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return PopScope(
      canPop: !_controls && !_options,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _playOrPause(),
          ),
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(
            onInvoke: (_) => _playOrPause(),
          ),
          QuickOptionsIntent: CallbackAction<QuickOptionsIntent>(
            onInvoke: (_) => _setOptions(!_options),
          ),
        },
        child: Focus(
          focusNode: _root,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controls)
                Positioned(
                  left: padding.left,
                  right: padding.right,
                  bottom: padding.bottom,
                  child: _ControlsBar(
                    player: _player,
                    title: widget.title,
                    subtitle: widget.subtitle,
                    seekTarget: _seekTarget,
                  ),
                ),
              if (_options)
                Positioned(
                  right: padding.right,
                  top: padding.top,
                  bottom: padding.bottom,
                  child: FocusTraversalGroup(
                    child: TvTrackOptions(player: _player),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar at the bottom: the title, play or pause, the position (or where
/// the last jump goes, [seekTarget], until the player gets near it) and the
/// progress over the length.
class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.player,
    required this.title,
    required this.subtitle,
    required this.seekTarget,
  });

  final Player player;
  final String title;
  final String? subtitle;
  final Duration? seekTarget;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted);
    return Container(
      key: const ValueKey('tv-vod-controls'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: tvPanelColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? Duration.zero;
              final target = seekTarget;
              // The jump's target until the player gets there.
              final position =
                  target == null || (playing - target).abs() <= _targetReached
                  ? playing
                  : target;
              final duration = player.state.duration;
              final share = duration > Duration.zero
                  ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    )
                  : 0.0;
              return Row(
                spacing: 16,
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, playing) => Icon(
                      playing.data ?? false ? Icons.pause : Icons.play_arrow,
                      size: 32,
                    ),
                  ),
                  Text(formatDuration(position), style: text.titleMedium),
                  Expanded(
                    child: GradientProgress(
                      key: const ValueKey('tv-vod-progress'),
                      value: share,
                      height: 6,
                    ),
                  ),
                  Text(formatDuration(duration), style: muted),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
