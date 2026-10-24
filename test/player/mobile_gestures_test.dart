import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/live/live_phone_view.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/mobile_gestures.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../sync/fake_passwords.dart';
import 'fake_player.dart';

const _area = Size(900, 400);

/// Centre of the gesture area's left, middle and right thirds, above the
/// controls band.
const _left = Offset(150, 150);
const _centre = Offset(450, 150);
const _right = Offset(750, 150);

void main() {
  group('swipeAction', () {
    test('live: a long vertical swipe changes channel, up is the next', () {
      expect(
        swipeAction(const Offset(0, -120), live: true),
        SwipeAction.nextChannel,
      );
      expect(
        swipeAction(const Offset(10, 120), live: true),
        SwipeAction.previousChannel,
      );
    });

    test('a move shorter than the threshold is a tap, not a swipe', () {
      final short = swipeMinDistance - 1;
      expect(swipeAction(Offset(0, short), live: true), isNull);
      expect(swipeAction(Offset(short, 0), live: false), isNull);
    });

    test('a diagonal move does nothing', () {
      expect(swipeAction(const Offset(100, -120), live: true), isNull);
      expect(swipeAction(const Offset(120, 100), live: false), isNull);
    });

    test('live ignores horizontal swipes and VOD vertical ones', () {
      expect(swipeAction(const Offset(200, 0), live: true), isNull);
      expect(swipeAction(const Offset(0, 200), live: false), isNull);
    });

    test('VOD: a horizontal swipe seeks, right goes forward', () {
      expect(
        swipeAction(const Offset(120, 5), live: false),
        SwipeAction.seekForward,
      );
      expect(
        swipeAction(const Offset(-120, 0), live: false),
        SwipeAction.seekBack,
      );
    });
  });

  group('gestureZone', () {
    test('live: brightness, channel and volume thirds', () {
      expect(
        gestureZone(100, 900, live: true, levels: true),
        GestureZone.brightness,
      );
      expect(
        gestureZone(450, 900, live: true, levels: true),
        GestureZone.channel,
      );
      expect(
        gestureZone(800, 900, live: true, levels: true),
        GestureZone.volume,
      );
    });

    test('VOD: brightness on the left half, volume on the right', () {
      expect(
        gestureZone(400, 900, live: false, levels: true),
        GestureZone.brightness,
      );
      expect(
        gestureZone(500, 900, live: false, levels: true),
        GestureZone.volume,
      );
    });

    test('without the setting there is no volume nor brightness', () {
      expect(
        gestureZone(100, 900, live: true, levels: false),
        GestureZone.channel,
      );
      expect(
        gestureZone(800, 900, live: true, levels: false),
        GestureZone.channel,
      );
      expect(gestureZone(100, 900, live: false, levels: false), isNull);
      expect(gestureZone(800, 900, live: false, levels: false), isNull);
    });
  });

  group('MobileGestures', () {
    late List<int> steps;
    late List<Duration> seeks;
    late double volume;
    late int taps;
    late List<MethodCall> brightnessCalls;

    setUp(() {
      steps = [];
      seeks = [];
      volume = 50;
      taps = 0;
      brightnessCalls = [];
    });

    Future<void> pumpGestures(
      WidgetTester tester, {
      required bool live,
      bool levels = true,
    }) async {
      tester.view.physicalSize = _area;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        brightnessChannel,
        (call) async {
          brightnessCalls.add(call);
          return call.method == 'get' ? 0.5 : null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          brightnessChannel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MobileGestures(
            live: live,
            levels: levels,
            onChannelStep: steps.add,
            onSeek: seeks.add,
            volume: () => volume,
            onVolume: (value) => volume = value,
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Calls to the brightness channel other than reading it.
    List<String> brightnessChanges() => [
      for (final call in brightnessCalls)
        if (call.method != 'get') call.method,
    ];

    testWidgets('a tap reaches the video controls and changes nothing', (
      tester,
    ) async {
      await pumpGestures(tester, live: true);

      await tester.tapAt(_centre);
      await tester.pump();

      expect(taps, 1);
      expect(steps, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('live: a short vertical move does not change channel', (
      tester,
    ) async {
      await pumpGestures(tester, live: true);

      await tester.dragFrom(_centre, Offset(0, -(swipeMinDistance - 10)));
      await tester.pump();

      expect(steps, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('live: swiping up in the centre goes to the next channel, '
        'down to the previous', (tester) async {
      await pumpGestures(tester, live: true);

      await tester.dragFrom(_centre, const Offset(0, -120));
      await tester.pump();
      await tester.dragFrom(
        _centre + const Offset(0, -100),
        const Offset(0, 120),
      );
      await tester.pump();

      expect(steps, [1, -1]);
      expect(volume, 50);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('live: horizontal swipes do nothing', (tester) async {
      await pumpGestures(tester, live: true);

      await tester.dragFrom(_centre, const Offset(200, 0));
      await tester.pump();

      expect(steps, isEmpty);
      expect(seeks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a swipe starting on the controls band is left to them', (
      tester,
    ) async {
      await pumpGestures(tester, live: false);

      await tester.dragFrom(
        Offset(450, _area.height - controlsBandHeight + 10),
        const Offset(200, 0),
      );
      await tester.pump();

      expect(seeks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('VOD: horizontal swipes seek 10 s, vertical ones do not', (
      tester,
    ) async {
      await pumpGestures(tester, live: false);

      await tester.dragFrom(_centre, const Offset(150, 0));
      await tester.pump();
      await tester.dragFrom(_centre, const Offset(-150, 0));
      await tester.pump();

      expect(seeks, [seekStep, -seekStep]);
      expect(steps, isEmpty);
      // The "+10 s" label goes away by itself.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('live: the right third sets the volume, not the channel', (
      tester,
    ) async {
      await pumpGestures(tester, live: true);

      await tester.dragFrom(_right, const Offset(0, -120));
      await tester.pump();

      expect(volume, greaterThan(50));
      expect(steps, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('swiping down on the right lowers the volume to 0 at most', (
      tester,
    ) async {
      await pumpGestures(tester, live: false);

      await tester.dragFrom(
        _right + const Offset(0, -140),
        const Offset(0, 380),
      );
      await tester.pump();

      expect(volume, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the left side sets the window brightness and leaving '
        'restores it', (tester) async {
      await pumpGestures(tester, live: true);

      await tester.dragFrom(_left, const Offset(0, -120));
      await tester.pump();

      expect(brightnessChanges(), everyElement('set'));
      final last = brightnessCalls.lastWhere((c) => c.method == 'set');
      expect(last.arguments as double, greaterThan(0.5));
      expect(last.arguments as double, lessThanOrEqualTo(1));
      expect(steps, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(brightnessCalls.last.method, 'reset');
    });

    testWidgets('leaving without touching the brightness does not reset it', (
      tester,
    ) async {
      await pumpGestures(tester, live: true);
      await tester.dragFrom(_centre, const Offset(0, -120));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(brightnessChanges(), isEmpty);
    });

    testWidgets('setting off: no volume nor brightness, the whole width '
        'changes channel', (tester) async {
      await pumpGestures(tester, live: true, levels: false);

      await tester.dragFrom(_right, const Offset(0, -120));
      await tester.pump();
      await tester.dragFrom(_left, const Offset(0, 120));
      await tester.pump();

      expect(steps, [1, -1]);
      expect(volume, 50);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(brightnessChanges(), isEmpty);
    });

    testWidgets('setting off in a VOD: vertical swipes change nothing', (
      tester,
    ) async {
      await pumpGestures(tester, live: false, levels: false);

      await tester.dragFrom(_right, const Offset(0, -120));
      await tester.pump();
      await tester.dragFrom(_left, const Offset(0, -120));
      await tester.pump();

      expect(volume, 50);
      expect(seeks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(brightnessChanges(), isEmpty);
    });

    testWidgets('on a desktop there are no gestures', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpGestures(tester, live: true);

        await tester.dragFrom(_centre, const Offset(0, -120));
        await tester.dragFrom(_right, const Offset(0, -120));
        await tester.pump();

        expect(steps, isEmpty);
        expect(volume, 50);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('setting', () {
    Future<SettingsController> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = CatalogDb.inMemory();
      addTearDown(db.close);
      final controller = SettingsController(db);
      await tester.pumpWidget(
        SettingsScope(
          controller: controller,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: SettingsScreen(db: db, passwords: FakePasswords()),
          ),
        ),
      );
      await tester.pump();
      return controller;
    }

    testWidgets('on a phone it is shown, on by default, and turns off', (
      tester,
    ) async {
      final controller = await pumpSettings(tester);
      final row = find.text('Gestos de volumen y brillo');
      expect(row, findsOneWidget);
      expect(controller.value.volumeBrightnessGestures, isTrue);

      // The switch on the same line as the label.
      final labelY = tester.getCenter(row).dy;
      final switches = find.byType(Switch);
      final toggle =
          [for (var i = 0; i < switches.evaluate().length; i++) switches.at(i)]
              .reduce(
                (a, b) =>
                    (tester.getCenter(a).dy - labelY).abs() <=
                        (tester.getCenter(b).dy - labelY).abs()
                    ? a
                    : b,
              );
      await tester.tap(toggle);
      await tester.pump();

      expect(controller.value.volumeBrightnessGestures, isFalse);
    });

    testWidgets('on a desktop it is not shown', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpSettings(tester);
        expect(find.text('Gestos de volumen y brillo'), findsNothing);
        expect(find.text('Decodificación por hardware'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('full-screen live player', () {
    late CatalogDb db;
    late Playlist playlist;
    late FakePlayer player;

    setUp(() {
      db = CatalogDb.inMemory();
      const unsaved = Playlist(
        name: 'Lista',
        type: PlaylistType.m3uUrl,
        source: 'http://h/l.m3u',
      );
      playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
      db.replaceCatalog(
        playlist.id!,
        const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
        [
          for (final (key, name) in [
            ('a', 'Uno'),
            ('b', 'Dos'),
            ('c', 'Tres'),
            ('d', 'Cuatro'),
          ])
            Channel(
              key: key,
              name: name,
              categoryId: 'c',
              kind: MediaKind.live,
              url: 'http://h/$key.ts',
            ),
        ],
        DateTime.now(),
      );
      player = FakePlayer();
    });
    tearDown(() => db.close());

    /// Directo on a phone in landscape, full screen on channel "Uno".
    Future<void> pumpFullScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SettingsScope(
          controller: SettingsController(db),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: LiveTvScreen(
                db: db,
                playlist: playlist,
                passwords: MemoryPasswordStore(),
                createPlayer: (_) => (player, FakeVideoController(player)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(PhoneChannelRow),
          matching: find.text('Uno'),
        ),
      );
      await _settleRoutes(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
    }

    /// A vertical swipe in the middle of the player.
    Future<void> swipe(WidgetTester tester, double dy) async {
      final centre = tester.getCenter(find.byType(MobileGestures));
      await tester.dragFrom(centre - Offset(0, dy / 2), Offset(0, dy));
      await tester.pump();
    }

    String appBarTitle(WidgetTester tester) => tester
        .widget<Text>(
          find
              .descendant(of: find.byType(AppBar), matching: find.byType(Text))
              .first,
        )
        .data!;

    testWidgets('swiping up and down zaps through the group', (tester) async {
      await pumpFullScreen(tester);

      await swipe(tester, -150);
      expect(player.current, 'http://h/b.ts');
      expect(appBarTitle(tester), 'Dos');

      await swipe(tester, 150);
      expect(player.current, 'http://h/a.ts');
      expect(appBarTitle(tester), 'Uno');

      // Before the first channel comes the last one.
      await swipe(tester, 150);
      expect(player.current, 'http://h/d.ts');
      expect(appBarTitle(tester), 'Cuatro');
      await _leave(tester);
    });

    testWidgets('fast swipes: the last channel wins with one stream', (
      tester,
    ) async {
      await pumpFullScreen(tester);
      player.openGate = Completer<void>();

      await swipe(tester, -150);
      await swipe(tester, -150);
      await swipe(tester, -150);
      player.openGate!.complete();
      await _settleRoutes(tester);

      expect(player.current, 'http://h/d.ts');
      expect(player.opened.last, 'http://h/d.ts');
      expect(appBarTitle(tester), 'Cuatro');
      // Never two streams: every open but the first follows a stop.
      final calls = player.calls.where((c) => c != 'dispose').toList();
      for (var i = 1; i < calls.length; i++) {
        if (calls[i].startsWith('open ')) {
          expect(calls[i - 1], 'stop', reason: 'calls: $calls');
        }
      }

      // Back in the list, the preview shows the channel zapped to.
      await tester.binding.handlePopRoute();
      await _settleRoutes(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(player.current, 'http://h/d.ts');
      await _leave(tester);
    });
  });
}

/// Lets routes finish their transitions (the video controls keep animating,
/// so `pumpAndSettle` would never return).
Future<void> _settleRoutes(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Removes the app and lets the video controls' timers (started by the
/// swipes) run out.
Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 4));
}
