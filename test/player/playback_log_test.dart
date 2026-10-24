import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/playback_log.dart';

void main() {
  late Directory dir;
  late DateTime now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('playback_log_test');
    now = DateTime(2026, 10, 21, 9, 5, 3, 7);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PlaybackLog newLog() => PlaybackLog(dir: dir, clock: () => now);

  String readToday() =>
      File('${dir.path}/playback-2026-10-21.log').readAsStringSync();

  test('records events with timestamps', () async {
    final log = newLog();
    log.record(PlaybackEvent.opened);
    now = now.add(const Duration(seconds: 2));
    log.record(PlaybackEvent.error, detail: 'boom');
    await log.flush();
    expect(readToday().trimRight().split('\n'), [
      '09:05:03.007 opened #1',
      '09:05:05.007 error boom',
    ]);
  });

  test('redacts URLs and credentials in details', () async {
    final log = newLog();
    log.record(PlaybackEvent.error, detail: 'failed http://h/live/u/p/1.ts');
    await log.flush();
    expect(readToday(), isNot(contains('u/p')));
    expect(readToday(), contains('[URL]'));
  });

  test('stats count stalls and reconnects', () async {
    final log = newLog();
    log.record(PlaybackEvent.bufferingStart);
    log.record(PlaybackEvent.bufferingEnd);
    log.record(PlaybackEvent.bufferingStart);
    log.record(PlaybackEvent.error);
    log.record(PlaybackEvent.reconnectScheduled);
    log.record(PlaybackEvent.reconnectOpened);
    log.sample(cacheSecs: 4.5, speedBytesPerSec: 1000000);
    expect(log.stats.stalls, 2);
    expect(log.stats.reconnects, 1);
    expect(log.stats.errors, 1);
    expect(log.stats.lastCacheSecs, 4.5);
    await log.flush();
  });

  test('keeps only 7 daily files', () async {
    for (var day = 1; day <= 9; day++) {
      File('${dir.path}/playback-2026-10-${day.toString().padLeft(2, '0')}.log')
          .writeAsStringSync('old\n');
    }
    final log = newLog();
    log.record(PlaybackEvent.opened);
    await log.flush();
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList()
      ..sort();
    expect(names, hasLength(7));
    expect(names.first, 'playback-2026-10-04.log');
    expect(names.last, 'playback-2026-10-21.log');
  });

  test('samples are written at most every 10 s', () async {
    final log = newLog();
    log.sample(cacheSecs: 12.4, speedBytesPerSec: 2100000);
    now = now.add(const Duration(seconds: 4));
    log.sample(cacheSecs: 11, speedBytesPerSec: null);
    now = now.add(const Duration(seconds: 7));
    log.sample(cacheSecs: 9, speedBytesPerSec: null);
    await log.flush();
    expect(readToday().trimRight().split('\n'), [
      '09:05:03.007 sample cache=12.4s speed=2.1MB/s',
      '09:05:14.007 sample cache=9.0s speed=?',
    ]);
  });

  test('bufferingStart carries the last cache and speed', () async {
    final log = newLog();
    log.sample(cacheSecs: 0.3, speedBytesPerSec: 1200000);
    log.record(PlaybackEvent.bufferingStart);
    await log.flush();
    expect(readToday(), contains('bufferingStart cache=0.3s speed=1.2MB/s'));
  });

  test('samples under 3 s of cache skip the throttle', () async {
    final log = newLog();
    log.sample(cacheSecs: 2.0, speedBytesPerSec: null);
    now = now.add(const Duration(seconds: 2));
    log.sample(cacheSecs: 1.0, speedBytesPerSec: null);
    now = now.add(const Duration(seconds: 2));
    log.sample(cacheSecs: 8.0, speedBytesPerSec: null);
    await log.flush();
    expect(readToday().trimRight().split('\n'), hasLength(2));
  });

  test('unknown cache is written as question marks', () async {
    final log = newLog();
    log.sample(cacheSecs: null, speedBytesPerSec: null);
    await log.flush();
    expect(readToday(), contains('sample cache=? speed=?'));
  });

  test('reconnectGaveUp keeps its reason and details are kept', () async {
    final log = newLog();
    log.record(PlaybackEvent.reconnectGaveUp, detail: 'attempts exhausted');
    log.record(PlaybackEvent.ended, detail: 'live after=3712s');
    await log.flush();
    expect(readToday(), contains('reconnectGaveUp attempts exhausted'));
    expect(readToday(), contains('ended live after=3712s'));
  });

  test('opened numbers sessions and resets the panel counters', () async {
    final log = newLog();
    log.record(PlaybackEvent.opened);
    log.record(PlaybackEvent.bufferingStart);
    log.record(PlaybackEvent.bufferingStart);
    expect(log.stats.stalls, 1);
    log.record(PlaybackEvent.opened);
    expect(log.stats.stalls, 0);
    await log.flush();
    expect(readToday(), contains('opened #1'));
    expect(readToday(), contains('opened #2'));
  });

  test('the initial buffering after a reconnect is not a stall', () {
    final log = newLog();
    log.record(PlaybackEvent.opened);
    log.record(PlaybackEvent.bufferingStart);
    log.record(PlaybackEvent.bufferingEnd);
    log.record(PlaybackEvent.reconnectOpened);
    log.record(PlaybackEvent.bufferingStart);
    expect(log.stats.stalls, 0);
    log.record(PlaybackEvent.bufferingStart);
    expect(log.stats.stalls, 1);
    expect(log.stats.reconnects, 1);
  });

  group('end of file and idle cache', () {
    test('buffering within 2 s of the end of a file is not a stall', () {
      const duration = Duration(seconds: 120);
      expect(isEndOfFile(const Duration(seconds: 119), duration), isTrue);
      expect(isEndOfFile(const Duration(seconds: 60), duration), isFalse);
      // Live streams and unknown durations have no end.
      expect(isEndOfFile(const Duration(seconds: 5), Duration.zero), isFalse);
    });

    test('the panel shows a dash for a VOD zero, but keeps it for live', () {
      const drained = PlaybackStats(lastCacheSecs: 0, lastSpeedBytesPerSec: 0);
      expect(
        bufferSummary(drained, live: false),
        startsWith('Búfer — s · — · cortes 0'),
      );
      expect(
        bufferSummary(drained),
        startsWith('Búfer 0 s · 0,0 MB/s · cortes 0'),
      );
      const cached = PlaybackStats(
        lastCacheSecs: 8.4,
        lastSpeedBytesPerSec: 900000,
      );
      expect(
        bufferSummary(cached, live: false),
        startsWith('Búfer 8 s · 0,9 MB/s'),
      );
    });

    test('the log keeps raw zeros so real drains stay visible', () async {
      final log = newLog();
      log.sample(cacheSecs: 0, speedBytesPerSec: 0);
      expect(log.stats.lastCacheSecs, 0);
      expect(log.stats.lastSpeedBytesPerSec, 0);
      await log.flush();
      expect(readToday(), contains('cache=0.0s speed=0.0MB/s'));
    });
  });
}
