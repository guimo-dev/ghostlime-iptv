import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../ui/app_theme.dart';
import '../ui/brand_state.dart';
import 'mpv_options.dart';
import 'playback_log.dart';
import 'stream_info.dart';

/// How often playback progress is reported while playing.
const progressInterval = Duration(seconds: 10);

/// Pause before each automatic reconnection of a live stream; its length is
/// the maximum number of attempts.
const reconnectDelays = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// How long a reopened stream must have run for new failures to count from
/// the first attempt again.
const _stableAfter = Duration(seconds: 30);

/// Decides whether a stream that failed or ended is reopened, and after how
/// long. mpv often reports one failure twice (`error`, then `completed`), so
/// giving up is reported once until a reconnection is scheduled again.
class ReconnectPolicy {
  ReconnectPolicy({
    required this.isLive,
    required this.autoReconnect,
    required this.onGiveUp,
  });

  /// Only live streams reconnect; a VOD that ends or fails has nothing to
  /// give up, so it reports nothing.
  final bool isLive;
  final bool autoReconnect;

  /// Called with the reason when a live stream will not be reopened.
  final void Function(String reason) onGiveUp;

  /// Reconnections scheduled since the stream last ran stably.
  int attempts = 0;
  bool _gaveUp = false;

  /// The pause before reopening the stream, or `null` when it stays closed.
  /// [stable] means it had run long enough for failures to count from the
  /// first attempt again.
  Duration? next({required bool stable}) {
    if (!isLive) return null;
    if (!autoReconnect) return _giveUp('auto-reconnect off');
    if (stable) attempts = 0;
    if (attempts >= reconnectDelays.length) {
      return _giveUp('attempts exhausted');
    }
    _gaveUp = false;
    return reconnectDelays[attempts++];
  }

  Duration? _giveUp(String reason) {
    if (!_gaveUp) onGiveUp(reason);
    _gaveUp = true;
    return null;
  }
}

/// Seconds shown before the next episode starts by itself.
const nextEpisodeCountdown = 10;

/// Whether the player's [position] is real progress worth saving: both values
/// are known and, when resuming from [start], playback has reached it (a
/// slow start would otherwise overwrite the saved point with ~0).
bool progressReady(Duration position, Duration duration, Duration? start) {
  if (position <= Duration.zero || duration <= Duration.zero) return false;
  return start == null || position >= start - const Duration(seconds: 5);
}

