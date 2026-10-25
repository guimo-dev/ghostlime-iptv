import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';

import '../catalog/catalog_models.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import 'mpv_options.dart';
import 'play_target.dart';
import 'playback_log.dart';
import 'stream_info.dart';
import 'stream_url.dart';

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

/// Creates the player and its video controller for the mpv [hwdec] (`null`
/// keeps media_kit's choice); tests pass a fake.
typedef PlayerFactory = (Player, VideoController) Function(String? hwdec);

/// The real media_kit player and video controller.
(Player, VideoController) _createMediaKitPlayer(String? hwdec) {
  final player = Player();
  return (
    player,
    VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    ),
  );
}

/// One player that keeps playing while it moves between screens: Directo's
/// preview and the full-screen player show the same stream, so going full
/// screen never opens a second connection (providers may allow only one)
/// nor buffers again.
///
/// It applies the playback settings to mpv, reconnects live streams as
/// [ReconnectPolicy] decides, gives up when a stream does not start within
/// [startTimeout] and records everything in the playback log. The player is
/// created on the first open, so a screen that never plays needs no libmpv.
///
/// A `PlayerScreen` that is given none creates its own, which then drives a
/// movie or episode (VOD) the same way and lives as long as that screen.
class LivePlayback extends ChangeNotifier {
  LivePlayback({
    required this._settings,
    this.playlist,
    this.password,
    this._log,
    this.startTimeout = streamStartTimeout,
    PlayerFactory? createPlayer,
  }) : _createPlayer = createPlayer ?? _createMediaKitPlayer;

  /// Playlist whose targets [play] opens; only [openUrl] works without it.
  final Playlist? playlist;

  /// The playlist's password, needed for Xtream targets.
  final Future<String?>? password;

  /// How long a stream may take to start before [startFailed] is set.
  final Duration startTimeout;

  /// Current settings, read again on every open.
  final AppSettings Function() _settings;
  final PlaybackLog? _log;
  final PlayerFactory _createPlayer;

  Player? _player;
  VideoController? _controller;

  /// The mpv `hwdec` [_controller] was created with: it is fixed for the
  /// life of the controller.
  String? _playerHwdec;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Bumped by every play and stop: an open that is no longer the latest
  /// gives up at its next step.
  int _generation = 0;

  /// Generation whose `open` has returned: only then do the player's events
  /// belong to it (a reused player may still report the previous stream).
  int? _openedGeneration;

  /// Generation that last called `open`: an older start that is no longer
  /// wanted may only stop the player while no newer one has opened it.
  int? _openingGeneration;

  /// What is playing (a target key or a URL), or `null` when stopped.
  String? _key;

  /// The stream being played, reopened by reconnections.
  Media? _media;
  bool _isLive = true;
  bool _startFailed = false;

  /// The stream failed or ended and will not be reopened by itself (the
  /// reconnections ran out or are switched off).
  bool _gaveUp = false;
  String? _error;

  /// Whether playback reached a position since the last play; later drops
  /// are left to the reconnection logic, not the start timeout.
  bool _everStarted = false;
  DateTime _openedAt = DateTime.now();
  ReconnectPolicy? _reconnectPolicy;
  Timer? _startTimer;
  Timer? _reconnectTimer;
  double _volume = 100;
  bool _disposed = false;

  /// The player, created on first use.
  Player get player => _ensurePlayer();

  /// The video controller of [player], for `Video` widgets.
  VideoController get controller {
    _ensurePlayer();
    return _controller!;
  }

