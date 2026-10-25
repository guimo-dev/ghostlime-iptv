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
  });
}
