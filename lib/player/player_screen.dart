import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../ui/app_theme.dart';
import '../ui/brand_state.dart';
import '../ui/tv_device.dart';
import 'live_playback.dart';
import 'mobile_gestures.dart';
import 'mpv_options.dart';
import 'playback_log.dart';
import 'stream_info.dart';
import 'tv_live_controls.dart';

/// How often playback progress is reported while playing.
const progressInterval = Duration(seconds: 10);

/// Seconds shown before the next episode starts by itself.
const nextEpisodeCountdown = 10;

/// Whether the player's [position] is real progress worth saving: both values
/// are known and, when resuming from [start], playback has reached it (a
/// slow start would otherwise overwrite the saved point with ~0).
bool progressReady(Duration position, Duration duration, Duration? start) {
  if (position <= Duration.zero || duration <= Duration.zero) return false;
  return start == null || position >= start - const Duration(seconds: 5);
}

/// Changes the live channel by [step] places in its group (+1 the next one)
/// and returns the title and subtitle to show, or `null` when there is no
/// other channel.
typedef ChannelStep = ({String title, String? subtitle})? Function(int step);

/// Full-screen player for one stream, with a toggleable technical info overlay.
///
/// With [shared] it shows that playback, already playing, and leaves it
/// playing when it closes (Directo's preview carries on). Otherwise its own
/// player lives exactly as long as this screen: leaving it closes the
/// connection, which matters for providers that allow a single connection.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    this.shared,
    required this.url,
    required this.title,
    this.userAgent,
    this.startPosition,
    this.onProgress,
    this.subtitle,
    this.isLive = false,
    this.onNext,
    this.nextTitle,
    this.onChannelStep,
    this.tvLive,
    this.startTimeout = streamStartTimeout,
    this.createPlayer,
  });

  /// Playback owned by someone else (Directo); this screen neither opens
  /// nor closes it, so [url], [userAgent], [startPosition] and
  /// [startTimeout] are not used. Its owner must outlive this screen's
  /// route: the screen keeps using it until the route is gone.
  final LivePlayback? shared;

  final String url;
  final String title;

  /// User-Agent sent with the stream request; `null` keeps mpv's default.
  final String? userAgent;

  /// Where to start playing (resume); `null` starts at the beginning.
  final Duration? startPosition;

  /// Called every [progressInterval] and when leaving, with the current
  /// position and total duration (VOD only; zero duration is never reported).
  final void Function(Duration position, Duration duration)? onProgress;

  /// Optional second line under the title, such as the programme on air.
  final String? subtitle;

  /// Live streams are reopened when they end or fail (if the setting is on).
  final bool isLive;

  /// Starts the next episode, replacing this screen. When set, finishing
  /// playback shows a countdown to it.
  final VoidCallback? onNext;

  /// Title of the next episode, shown in the countdown.
  final String? nextTitle;

  /// Zaps the [shared] live playback to a neighbouring channel; on phones
  /// and tablets a vertical swipe calls it.
  final ChannelStep? onChannelStep;

  /// Directo's channels for the remote controls of a live stream on a TV
  /// (the list, the groups and the channel numbers).
  final TvLiveSource? tvLive;

  /// How long the stream may take to start before an error replaces the
  /// loading spinner (shorter in tests).
  final Duration startTimeout;

  /// Creates the player of this screen's own playback; `null` uses
  /// media_kit (tests pass a fake). Not used with [shared].
  final PlayerFactory? createPlayer;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AppSettings _settings = SettingsScope.read(context).value;
  late final PlaybackLog? _log = PlaybackLogScope.read(context);
  late final LivePlayback _playback =
      widget.shared ??
      LivePlayback(
        settings: () => _settings,
        log: _log,
        startTimeout: widget.startTimeout,
        createPlayer: widget.createPlayer,
      );

  /// Whether this screen created [_playback] and must close it.
  bool get _ownsPlayback => widget.shared == null;
  StreamSubscription<bool>? _completedSubscription;
  Timer? _infoTimer;
  Timer? _progressTimer;
  Timer? _countdownTimer;

  /// Whether playback has reached the resume point, so progress is real.
  bool _resumed = false;
  StreamInfo _info = const StreamInfo();
  bool _showInfo = false;

  /// Set once the screen is leaving.
  bool _stopped = false;

  /// Seconds left before the next episode, or `null` when not counting down.
  int? _secondsToNext;

  /// Handles the app going to the background and back.
  late final AppLifecycleListener _lifecycle;

  /// The app went to the background while this screen played its own
  /// stream.
  bool _wentToBackground = false;

  /// Title and subtitle shown; zapping changes them.
  late String _title = widget.title;
  late String? _subtitle = widget.subtitle;

  @override
  void initState() {
    super.initState();
    if (_ownsPlayback) {
      _playback.openUrl(
        widget.url,
        isLive: widget.isLive,
        userAgent: widget.userAgent,
        start: widget.startPosition,
      );
    }
    _playback.addListener(_onPlaybackChanged);
    _lifecycle = AppLifecycleListener(
      onPause: _onAppPaused,
      onResume: _onAppResumed,
    );
    if (widget.onNext != null) {
      _completedSubscription = _playback.player.stream.completed.listen((
        completed,
      ) {
        if (completed && !widget.isLive) _startCountdown();
      });
    }
    if (widget.onProgress != null) {
      _progressTimer = Timer.periodic(
        progressInterval,
        (_) => _reportProgress(),
      );
    }
    _infoTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshInfo(),
    );
  }

  /// In the background media_kit pauses the video. A live stream of this
  /// screen's own would stay frozen with its connection open: close it. A
  /// shared one is Directo's to handle, and a video just stays paused.
  void _onAppPaused() {
    if (!_ownsPlayback || _stopped) return;
    _wentToBackground = true;
    if (widget.isLive) _playback.stop();
  }

  /// Back from the background: a live stream stopped there opens again, and
  /// so does a video whose start timed out while away (paused, it could
  /// never start). A paused video waits for the user.
  void _onAppResumed() {
    if (!_wentToBackground || _stopped) return;
    _wentToBackground = false;
    if (!widget.isLive && !_playback.startFailed) return;
    _playback.openUrl(
      widget.url,
      isLive: widget.isLive,
      userAgent: widget.userAgent,
      start: widget.startPosition,
    );
  }

  /// Repaints when the playback fails to start or reports an error.
  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  /// Shows the next-episode countdown (once per playback).
  void _startCountdown() {
    if (_stopped || _secondsToNext != null) return;
    setState(() => _secondsToNext = nextEpisodeCountdown);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_secondsToNext ?? 0) - 1;
      if (left <= 0) {
        timer.cancel();
        _goNext();
      } else if (mounted) {
        setState(() => _secondsToNext = left);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsToNext = null);
  }

  /// Saves progress, closes the stream and hands over to the next episode.
  Future<void> _goNext() async {
    if (_stopped) return;
    _stopForLeaving();
    _reportProgress();
    await _playback.stop();
    widget.onNext?.call();
  }

  /// Cancels this screen's timers; used when leaving the screen.
  void _stopForLeaving() {
    _stopped = true;
    _infoTimer?.cancel();
    _progressTimer?.cancel();
    _countdownTimer?.cancel();
  }

  /// Sends the current position to [PlayerScreen.onProgress] when known.
  void _reportProgress() {
    if (widget.onProgress == null) return;
    final state = _playback.player.state;
    final position = state.position;
    final duration = state.duration;
    if (_resumed || progressReady(position, duration, widget.startPosition)) {
      _resumed = position > Duration.zero && duration > Duration.zero;
      if (_resumed) widget.onProgress?.call(position, duration);
    }
  }

  @override
  void dispose() {
    _stopForLeaving();
    _completedSubscription?.cancel();
    _lifecycle.dispose();
    _playback.removeListener(_onPlaybackChanged);
    if (_ownsPlayback) _playback.dispose();
    super.dispose();
  }

  /// Reads the current mpv properties into [_info].
  Future<void> _refreshInfo() async {
    final info = await _playback.readInfo();
    if (info != null && mounted) setState(() => _info = info);
  }

  /// Zaps to the channel [step] places away and shows its name.
  void _stepChannel(int step) {
    final shown = widget.onChannelStep?.call(step);
    if (shown == null) return;
    setState(() {
      _title = shown.title;
      _subtitle = shown.subtitle;
    });
  }

  /// Moves a movie or episode by [offset], within its length.
  void _seekBy(Duration offset) {
    final state = _playback.player.state;
    var target = state.position + offset;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    if (target < Duration.zero) target = Duration.zero;
    _playback.player.seek(target);
  }

  void _toggleInfo() => setState(() => _showInfo = !_showInfo);

  /// A live stream on a TV: no media_kit controls nor app bar, the remote
  /// drives [TvLiveControls] instead.
  bool get _tvLive => isTvDevice && widget.isLive;

  /// The TV channel list or options are open: error messages hide under
  /// them.
  bool _tvPanelOpen = false;

  /// Handles `I` (toggle info) and `Esc` (go back).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      _toggleInfo();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final error = _playback.error;
    final accent = AccentPalette.of(context).accent;
    final desktopControls = desktopControlsTheme(accent);
    final mobileControls = mobileControlsTheme(accent);
    // Stop as soon as the pop starts, not when the route is disposed after
    // its exit animation: otherwise opening the next channel quickly can
    // overlap two connections on single-connection accounts. A shared
    // playback goes on in the screen below.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _stopForLeaving();
          _reportProgress();
          if (_ownsPlayback) _playback.stop();
        }
      },
      child: Focus(
        // On a TV the live controls take the focus.
        autofocus: !_tvLive,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: _tvLive
              ? null
              : AppBar(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  title: _subtitle == null
                      ? Text(_title)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_title),
                            Text(
                              _subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                  actions: [
                    IconButton(
                      tooltip: 'Info del stream (I)',
                      icon: Icon(_showInfo ? Icons.info : Icons.info_outline),
                      onPressed: _toggleInfo,
                    ),
                  ],
                ),
          body: Stack(
            children: [
              MaterialDesktopVideoControlsTheme(
                normal: desktopControls,
                fullscreen: desktopControls,
                child: MaterialVideoControlsTheme(
                  normal: mobileControls,
                  fullscreen: mobileControls,
                  child: MobileGestures(
                    live: widget.isLive,
                    levels: _settings.volumeBrightnessGestures,
                    volume: () => _playback.volume,
                    onVolume: _playback.setVolume,
                    onChannelStep: widget.onChannelStep == null
                        ? null
                        : _stepChannel,
                    onSeek: widget.isLive ? null : _seekBy,
                    child: Video(
                      // A new controller (new player) needs a new Video state.
                      key: ObjectKey(_playback.controller),
                      controller: _playback.controller,
                      fit: BoxFit.contain,
                      controls: _tvLive
                          ? NoVideoControls
                          : AdaptiveVideoControls,
                    ),
                  ),
                ),
              ),
              if (_playback.startFailed && !_tvPanelOpen)
                Center(
                  child: _StartFailedMessage(
                    what: widget.isLive ? 'el canal' : 'el vídeo',
                    timeout: _playback.startTimeout,
                  ),
                ),
              if (_showInfo || (error != null && !_tvPanelOpen))
                Positioned(
                  top: 72,
                  left: 12,
                  child: _InfoPanel(
                    rows: _showInfo
                        ? [
                            ..._info.toRows(),
                            if (_log != null)
                              (
                                '',
                                bufferSummary(
                                  _playback.stats,
                                  live: _playback.isLive,
                                ),
                              ),
                          ]
                        : const [],
                    error: error,
                  ),
                ),
              if (_secondsToNext != null)
                Positioned(
                  right: 24,
                  bottom: 24,
                  child: _NextEpisodePanel(
                    title: widget.nextTitle,
                    seconds: _secondsToNext!,
                    onWatchNow: _goNext,
                    onCancel: _cancelCountdown,
                  ),
                ),
              // Last, so the list and options cover the messages above.
              if (_tvLive)
                Positioned.fill(
                  child: TvLiveControls(
                    playback: _playback,
                    title: _title,
                    subtitle: _subtitle,
                    source: widget.tvLive,
                    onChannelStep: widget.onChannelStep,
                    onPanelChanged: (open) =>
                        setState(() => _tvPanelOpen = open),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay counting down to the next episode, with "Ver ahora" and "Cancelar".
class _NextEpisodePanel extends StatelessWidget {
  const _NextEpisodePanel({
    required this.seconds,
    required this.onWatchNow,
    required this.onCancel,
    this.title,
  });

  final String? title;
  final int seconds;
  final VoidCallback onWatchNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Siguiente episodio en $seconds s', style: text.titleMedium),
          if (title != null)
            Text(
              title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                autofocus: true,
                onPressed: onWatchNow,
                child: const Text('Ver ahora'),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onCancel, child: const Text('Cancelar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Semi-transparent box listing stream details and the last playback error.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.rows, this.error});

  final List<(String, String)> rows;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, value) in rows)
            Text(label.isEmpty ? value : '$label: $value', style: style),
          if (error != null)
            Text(
              'Error: $error',
              style: style?.copyWith(color: Colors.redAccent),
            ),
        ],
      ),
    );
  }
}

/// Shown instead of the spinner when the stream did not start in time.
class _StartFailedMessage extends StatelessWidget {
  const _StartFailedMessage({required this.what, required this.timeout});

  /// What failed to open, e.g. `el canal`.
  final String what;
  final Duration timeout;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          BrandMessage(
            title: 'No se ha podido abrir $what',
            message:
                'No ha empezado a reproducirse en ${timeout.inSeconds} s. '
                'Prueba más tarde o elige otro.',
            logoSize: 64,
            dimmed: true,
          ),
        ],
      ),
    );
  }
}