/// Full-screen player for one stream, with a toggleable technical info overlay.
///
/// The [Player] lives exactly as long as this screen: leaving it closes the
/// connection, which matters for providers that allow a single connection.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.userAgent,
    this.startPosition,
    this.onProgress,
    this.subtitle,
    this.isLive = false,
    this.onNext,
    this.nextTitle,
    this.startTimeout = streamStartTimeout,
  });

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

  /// How long the stream may take to start before an error replaces the
  /// loading spinner (shorter in tests).
  final Duration startTimeout;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final AppSettings _settings = SettingsScope.read(context).value;

  /// `hwdec` forced by the settings, or `null` to keep media_kit's choice.
  late final String? _hwdec = hwdecFor(
    hardwareDecoding: _settings.hardwareDecoding,
    isAndroid: Platform.isAndroid,
  );
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(hwdec: _hwdec),
  );
  late final PlaybackLog? _log = PlaybackLogScope.read(context);
  late final ReconnectPolicy _reconnectPolicy = ReconnectPolicy(
    isLive: widget.isLive,
    autoReconnect: _settings.autoReconnect,
    onGiveUp: (reason) =>
        _log?.record(PlaybackEvent.reconnectGaveUp, detail: reason),
  );
  late final Media _media = Media(
    widget.url,
    httpHeaders: widget.userAgent == null
        ? null
        : {'User-Agent': widget.userAgent!},
    start: widget.startPosition,
  );
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _infoTimer;
  Timer? _startTimer;
  Timer? _progressTimer;
  Timer? _reconnectTimer;
  Timer? _countdownTimer;

  /// Whether playback has reached the resume point, so progress is real.
  bool _resumed = false;
  StreamInfo _info = const StreamInfo();
  String? _error;
  bool _showInfo = false;

  /// Set once the screen is leaving: nothing may open or reopen a stream.
  bool _stopped = false;

  /// Set when the stream did not start within [PlayerScreen.startTimeout].
  bool _startFailed = false;

  /// Whether playback ever reached a position on this screen; later drops
  /// are left to the reconnection logic, not the start timeout.
  bool _everStarted = false;
  DateTime _openedAt = DateTime.now();

  /// Seconds left before the next episode, or `null` when not counting down.
  int? _secondsToNext;

  @override
  void initState() {
    super.initState();
    _errorSubscription = _player.stream.error.listen((message) {
      _log?.record(
        PlaybackEvent.error,
        detail: '${_playbackContext()}: $message',
      );
      if (mounted) setState(() => _error = redactUrls(message));
      _reconnect();
    });
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (!completed) return;
      _log?.record(PlaybackEvent.ended, detail: _playbackContext());
      if (widget.isLive) {
        _reconnect();
      } else if (widget.onNext != null) {
        _startCountdown();
      }
    });
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      // mpv reports buffering while a file drains at its end: not a stall.
      final state = _player.state;
      if (!widget.isLive && isEndOfFile(state.position, state.duration)) return;
      _log?.record(
        buffering ? PlaybackEvent.bufferingStart : PlaybackEvent.bufferingEnd,
      );
    });
    _positionSubscription = _player.stream.position.listen((position) {
      if (position <= Duration.zero) return;
      _everStarted = true;
      _startTimer?.cancel();
    });
    _openStream();
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

  /// Applies the playback settings to mpv, then opens the stream. Settings
  /// are read once here, so changing them never affects a running player.
  Future<void> _openStream() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final properties = {
        if (_hwdec != null) 'hwdec': _hwdec,
        'cache': 'yes',
        'cache-secs': '${_settings.networkCacheSecs}',
        'demuxer-readahead-secs': '${_settings.networkCacheSecs}',
      };
      for (final MapEntry(:key, :value) in properties.entries) {
        await platform.setProperty(key, value);
      }
    }
    await useSafeDemuxerOptions(_player);
    if (_stopped) return;
    _openedAt = DateTime.now();
    _log?.record(PlaybackEvent.opened);
    _watchStart();
    await _player.open(_media);
  }

  /// Arms the start timeout unless it is already running or the stream has
  /// already played; playback reaching a position cancels it.
  void _watchStart() {
    if (_everStarted) return;
    if (_startTimer?.isActive ?? false) return;
    _startTimer = Timer(widget.startTimeout, _onStartTimeout);
  }

  /// The stream never started: stop trying, free the connection and show
  /// the error instead of the endless spinner.
  void _onStartTimeout() {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _log?.record(PlaybackEvent.startTimeout, detail: _playbackContext());
    _player.stop();
    if (mounted) setState(() => _startFailed = true);
  }

  /// Reopens a live stream after it ended or failed, as [ReconnectPolicy]
  /// decides. Never once leaving.
  void _reconnect() {
    if (_stopped || _startFailed) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final delay = _reconnectPolicy.next(
      stable: DateTime.now().difference(_openedAt) > _stableAfter,
    );
    if (delay == null) return;
    _log?.record(
      PlaybackEvent.reconnectScheduled,
      detail: 'attempt ${_reconnectPolicy.attempts} in ${delay.inSeconds}s',
    );
    _reconnectTimer = Timer(delay, () {
      if (_stopped) return;
      _openedAt = DateTime.now();
      _log?.record(PlaybackEvent.reconnectOpened);
      _watchStart();
      _player.open(_media);
    });
  }

  /// `live` or `vod`, seconds since the stream was opened and the position
  /// when known, e.g. `live after=3712s pos=3700s`.
  String _playbackContext() {
    final kind = widget.isLive ? 'live' : 'vod';
    final after = DateTime.now().difference(_openedAt).inSeconds;
    final position = _player.state.position.inSeconds;
    return '$kind after=${after}s${position > 0 ? ' pos=${position}s' : ''}';
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
    await _player.stop();
    widget.onNext?.call();
  }

  /// Cancels every timer and blocks new opens; used when leaving the screen.
  void _stopForLeaving() {
    _stopped = true;
    _infoTimer?.cancel();
    _progressTimer?.cancel();
    _reconnectTimer?.cancel();
    _countdownTimer?.cancel();
    _startTimer?.cancel();
  }

  /// Sends the current position to [PlayerScreen.onProgress] when known.
  void _reportProgress() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    if (_resumed || progressReady(position, duration, widget.startPosition)) {
      _resumed = position > Duration.zero && duration > Duration.zero;
      if (_resumed) widget.onProgress?.call(position, duration);
    }
  }

  @override
  void dispose() {
    _stopForLeaving();
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _positionSubscription?.cancel();
    _log?.flush();
    _player.dispose();
    super.dispose();
  }

  /// Reads the current mpv properties into [_info].
  Future<void> _refreshInfo() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final values = <String, String>{};
    for (final name in mpvInfoProperties) {
      if (!mounted) return;
      values[name] = await platform.getProperty(name);
    }
    await _sampleCache(platform);
    if (mounted) setState(() => _info = StreamInfo.fromMpvProperties(values));
  }

  /// Logs mpv's cache level and download speed (bytes per second).
  Future<void> _sampleCache(NativePlayer platform) async {
    final log = _log;
    if (log == null || !mounted) return;
    final cache = double.tryParse(
      await platform.getProperty('demuxer-cache-duration'),
    );
    final speed = double.tryParse(await platform.getProperty('cache-speed'));
    // The cache of a file that has ended reads 0: keep the last real values.
    final state = _player.state;
    if (!widget.isLive && isEndOfFile(state.position, state.duration)) return;
    log.sample(cacheSecs: cache, speedBytesPerSec: speed?.round());
  }

  void _toggleInfo() => setState(() => _showInfo = !_showInfo);

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
    // Stop as soon as the pop starts, not when the route is disposed after
    // its exit animation: otherwise opening the next channel quickly can
    // overlap two connections on single-connection accounts.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _stopForLeaving();
          _reportProgress();
          _player.stop();
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.55),
            title: widget.subtitle == null
                ? Text(widget.title)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title),
                      Text(
                        widget.subtitle!,
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
                normal: desktopControlsTheme,
                fullscreen: desktopControlsTheme,
                child: MaterialVideoControlsTheme(
                  normal: mobileControlsTheme,
                  fullscreen: mobileControlsTheme,
                  child: Video(controller: _controller, fit: BoxFit.contain),
                ),
              ),
              if (_startFailed)
                Center(
                  child: _StartFailedMessage(
                    what: widget.isLive ? 'el canal' : 'el vídeo',
                    timeout: widget.startTimeout,
                  ),
                ),
              if (_showInfo || _error != null)
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
                                bufferSummary(_log.stats, live: widget.isLive),
                              ),
                          ]
                        : const [],
                    error: _error,
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

