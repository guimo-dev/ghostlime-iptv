import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/player/mpv_options.dart';
import 'package:iptv_player/player/playback_log.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:media_kit/media_kit.dart';

import '../tool/demo_server/demo_server.dart';

/// Seconds of the demo clip, used as segment length.
const _segmentSeconds = 12;

/// Serves a live HLS stream shaped like RTVE's: a master playlist with a
/// WebVTT subtitle rendition and one video variant, both sliding windows of
/// three segments without `#EXT-X-ENDLIST`. Every video segment is the demo
/// clip.
Future<HttpServer> _startLiveHlsWithSubtitles() async {
  final clip = await File(DemoServer.defaultClipPath).readAsBytes();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  String window(String extension) {
    final first =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ _segmentSeconds;
    return [
      '#EXTM3U',
      '#EXT-X-VERSION:3',
      '#EXT-X-TARGETDURATION:$_segmentSeconds',
      '#EXT-X-MEDIA-SEQUENCE:$first',
      for (var i = first; i < first + 3; i++) ...[
        '#EXTINF:$_segmentSeconds.0,',
        '/seg/$i.$extension',
      ],
    ].join('\n');
  }

  server.listen((request) async {
    final path = request.uri.path;
    final response = request.response;
    if (path == '/master.m3u8') {
      response.write(
        '#EXTM3U\n'
        '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Español",'
        'LANGUAGE="es",DEFAULT=NO,URI="/subs.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1000000,SUBTITLES="subs"\n'
        '/video.m3u8\n',
      );
    } else if (path == '/video.m3u8') {
      response.write(window('ts'));
    } else if (path == '/subs.m3u8') {
      response.write(window('vtt'));
    } else if (path.endsWith('.ts')) {
      response.add(clip);
    } else if (path.endsWith('.vtt')) {
      response.write('WEBVTT\n\n00:00.000 --> 00:05.000\nHola\n');
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a live HLS stream with WebVTT subtitles starts playing', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final server = await _startLiveHlsWithSubtitles();
    final player = Player();
    addTearDown(() async {
      await player.dispose();
      await server.close(force: true);
    });

    final position = await tester.runAsync(() async {
      await useSafeDemuxerOptions(player);
      await player.open(Media('http://127.0.0.1:${server.port}/master.m3u8'));
      return player.stream.position
          .firstWhere((p) => p > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
    });

    expect(position, greaterThan(Duration.zero));
  });

  testWidgets('a stream that never starts shows an error and logs it', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final held = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(held.add);
    final dir = await Directory.systemTemp.createTemp('ghostlime_log_');
    final db = CatalogDb.inMemory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
      db.close();
      await dir.delete(recursive: true);
    });
    final log = PlaybackLog(dir: dir);

    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(db),
        child: PlaybackLogScope(
          log: log,
          child: MaterialApp(
            home: PlayerScreen(
              url: 'http://127.0.0.1:${server.port}/live.ts',
              title: 'Canal',
              isLive: true,
              startTimeout: const Duration(seconds: 3),
            ),
          ),
        ),
      ),
    );

    final message = find.text('No se ha podido abrir el canal');
    final watch = Stopwatch()..start();
    while (message.evaluate().isEmpty && watch.elapsed.inSeconds < 10) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(message, findsOneWidget);
    final logText = await tester.runAsync(() async {
      await log.flush();
      final files = await dir.list().toList();
      return (files.single as File).readAsString();
    });
    expect(logText, contains('startTimeout live'));
  });

  testWidgets('a stream that played and then drops is left to reconnection, '
      'not the start timeout', (tester) async {
    MediaKit.ensureInitialized();
    final clip = await File(DemoServer.defaultClipPath).readAsBytes();
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // The first request gets the clip once; every reconnection hangs.
    server.listen((request) async {
      if (requests++ > 0) return;
      request.response.add(clip);
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('ghostlime_log_');
    final db = CatalogDb.inMemory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
      db.close();
      await dir.delete(recursive: true);
    });
    final log = PlaybackLog(dir: dir);

    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(db),
        child: PlaybackLogScope(
          log: log,
          child: MaterialApp(
            home: PlayerScreen(
              url: 'http://127.0.0.1:${server.port}/live.ts',
              title: 'Canal',
              isLive: true,
              startTimeout: const Duration(seconds: 3),
            ),
          ),
        ),
      ),
    );

    // 12 s of clip, a 2 s pause and the first reconnection, plus margin
    // beyond the 3 s start timeout.
    final watch = Stopwatch()..start();
    while (watch.elapsed.inSeconds < 24) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    final logText = await tester.runAsync(() async {
      await log.flush();
      final files = await dir.list().toList();
      return (files.single as File).readAsString();
    });
    expect(logText, contains('reconnectOpened'));
    expect(logText, isNot(contains('startTimeout')));
    expect(find.text('No se ha podido abrir el canal'), findsNothing);
  });
}
