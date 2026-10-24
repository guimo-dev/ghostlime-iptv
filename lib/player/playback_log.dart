import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'stream_info.dart';

/// Minimum time between two `sample` lines in the log.
const sampleInterval = Duration(seconds: 10);

/// Cache level (seconds) under which every sample is logged: the buffer is
/// about to drain.
const lowCacheSecs = 3.0;

/// How close to the end of a file mpv's buffering is just the stream draining.
const endOfFileMargin = Duration(seconds: 2);

/// How many daily log files are kept.
const keptLogFiles = 7;

/// Things worth recording while a stream plays, to tell a server that drops
/// the stream (`error`/`ended` plus a reconnect) from a buffer that drains
/// (`bufferingStart` with a falling cache).
enum PlaybackEvent {
  opened,
  bufferingStart,
  bufferingEnd,
  error,
  ended,
  reconnectScheduled,
  reconnectOpened,
  reconnectGaveUp,

  /// The stream did not start playing within the start timeout.
  startTimeout,
}

/// Running totals shown in the info panel.
class PlaybackStats {
  const PlaybackStats({
    this.stalls = 0,
    this.reconnects = 0,
    this.errors = 0,
    this.lastCacheSecs,
    this.lastSpeedBytesPerSec,
  });

  /// Times buffering started after the initial fill.
  final int stalls;

  /// Times a stream was reopened after a failure.
  final int reconnects;
  final int errors;

  /// Seconds of video in mpv's cache at the last sample, if any.
  final double? lastCacheSecs;

  /// Download speed at the last sample, if known.
  final int? lastSpeedBytesPerSec;
}

/// Appends playback events to `<dir>/playback-YYYY-MM-DD.log`, one line each
/// (`HH:mm:ss.SSS <event> <detail>`), keeping the [keptLogFiles] newest files.
/// Details never contain stream URLs or credentials.
class PlaybackLog {
  PlaybackLog({required this.dir, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Directory dir;
  final DateTime Function() _clock;
  final List<(String day, String line)> _pending = [];
  Future<void> _writing = Future.value();
  DateTime? _lastSampleAt;
  int _sessions = 0;
  int _stalls = 0;
  int _reconnects = 0;
  int _errors = 0;
  double? _cacheSecs;
  int? _speedBytesPerSec;

  /// Whether the buffering right after an open is still to come: it is the
  /// initial fill, not a stall.
  bool _initialBufferingPending = false;

  /// Totals since the last `opened` (the current playback).
  PlaybackStats get stats => PlaybackStats(
    stalls: _stalls,
    reconnects: _reconnects,
    errors: _errors,
    lastCacheSecs: _cacheSecs,
    lastSpeedBytesPerSec: _speedBytesPerSec,
  );

  /// Records [event]; [detail] has its URLs replaced before being written.
  /// `opened` starts a new numbered session and resets the totals;
  /// `bufferingStart` also logs the last known cache level and speed.
  void record(PlaybackEvent event, {String? detail}) {
    var text = detail;
    switch (event) {
      case PlaybackEvent.opened:
        _sessions++;
        _stalls = _reconnects = _errors = 0;
        _cacheSecs = _speedBytesPerSec = null;
        _initialBufferingPending = true;
        text = '#$_sessions';
      case PlaybackEvent.reconnectOpened:
        _reconnects++;
        _initialBufferingPending = true;
      case PlaybackEvent.bufferingStart:
        if (_initialBufferingPending) {
          _initialBufferingPending = false;
        } else {
          _stalls++;
        }
        text = _cacheText(_cacheSecs, _speedBytesPerSec);
      case PlaybackEvent.error:
        _errors++;
      default:
    }
    final redacted = text == null ? '' : ' ${redactUrls(text)}';
    _add('${event.name}$redacted');
  }

  /// Notes the cache level and download speed (`null` when mpv does not know
  /// them). The log line is written at most once per [sampleInterval], except
  /// while the cache is under [lowCacheSecs]; the stats are always updated.
  void sample({required double? cacheSecs, required int? speedBytesPerSec}) {
    _cacheSecs = cacheSecs;
    _speedBytesPerSec = speedBytesPerSec;
    final now = _clock();
    final last = _lastSampleAt;
    final low = cacheSecs != null && cacheSecs < lowCacheSecs;
    if (!low && last != null && now.difference(last) < sampleInterval) return;
    _lastSampleAt = now;
    _add('sample ${_cacheText(cacheSecs, speedBytesPerSec)}');
  }

  static String _cacheText(double? cacheSecs, int? speedBytesPerSec) {
    final cache = cacheSecs == null ? '?' : '${cacheSecs.toStringAsFixed(1)}s';
    final speed = speedBytesPerSec == null
        ? '?'
        : '${(speedBytesPerSec / 1e6).toStringAsFixed(1)}MB/s';
    return 'cache=$cache speed=$speed';
  }

  /// Completes when every line recorded so far is on disk.
  Future<void> flush() => _writing;

  void _add(String text) {
    final now = _clock();
    _pending.add((_day(now), '${_time(now)} $text'));
    _writing = _writing.then((_) => _writePending());
  }

  Future<void> _writePending() async {
    if (_pending.isEmpty) return;
    final batch = List.of(_pending);
    _pending.clear();
    try {
      await dir.create(recursive: true);
      for (final (day, line) in batch) {
        await File('${dir.path}/playback-$day.log')
            .writeAsString('$line\n', mode: FileMode.append);
      }
      await _pruneOldFiles();
    } on FileSystemException {
      // Logging must never break playback.
    }
  }

  Future<void> _pruneOldFiles() async {
    final files = await dir
        .list()
        .where((e) => e is File && _isLogName(e.uri.pathSegments.last))
        .map((e) => e.path)
        .toList();
    files.sort();
    if (files.length <= keptLogFiles) return;
    for (final path in files.take(files.length - keptLogFiles)) {
      await File(path).delete();
    }
  }

  static bool _isLogName(String name) =>
      RegExp(r'^playback-\d{4}-\d{2}-\d{2}\.log$').hasMatch(name);

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _day(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

  static String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

/// Whether [position] is at the end of a file of [duration]: mpv reports
/// buffering there while it drains, which is not a stall. A zero [duration]
/// (live, or not known yet) has no end.
bool isEndOfFile(Duration position, Duration duration) =>
    duration > Duration.zero && position >= duration - endOfFileMargin;

/// The info-panel line, e.g. `Búfer 12 s · 2,1 MB/s · cortes 3 · reconexiones 1`.
/// For a VOD (`live: false`) a cache or speed of 0 only means everything is
/// cached or read from disk, so it shows "—" instead of a misleading 0.
String bufferSummary(PlaybackStats stats, {bool live = true}) {
  final cache = stats.lastCacheSecs?.round();
  final speed = stats.lastSpeedBytesPerSec;
  final cacheText = cache == null || (!live && cache <= 0) ? '—' : '$cache';
  final speedText = speed == null || (!live && speed <= 0)
      ? '—'
      : '${(speed / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB/s';
  return 'Búfer $cacheText s · $speedText · cortes ${stats.stalls} · '
      'reconexiones ${stats.reconnects}';
}

/// Exposes the [PlaybackLog] to the player screens; without a scope nothing
/// is logged.
class PlaybackLogScope extends InheritedWidget {
  const PlaybackLogScope({super.key, required this.log, required super.child});

  final PlaybackLog log;

  /// The log of the nearest scope, or `null` when there is none.
  static PlaybackLog? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlaybackLogScope>()?.log;

  @override
  bool updateShouldNotify(PlaybackLogScope oldWidget) => log != oldWidget.log;
}