/// Desktop video controls: white icons, a lime position bar on a visible
/// track, and the branded loader while buffering.
const desktopControlsTheme = MaterialDesktopVideoControlsThemeData(
  buttonBarButtonColor: Colors.white,
  buttonBarButtonSize: 32,
  seekBarColor: controlsTrackColor,
  seekBarHoverColor: controlsTrackColor,
  seekBarBufferColor: Color(0x99FFFFFF),
  seekBarPositionColor: AppColors.accent,
  seekBarThumbColor: AppColors.accent,
  seekBarHeight: 4.5,
  seekBarHoverHeight: 6.5,
  seekBarThumbSize: 14,
  volumeBarColor: controlsTrackColor,
  bufferingIndicatorBuilder: _brandLoaderBuilder,
);

/// Touch video controls, with the same contrast as [desktopControlsTheme].
const mobileControlsTheme = MaterialVideoControlsThemeData(
  buttonBarButtonColor: Colors.white,
  seekBarColor: controlsTrackColor,
  seekBarBufferColor: Color(0x99FFFFFF),
  seekBarPositionColor: AppColors.accent,
  seekBarThumbColor: AppColors.accent,
  bufferingIndicatorBuilder: _brandLoaderBuilder,
);

/// Buffering indicator for the video controls.
Widget _brandLoaderBuilder(BuildContext context) =>
    const Center(child: BrandLoader());