  /// Creates the player and its controller unless they exist.
  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final hwdec = _hwdecSetting();
    final (player, controller) = _createPlayer(hwdec);
    _player = player;
    _controller = controller;
    _playerHwdec = hwdec;
    _subscriptions.addAll([
      player.stream.error.listen(_onError),
      player.stream.completed.listen(_onCompleted),
      player.stream.buffering.listen(_onBuffering),
      player.stream.position.listen(_onPosition),
    ]);
    return player;
  }

  /// Disposes the player and its controller; the next use creates new ones.
  void _releasePlayer() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  /// The `hwdec` the current "hardware decoding" setting asks for.
  String? _hwdecSetting() => hwdecFor(
    hardwareDecoding: _settings().hardwareDecoding,
    isAndroid: Platform.isAndroid,
  );

  /// Whether the player exists, i.e. something was ever opened.
  bool get hasPlayer => _player != null;

  /// Whether the current stream is live (it reconnects) or a VOD.
  bool get isLive => _isLive;

  /// The stream did not start within [startTimeout] and was closed.
  bool get startFailed => _startFailed;

  /// The last playback error of the current stream, without URLs.
  String? get error => _error;

  /// Running totals of the current playback (zero without a log).
  PlaybackStats get stats => _log?.stats ?? const PlaybackStats();

  /// Plays [target] from [playlist]. Does nothing when it is already
  /// playing (or starting), so moving between screens never reopens it; a
  /// stream that failed to start, or failed later and is not being
  /// reconnected, is opened again.
  Future<void> play(PlayTarget target) async {
    if (_key == target.key && !_startFailed && !_gaveUp) return;
    final generation = _begin(target.key);
    final playlist = this.playlist!;
    final url = playTargetUrl(playlist, target, await password);
    if (generation != _generation) return;
    if (url == null) {
      // Nothing to play: the previous channel must not go on.
      _key = null;
      _media = null;
      notifyListeners();
      await _player?.stop();
      return;
    }
    final userAgent = playlist.userAgent;
    await _open(
      generation,
      Media(
        url,
        httpHeaders: userAgent == null ? null : {'User-Agent': userAgent},
      ),
      isLive: target.kind == MediaKind.live,
    );
  }

  /// Plays [url] (from [start] when given), sending [userAgent] if set.
  Future<void> openUrl(
    String url, {
    required bool isLive,
    String? userAgent,
    Duration? start,
  }) {
    final generation = _begin(url);
    return _open(
      generation,
      Media(
        url,
        httpHeaders: userAgent == null ? null : {'User-Agent': userAgent},
        start: start,
      ),
      isLive: isLive,
    );
  }

  /// Closes the stream and cancels pending starts and reconnections.
  Future<void> stop() async {
    _generation++;
    _cancelTimers();
    _key = null;
    _media = null;
    _startFailed = false;
    _gaveUp = false;
    _error = null;
    _openedGeneration = null;
    notifyListeners();
    await _player?.stop();
    await _log?.flush();
  }

  /// The volume (0 to 100) set with [setVolume].
  double get volume => _volume;

  /// Sets the volume (0 to 100), now and for every later open.
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _player?.setVolume(volume);
  }

  /// Reads the stream details from mpv and samples the cache into the log;
  /// `null` when there is no mpv player.
  Future<StreamInfo?> readInfo() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return null;
    final values = <String, String>{};
    for (final name in mpvInfoProperties) {
      if (_disposed) return null;
      values[name] = await platform.getProperty(name);
    }
    await _sampleCache(platform);
    return _disposed ? null : StreamInfo.fromMpvProperties(values);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelTimers();
    _log?.flush();
    _releasePlayer();
    super.dispose();
  }

  /// Starts a new playback of [key]: cancels the previous one's timers and
  /// clears its state. Returns the new generation.
  int _begin(String key) {
    _cancelTimers();
    _key = key;
    _startFailed = false;
    _gaveUp = false;
    _error = null;
    _everStarted = false;
    _openedGeneration = null;
    notifyListeners();
    return ++_generation;
  }

  /// Applies the playback settings, closes whatever was playing and opens
  /// [media], giving up at any step once [generation] is no longer current.
  Future<void> _open(
    int generation,
    Media media, {
    required bool isLive,
  }) async {
    final settings = _settings();
    _isLive = isLive;
    _reconnectPolicy = ReconnectPolicy(
      isLive: isLive,
      autoReconnect: settings.autoReconnect,
      onGiveUp: (reason) =>
          _log?.record(PlaybackEvent.reconnectGaveUp, detail: reason),
    );
    // The controller keeps the hwdec it was created with: when the setting
    // changed since, start over with a new player and controller.
    final hwdec = _hwdecSetting();
    final recreate = _player != null && hwdec != _playerHwdec;
    if (recreate) _releasePlayer();
    final player = this.player;
    if (recreate) notifyListeners();
    final platform = player.platform;
    if (platform is NativePlayer) {
      final properties = {
        'hwdec': ?hwdec,
        'cache': 'yes',
        'cache-secs': '${settings.networkCacheSecs}',
        'demuxer-readahead-secs': '${settings.networkCacheSecs}',
      };
      for (final MapEntry(:key, :value) in properties.entries) {
        await platform.setProperty(key, value);
        if (generation != _generation) return;
      }
    }
    await useSafeDemuxerOptions(player);
    if (generation != _generation) return;
    await player.setVolume(_volume);
    if (generation != _generation) return;
    // A reused player may report the previous stream's position after the
    // next open: stop it first and only trust events once `open` returns.
    await player.stop();
    if (generation != _generation) return;
    _media = media;
    _openedAt = DateTime.now();
    _log?.record(PlaybackEvent.opened);
    _watchStart(generation);
    _openingGeneration = generation;
    await player.open(media);
    if (generation != _generation) {
      // Replaced or stopped while opening: the stop issued then may have
      // landed before the open, so close the stream now.
      if (identical(player, _player) && _openingGeneration == generation) {
        await player.stop();
      }
      return;
    }
    _openedGeneration = generation;
    notifyListeners();
  }

  /// Whether the player's events belong to the stream opened last.
  bool get _eventsAreCurrent =>
      _media != null && _openedGeneration == _generation;

  void _onError(String message) {
    if (!_eventsAreCurrent) return;
    _log?.record(
      PlaybackEvent.error,
      detail: '${_playbackContext()}: $message',
    );
    _error = redactUrls(message);
    notifyListeners();
    _reconnect();
  }

  void _onCompleted(bool completed) {
    if (!completed || !_eventsAreCurrent) return;
    _log?.record(PlaybackEvent.ended, detail: _playbackContext());
    if (_isLive) _reconnect();
  }

  void _onBuffering(bool buffering) {
    if (!_eventsAreCurrent) return;
    // mpv reports buffering while a file drains at its end: not a stall.
    final state = player.state;
    if (!_isLive && isEndOfFile(state.position, state.duration)) return;
    _log?.record(
      buffering ? PlaybackEvent.bufferingStart : PlaybackEvent.bufferingEnd,
    );
  }

  void _onPosition(Duration position) {
    if (position <= Duration.zero || !_eventsAreCurrent) return;
    _everStarted = true;
    _startTimer?.cancel();
  }

  /// Arms the start timeout unless it is already running or the stream has
  /// already played; playback reaching a position cancels it.
  void _watchStart(int generation) {
    if (_everStarted) return;
    if (_startTimer?.isActive ?? false) return;
    _startTimer = Timer(startTimeout, () => _onStartTimeout(generation));
  }

  /// The stream never started: stop trying, free the connection and report
  /// [startFailed] instead of loading forever.
  void _onStartTimeout(int generation) {
    if (generation != _generation) return;
    _reconnectTimer?.cancel();
    _log?.record(PlaybackEvent.startTimeout, detail: _playbackContext());
    _player?.stop();
    _startFailed = true;
    notifyListeners();
  }

  /// Reopens a live stream after it ended or failed, as [ReconnectPolicy]
  /// decides; when it will not, a later [play] of the same target opens it
  /// again.
  void _reconnect() {
    final media = _media;
    if (media == null || _startFailed) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final policy = _reconnectPolicy!;
    final delay = policy.next(
      stable: DateTime.now().difference(_openedAt) > _stableAfter,
    );
    if (delay == null) {
      _gaveUp = true;
      return;
    }
    _log?.record(
      PlaybackEvent.reconnectScheduled,
      detail: 'attempt ${policy.attempts} in ${delay.inSeconds}s',
    );
    final generation = _generation;
    _reconnectTimer = Timer(delay, () {
      if (generation != _generation) return;
      _openedAt = DateTime.now();
      _log?.record(PlaybackEvent.reconnectOpened);
      _watchStart(generation);
      player.open(media);
    });
  }

  /// `live` or `vod`, seconds since the stream was opened and the position
  /// when known, e.g. `live after=3712s pos=3700s`.
  String _playbackContext() {
    final kind = _isLive ? 'live' : 'vod';
    final after = DateTime.now().difference(_openedAt).inSeconds;
    final position = _player?.state.position.inSeconds ?? 0;
    return '$kind after=${after}s${position > 0 ? ' pos=${position}s' : ''}';
  }

  /// Logs mpv's cache level and download speed (bytes per second).
  Future<void> _sampleCache(NativePlayer platform) async {
    final log = _log;
    if (log == null || _disposed) return;
    final cache = double.tryParse(
      await platform.getProperty('demuxer-cache-duration'),
    );
    final speed = double.tryParse(await platform.getProperty('cache-speed'));
    if (_disposed) return;
    // The cache of a file that has ended reads 0: keep the last real values.
    final state = player.state;
    if (!_isLive && isEndOfFile(state.position, state.duration)) return;
    log.sample(cacheSecs: cache, speedBytesPerSec: speed?.round());
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _reconnectTimer?.cancel();
  }
}
