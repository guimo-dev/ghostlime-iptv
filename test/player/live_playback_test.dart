import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/live_playback.dart';
import 'package:iptv_player/player/mpv_options.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:media_kit_video/media_kit_video.dart' show VideoController;

import 'fake_player.dart';

/// Live channel `<key>` of group `c`, streamed from `http://h/<key>.ts`.
Channel _channel(String key, String name) => Channel(
  key: key,
  name: name,
  categoryId: 'c',
  kind: MediaKind.live,
  url: 'http://h/$key.ts',
);

final _uno = _channel('a', 'Uno');
final _dos = _channel('b', 'Dos');
final _tres = _channel('t', 'Tres');

const _unsaved = Playlist(
  name: 'Lista',
  type: PlaylistType.m3uUrl,
  source: 'http://h/l.m3u',
);

void main() {
  group('LivePlayback', () {
    late FakePlayer player;
    late LivePlayback playback;

    setUp(() {
      player = FakePlayer();
      playback = LivePlayback(
        settings: () => const AppSettings(),
        playlist: _unsaved.copyWith(id: 1),
        password: Future.value(null),
        createPlayer: (_) => (player, FakeVideoController(player)),
      );
    });
    tearDown(() => playback.dispose());

    test(
      'playing the channel already playing does not open it again',
      () async {
        await playback.play(PlayTarget.fromChannel(_uno));
        await playback.play(PlayTarget.fromChannel(_uno));

        expect(player.opened, ['http://h/a.ts']);
        expect(player.current, 'http://h/a.ts');
      },
    );

    test('switching channel twice in a row only opens the last one', () async {
      await playback.play(PlayTarget.fromChannel(_uno));
      player.calls.clear();

      final second = playback.play(PlayTarget.fromChannel(_dos));
      final third = playback.play(PlayTarget.fromChannel(_tres));
      await Future.wait([second, third]);

      expect(player.opened, ['http://h/t.ts']);
      expect(player.calls.first, 'stop');
      expect(player.current, 'http://h/t.ts');
    });

    test('stop closes the stream; playing again reopens it', () async {
      await playback.play(PlayTarget.fromChannel(_uno));
      await playback.stop();
      expect(player.current, isNull);

      await playback.play(PlayTarget.fromChannel(_uno));
      expect(player.opened, ['http://h/a.ts', 'http://h/a.ts']);
    });
  });

  group('LivePlayback timers and settings', () {
    /// A playback of the test playlist on [player] (or a new fake per
    /// player creation through [createPlayer]).
    LivePlayback playbackOf({
      FakePlayer? player,
      AppSettings Function()? settings,
      PlayerFactory? createPlayer,
    }) => LivePlayback(
      settings: settings ?? () => const AppSettings(),
      playlist: _unsaved.copyWith(id: 1),
      password: Future.value(null),
      startTimeout: const Duration(seconds: 5),
      createPlayer:
          createPlayer ?? (_) => (player!, FakeVideoController(player)),
    );

    test('changing hardware decoding recreates the player with the new '
        'hwdec', () async {
      var settings = const AppSettings();
      final created = <(FakePlayer, String?)>[];
      final playback = playbackOf(
        settings: () => settings,
        createPlayer: (hwdec) {
          final player = FakePlayer();
          created.add((player, hwdec));
          return (player, FakeVideoController(player));
        },
      );
      addTearDown(playback.dispose);
      final notifiedControllers = <VideoController>[];
      playback.addListener(() {
        if (playback.hasPlayer) notifiedControllers.add(playback.controller);
      });

      await playback.play(PlayTarget.fromChannel(_uno));
      final first = playback.controller;
      settings = settings.copyWith(hardwareDecoding: false);
      await playback.play(PlayTarget.fromChannel(_dos));

      expect(created.map((c) => c.$2), [
        hwdecFor(
          hardwareDecoding: true,
          isMobile: Platform.isAndroid || Platform.isIOS,
        ),
        'no',
      ]);
      expect(created.first.$1.calls.last, 'dispose');
      expect(created.last.$1.opened, ['http://h/b.ts']);
      expect(playback.controller, isNot(same(first)));
      expect(notifiedControllers, contains(same(playback.controller)));

      await playback.play(PlayTarget.fromChannel(_tres));
      expect(created, hasLength(2), reason: 'same setting, same player');
    });

    testWidgets('a position reported before the open returns does not count '
        'as started', (tester) async {
      final player = FakePlayer()..openGate = Completer();
      final playback = playbackOf(player: player);
      final playing = playback.play(PlayTarget.fromChannel(_uno));
      await tester.pump();
      expect(player.current, 'http://h/a.ts');

      // The previous channel's position, arriving while opening.
      player.emitPosition(const Duration(seconds: 30));
      await tester.pump();
      player.openGate!.complete();
      await playing;
      await tester.pump(const Duration(seconds: 6));

      expect(playback.startFailed, isTrue);
      expect(player.current, isNull);
      playback.dispose();
    });

    testWidgets('a position after the open returns cancels the start '
        'timeout', (tester) async {
      final player = FakePlayer();
      final playback = playbackOf(player: player);
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 6));

      expect(playback.startFailed, isFalse);
      expect(player.current, 'http://h/a.ts');
      playback.dispose();
    });

    testWidgets('a live stream that ends is reopened after the first delay', (
      tester,
    ) async {
      final player = FakePlayer();
      final playback = playbackOf(player: player);
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      player.emitCompleted();
      await tester.pump(
        reconnectDelays.first - const Duration(milliseconds: 1),
      );
      expect(player.opened, ['http://h/a.ts']);

      await tester.pump(const Duration(milliseconds: 1));
      expect(player.opened, ['http://h/a.ts', 'http://h/a.ts']);
      playback.dispose();
    });

    testWidgets('a channel that ended without auto-reconnect plays again '
        'when chosen again', (tester) async {
      final player = FakePlayer();
      final playback = playbackOf(
        player: player,
        settings: () => const AppSettings(autoReconnect: false),
      );
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      player.emitCompleted();
      await tester.pump(const Duration(seconds: 10));
      expect(player.opened, ['http://h/a.ts']);

      await playback.play(PlayTarget.fromChannel(_uno));
      expect(player.opened, ['http://h/a.ts', 'http://h/a.ts']);
      playback.dispose();
    });

    testWidgets('a channel whose reconnections ran out plays again when '
        'chosen again', (tester) async {
      final player = FakePlayer();
      final playback = playbackOf(player: player);
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      for (final delay in reconnectDelays) {
        player.emitError('connection lost');
        await tester.pump(delay);
        player.emitPosition(const Duration(seconds: 1));
      }
      player.emitError('connection lost');
      await tester.pump(const Duration(seconds: 20));
      expect(player.opened, hasLength(1 + reconnectDelays.length));

      await playback.play(PlayTarget.fromChannel(_uno));
      expect(player.opened, hasLength(2 + reconnectDelays.length));
      playback.dispose();
    });

    testWidgets('a channel still reconnecting is not reopened when chosen '
        'again', (tester) async {
      final player = FakePlayer();
      final playback = playbackOf(player: player);
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      player.emitError('connection lost');
      await tester.pump();

      await playback.play(PlayTarget.fromChannel(_uno));
      expect(player.opened, ['http://h/a.ts']);
      playback.dispose();
    });

    // On Android media_kit seeks to the current position whenever the video
    // surface changes (the preview going full screen); a live stream cannot
    // seek and mpv logs it at error level.
    testWidgets('mpv refusing to seek a live stream is not an error', (
      tester,
    ) async {
      final player = FakePlayer();
      final playback = playbackOf(player: player);
      await playback.play(PlayTarget.fromChannel(_uno));
      player.emitPosition(const Duration(seconds: 1));
      player.emitError('Cannot seek in this stream.');
      player.emitError("You can force it with '--force-seekable=yes'.");
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));

      expect(playback.error, isNull);
      expect(player.opened, ['http://h/a.ts'], reason: 'no reconnection');
      playback.dispose();
    });
  });

  group('Directo with one shared player', () {
    late CatalogDb db;
    late Playlist playlist;
    late FakePlayer player;

    setUp(() {
      db = CatalogDb.inMemory();
      playlist = _unsaved.copyWith(id: db.savePlaylist(_unsaved));
      db.replaceCatalog(
        playlist.id!,
        const [Category(id: 'c', name: 'Cat', kind: MediaKind.live)],
        [_uno, _dos],
        DateTime.now(),
      );
      player = FakePlayer();
    });
    tearDown(() => db.close());

    /// Shows Directo (visible while [visible] is true, as the shell does
    /// with `TickerMode`) and opens the group.
    Future<void> pumpLive(
      WidgetTester tester, {
      ValueNotifier<bool>? visible,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shown = visible ?? ValueNotifier(true);
      await tester.pumpWidget(
        SettingsScope(
          controller: SettingsController(db),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: shown,
                builder: (context, enabled, child) =>
                    TickerMode(enabled: enabled, child: child!),
                child: LiveTvScreen(
                  db: db,
                  playlist: playlist,
                  passwords: MemoryPasswordStore(),
                  createPlayer: (_) => (player, FakeVideoController(player)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cat'));
      await tester.pump();
    }

    /// Lets routes finish their transitions (the video controls keep
    /// animating, so `pumpAndSettle` would never return).
    Future<void> settleRoutes(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> tapChannel(WidgetTester tester, String name) async {
      await tester.tap(
        find.descendant(of: find.byType(ChannelRow), matching: find.text(name)),
      );
      await tester.pump();
    }

    testWidgets('full screen from the preview keeps its stream', (
      tester,
    ) async {
      await pumpLive(tester);
      await tapChannel(tester, 'Uno');
      expect(player.opened, ['http://h/a.ts']);

      await tapChannel(tester, 'Uno');
      await settleRoutes(tester);

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(player.opened, ['http://h/a.ts']);
      expect(player.current, 'http://h/a.ts');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('going back keeps the same channel playing without reopening', (
      tester,
    ) async {
      await pumpLive(tester);
      await tapChannel(tester, 'Uno');
      await tapChannel(tester, 'Uno');
      await settleRoutes(tester);
      final callsInFullScreen = List.of(player.calls);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settleRoutes(tester);

      expect(find.byType(PlayerScreen), findsNothing);
      expect(player.calls, callsInFullScreen);
      expect(player.current, 'http://h/a.ts');
      expect(tester.widget<NowPanel>(find.byType(NowPanel)).channel?.key, 'a');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('leaving Directo stops the stream', (tester) async {
      final visible = ValueNotifier(true);
      await pumpLive(tester, visible: visible);
      await tapChannel(tester, 'Uno');
      expect(player.current, 'http://h/a.ts');

      visible.value = false;
      await tester.pump();

      expect(player.current, isNull);
      expect(player.calls.last, 'stop');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the preview stops in the background and plays again on '
        'return', (tester) async {
      await pumpLive(tester);
      await tapChannel(tester, 'Uno');

      await toBackground(tester);
      expect(player.current, isNull);

      await toForeground(tester);
      expect(player.opened, ['http://h/a.ts', 'http://h/a.ts']);
      expect(player.current, 'http://h/a.ts');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a brief interruption without going to the background keeps '
        'the preview', (tester) async {
      await pumpLive(tester);
      await tapChannel(tester, 'Uno');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(player.opened, ['http://h/a.ts']);
      expect(player.current, 'http://h/a.ts');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the full-screen channel stops in the background and plays '
        'again on return, once', (tester) async {
      await pumpLive(tester);
      await tapChannel(tester, 'Uno');
      await tapChannel(tester, 'Uno');
      await settleRoutes(tester);

      await toBackground(tester);
      expect(player.current, isNull);

      await toForeground(tester);
      await settleRoutes(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(player.opened, ['http://h/a.ts', 'http://h/a.ts']);
      expect(player.current, 'http://h/a.ts');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Directo hidden by another section stays stopped on return', (
      tester,
    ) async {
      final visible = ValueNotifier(true);
      await pumpLive(tester, visible: visible);
      await tapChannel(tester, 'Uno');
      visible.value = false;
      await tester.pump();

      await toBackground(tester);
      await toForeground(tester);

      expect(player.opened, ['http://h/a.ts']);
      expect(player.current, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('PlayerScreen with its own playback', () {
    testWidgets('a live stream stops in the background and reopens on '
        'return', (tester) async {
      final player = FakePlayer();
      await pumpPlayer(tester, player, isLive: true);
      expect(player.opened, ['http://h/live.ts']);

      await toBackground(tester);
      expect(player.current, isNull);

      await toForeground(tester);
      expect(player.opened, ['http://h/live.ts', 'http://h/live.ts']);
      expect(player.current, 'http://h/live.ts');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a video keeps its stream through the background', (
      tester,
    ) async {
      final player = FakePlayer();
      await pumpPlayer(tester, player, isLive: false);
      player.emitPosition(const Duration(seconds: 5));

      await toBackground(tester);
      await toForeground(tester);

      expect(player.opened, ['http://h/vod.mp4']);
      expect(player.current, 'http://h/vod.mp4');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a video that timed out while in the background opens again '
        'on return', (tester) async {
      final player = FakePlayer();
      await pumpPlayer(tester, player, isLive: false);

      await toBackground(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(player.current, isNull, reason: 'the start timed out');

      await toForeground(tester);
      expect(player.opened, ['http://h/vod.mp4', 'http://h/vod.mp4']);
      expect(player.current, 'http://h/vod.mp4');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Sends the app to the background as a phone does.
Future<void> toBackground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// Brings the app back from the background.
Future<void> toForeground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// Shows a [PlayerScreen] that plays a live stream or a video on [player].
Future<void> pumpPlayer(
  WidgetTester tester,
  FakePlayer player, {
  required bool isLive,
}) async {
  final db = CatalogDb.inMemory();
  addTearDown(db.close);
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: PlayerScreen(
          url: isLive ? 'http://h/live.ts' : 'http://h/vod.mp4',
          title: 'Prueba',
          isLive: isLive,
          startTimeout: const Duration(seconds: 5),
          createPlayer: (_) => (player, FakeVideoController(player)),
        ),
      ),
    ),
  );
  await tester.pump();
}
