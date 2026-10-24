import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import '../../tool/demo_server/demo_server.dart';

/// Key of the [RepaintBoundary] around the app that `expectScreen` captures.
final screenBoundaryKey = GlobalKey(debugLabel: 'screen');

/// Window size of the compact layout.
const smallSize = Size(1024, 700);

/// Window size of the usual desktop layout.
const mediumSize = Size(1440, 900);

/// Folder name of the references for [size]: `small`, `medium` or `<w>x<h>`.
String sizeName(Size size) {
  if (size == smallSize) return 'small';
  if (size == mediumSize) return 'medium';
  return '${size.width.toInt()}x${size.height.toInt()}';
}

/// The real app on throwaway data: a temp catalog, in-memory passwords and
/// PIN, no account, and a local demo server to add as a playlist.
class AppHarness {
  AppHarness._(
    this._tester,
    this.dir,
    this.db,
    this.passwords,
    this.pins,
    this.settings,
    this.server,
  );

  final WidgetTester _tester;

  /// Temporary data directory, deleted on [close].
  final Directory dir;
  final CatalogDb db;
  final MemoryPasswordStore passwords;
  final MemoryPinStore pins;
  final SettingsController settings;

  /// Demo Xtream/M3U server (credentials `demo` / `demo`).
  final DemoServer server;

  /// Starts the app in a window of [size] logical pixels at device pixel
  /// ratio 1.0, with a non-blinking caret, and pumps the first frame. Whatever
  /// was opened is released again if starting fails.
  static Future<AppHarness> start(
    WidgetTester tester, {
    required Size size,
  }) async {
    MediaKit.ensureInitialized();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    EditableText.debugDeterministicCursor = true;
    final dir = await Directory.systemTemp.createTemp('ghostlime_visual_');
    CatalogDb? db;
    DemoServer? server;
    try {
      db = CatalogDb.open('${dir.path}/catalog.db');
      server = await DemoServer.start();
      final harness = AppHarness._(
        tester,
        dir,
        db,
        MemoryPasswordStore(),
        MemoryPinStore(),
        SettingsController(db),
        server,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenBoundaryKey,
          child: IptvApp(
            db: db,
            passwords: harness.passwords,
            settings: harness.settings,
            pins: harness.pins,
            account: null,
          ),
        ),
      );
      return harness;
    } catch (_) {
      await _release(tester, dir, db, server);
      rethrow;
    }
  }

  /// Unmounts the app (disposing its players), stops the server, closes the
  /// catalog, deletes the data directory and restores the window and caret.
  Future<void> close() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    await _release(_tester, dir, db, server);
  }

  /// Releases what [start] opened; [db] and [server] may be `null` if
  /// starting failed before them.
  static Future<void> _release(
    WidgetTester tester,
    Directory dir,
    CatalogDb? db,
    DemoServer? server,
  ) async {
    await server?.close();
    db?.close();
    await dir.delete(recursive: true);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    EditableText.debugDeterministicCursor = false;
  }
}

/// Pumps until no frame is scheduled and every [Image] on screen has loaded
/// (failed loads count as done), or until [timeout] passes. Animations that
/// never stop (playing video, spinning progress) just run until [timeout]
/// without failing the test. Call it before `expectScreen`.
Future<void> settle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    final images = find.byType(Image).evaluate().toList();
    await tester.runAsync(() async {
      final loads = [
        for (final element in images)
          precacheImage(
            (element.widget as Image).image,
            element,
            onError: (_, _) {},
          ),
      ];
      await Future.wait(loads).timeout(remaining, onTimeout: () => []);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    if (!tester.binding.hasScheduledFrame) return;
  }
}