/// Seek bar track over the picture: clearly visible even on black.
const controlsTrackColor = Color(0x73FFFFFF);

/// Desktop video controls: white icons, an [accent] position bar on a
/// visible track, and the branded loader while buffering.
MaterialDesktopVideoControlsThemeData desktopControlsTheme(Color accent) =>
    MaterialDesktopVideoControlsThemeData(
      buttonBarButtonColor: Colors.white,
      buttonBarButtonSize: 32,
      seekBarColor: controlsTrackColor,
      seekBarHoverColor: controlsTrackColor,
      seekBarBufferColor: const Color(0x99FFFFFF),
      seekBarPositionColor: accent,
      seekBarThumbColor: accent,
      seekBarHeight: 4.5,
      seekBarHoverHeight: 6.5,
      seekBarThumbSize: 14,
      volumeBarColor: controlsTrackColor,
      bufferingIndicatorBuilder: _brandLoaderBuilder,
    );

/// Touch video controls, with the same contrast as [desktopControlsTheme].
MaterialVideoControlsThemeData mobileControlsTheme(Color accent) =>
    MaterialVideoControlsThemeData(
      buttonBarButtonColor: Colors.white,
      seekBarColor: controlsTrackColor,
      seekBarBufferColor: const Color(0x99FFFFFF),
      seekBarPositionColor: accent,
      seekBarThumbColor: accent,
      bufferingIndicatorBuilder: _brandLoaderBuilder,
    );

/// Buffering indicator for the video controls.
Widget _brandLoaderBuilder(BuildContext context) =>
    const Center(child: BrandLoader());
