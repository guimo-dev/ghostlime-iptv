import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/marquee_text.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import '../../test/sync/fake_account.dart';
import '../../tool/demo_server/demo_server.dart';

/// Key of the [RepaintBoundary] around the app that `expectScreen` captures.
final screenBoundaryKey = GlobalKey(debugLabel: 'screen');

/// Window size of the compact layout.
const smallSize = Size(1024, 700);

/// Window size of the usual desktop layout.
const mediumSize = Size(1440, 900);

/// Window size of a phone held upright (phone layout, bottom bar).
const phoneSize = Size(390, 844);

/// Window size of a portrait tablet (still the phone layout: under 1024 wide).
const tabletSize = Size(800, 1280);

/// Canvas of a TV (`TvScale` lays every TV out at 1280x720). The tests that
/// use it force the TV mode themselves (`debugTvDevice`).
const tvSize = Size(1280, 720);

/// Folder name of the references for [size]: `small`, `medium`, `phone`,
/// `tablet`, `tv` or `<w>x<h>`.
String sizeName(Size size) {
  if (size == smallSize) return 'small';
  if (size == mediumSize) return 'medium';
  if (size == phoneSize) return 'phone';
  if (size == tabletSize) return 'tablet';
  if (size == tvSize) return 'tv';
  return '${size.width.toInt()}x${size.height.toInt()}';
}

/// The real app on throwaway data: a temp catalog, in-memory passwords and
/// PIN, no account unless asked for a signed-in fake one, and a local demo
/// server to add as a playlist.
class AppHarness {
  AppHarness._(
    this._tester,
    this.dir,
    this.db,
    this.passwords,
    this.pins,
    this.settings,
    this.server,
    this.account,
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

  /// Account over fakes (no network, no real secure storage), signed in
  /// unless it is a first run, or `null` as in a build without Supabase.
  final AccountService? account;

  /// Starts the app in a window of [size] logical pixels at device pixel
  /// ratio 1.0, with a non-blinking caret, and pumps the first frame. The
  /// device's insets (status bar, keyboard) are zeroed as on Windows: on a
  /// phone they come in physical pixels, which at ratio 1.0 would take two or
  /// three times their real share of the window. With
  /// [signedIn] the account is created and signed in first (as
  /// `demo@example.com`). The welcome is marked done and the terms accepted,
  /// unless [firstRun] asks for a new installation (with a signed-out account,
  /// as in a build with Supabase). Whatever was opened is released again if
  /// starting fails.
  static Future<AppHarness> start(
    WidgetTester tester, {
    required Size size,
    bool signedIn = false,
    bool firstRun = false,
  }) async {
    MediaKit.ensureInitialized();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    tester.view.viewInsets = FakeViewPadding.zero;
    EditableText.debugDeterministicCursor = true;
    // Channel names in the phone guide would scroll forever: settle and
    // pumpAndSettle would never end and captures would catch them mid-way.
    MarqueeText.enabled = false;
    final dir = await Directory.systemTemp.createTemp('ghostlime_visual_');
    CatalogDb? db;
    DemoServer? server;
    try {
      db = CatalogDb.open('${dir.path}/catalog.db');
      if (!firstRun) {
        db.saveWelcomeDone();
        db.saveAcceptedTermsVersion(termsVersion);
      }
      server = await DemoServer.start();
      final passwords = MemoryPasswordStore();
      final account = signedIn || firstRun
          ? AccountService(
              db: db,
              auth: FakeAuthGateway({}),
              backend: InMemorySyncBackend(),
              keys: FakeKeyStore(),
              passwords: passwords,
            )
          : null;
      final harness = AppHarness._(
        tester,
        dir,
        db,
        passwords,
        MemoryPinStore(),
        SettingsController(db),
        server,
        account,
      );
      if (account != null && signedIn) {
        await tester.runAsync(
          () => account.signUp('demo@example.com', 'demo password'),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenBoundaryKey,
          child: IptvApp(
            db: db,
            passwords: harness.passwords,
            settings: harness.settings,
            pins: harness.pins,
            account: harness.account,
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
  /// catalog, deletes the data directory and restores the window, caret and marquee.
  Future<void> close() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    account?.dispose();
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
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
    EditableText.debugDeterministicCursor = false;
    MarqueeText.enabled = true;
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
