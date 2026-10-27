import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/live_playback.dart';
import 'package:iptv_player/player/mpv_options.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/player/tv_live_controls.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:media_kit/media_kit.dart'
    show AudioTrack, PlayerState, SubtitleTrack, Track, Tracks;
import 'package:media_kit_video/media_kit_video.dart';

import '../tv/tv_harness.dart';
import 'fake_player.dart';

/// The fixed time of these tests.
final _now = DateTime.utc(2026, 10, 25, 20, 30);

void main() {
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
      const [
        Category(id: 'c', name: 'Generalistas', kind: MediaKind.live),
        Category(id: 'o', name: 'Otros', kind: MediaKind.live),
      ],
      [
        for (var i = 1; i <= 15; i++)
          Channel(
            key: 'k$i',
            name: 'Canal $i',
            categoryId: 'c',
            kind: MediaKind.live,
            epgId: i == 1 ? 'e1' : null,
            url: 'http://h/k$i.ts',
          ),
        for (final name in ['Alfa', 'Beta'])
          Channel(
            key: name,
            name: name,
            categoryId: 'o',
            kind: MediaKind.live,
            url: 'http://h/$name.ts',
          ),
      ],
      _now,
    );
    db.replaceEpg(playlist.id!, [
      Programme(
        channelId: 'e1',
        start: _now.subtract(const Duration(minutes: 30)),
        stop: _now.add(const Duration(minutes: 30)),
        title: 'Noticias de la noche',
      ),
      Programme(
        channelId: 'e1',
        start: _now.add(const Duration(minutes: 30)),
        stop: _now.add(const Duration(minutes: 90)),
        title: 'Cine de madrugada',
      ),
    ], _now);
    player = FakePlayer();
  });
  tearDown(() => db.close());

  /// Directo on a TV, with the focus on the row of "Canal 1"; channels fail
  /// to start after [startTimeout].
  Future<void> pumpDirecto(
    WidgetTester tester, {
    Duration startTimeout = streamStartTimeout,
  }) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      db,
      Scaffold(
        body: LiveTvScreen(
          db: db,
          playlist: playlist,
          passwords: MemoryPasswordStore(),
          clock: () => _now,
          previewStartTimeout: startTimeout,
          createPlayer: (_) => (player, FakeVideoController(player)),
        ),
      ),
    );
    final name = find.descendant(
      of: find.byType(ChannelRow),
      matching: find.text('Canal 1'),
    );
    Focus.of(tester.element(name)).requestFocus();
    await tester.pump();
  }

  /// Directo on a TV, full screen on "Canal 1" (OK twice on its row).
  Future<void> pumpFullScreen(
    WidgetTester tester, {
    Duration startTimeout = streamStartTimeout,
  }) async {
    await pumpDirecto(tester, startTimeout: startTimeout);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.current, 'http://h/k1.ts');
  }

  /// The key of the channel row with the primary focus in the channel list.
  String? focusedChannel() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? key;
    context.visitAncestorElements((element) {
      final widgetKey = element.widget.key;
      if (widgetKey is ValueKey<String> &&
          widgetKey.value.startsWith('tv-channel-')) {
        key = widgetKey.value.substring('tv-channel-'.length);
        return false;
      }
      return true;
    });
    return key;
  }

  /// Checks that no two streams were ever open: every open but the first
  /// follows a stop.
  void expectOneStreamAtATime() {
    final calls = player.calls
        .where((c) => c.startsWith('open ') || c == 'stop')
        .toList();
    for (var i = 1; i < calls.length; i++) {
      if (calls[i].startsWith('open ')) {
        expect(calls[i - 1], 'stop', reason: 'calls: $calls');
      }
    }
  }

  testWidgets('on a TV the live player has no media_kit controls', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    final video = tester.widget<Video>(find.byType(Video));
    expect(video.controls, isNull);
    expect(find.byType(TvLiveControls), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await _leave(tester);
  });

  testWidgets('Up, Down, CH+ and CH- change channel in the group', (
    tester,
  ) async {
    await pumpFullScreen(tester);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(player.current, 'http://h/k2.ts');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(player.current, 'http://h/k1.ts');
    // Before the first channel comes the last one.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(player.current, 'http://h/k15.ts');
    await _press(tester, LogicalKeyboardKey.channelUp);
    expect(player.current, 'http://h/k1.ts');
    await _press(tester, LogicalKeyboardKey.channelDown);
    expect(player.current, 'http://h/k15.ts');
    // Zapping shows the channel it lands on.
    expect(find.text('Canal 15'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('five fast presses end on the last channel with one stream', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    player.openGate = Completer<void>();

    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 50));
    }
    player.openGate!.complete();
    await _settle(tester);

    expect(player.current, 'http://h/k6.ts');
    expect(player.opened.last, 'http://h/k6.ts');
    expectOneStreamAtATime();
    await _leave(tester);
  });

  testWidgets('OK shows the info bar with the programmes on air and next', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    expect(find.text('Noticias de la noche'), findsNothing);

    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Canal 1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Noticias de la noche'), findsOneWidget);
    expect(find.textContaining('Cine de madrugada'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-info-progress')), findsOneWidget);

    // A channel without guide says so.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('Canal 2'), findsOneWidget);
    expect(find.text('Sin guía'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a second OK opens the channel list on the current channel', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(player.current, 'http://h/k3.ts');
    // Zapping showed the info bar: hide it first.
    await _back(tester);

    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-channel-list')), findsOneWidget);
    expect(focusedChannel(), 'k3');
    // No groups in this list.
    expect(find.byKey(const ValueKey('tv-group-list')), findsNothing);

    // Down and OK zap to the next channel and close the list.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedChannel(), 'k4');
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.current, 'http://h/k4.ts');
    expect(find.byKey(const ValueKey('tv-channel-list')), findsNothing);
    expectOneStreamAtATime();
    await _leave(tester);
  });

  testWidgets('Left opens the list with the groups', (tester) async {
    await pumpFullScreen(tester);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    final groups = find.byKey(const ValueKey('tv-group-list'));
    expect(groups, findsOneWidget);
    for (final name in ['Favoritos', 'Recientes', 'Generalistas', 'Otros']) {
      expect(
        find.descendant(of: groups, matching: find.text(name)),
        findsOneWidget,
      );
    }
    // The focus is on the group shown.
    expect(
      find.descendant(
        of: groups,
        matching: find.byElementPredicate(
          (e) => e == FocusManager.instance.primaryFocus?.context,
        ),
      ),
      findsOneWidget,
    );

    // Down to "Otros" and OK shows its channels; OK on one plays it.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Alfa'), findsOneWidget);
    expect(focusedChannel(), 'Alfa');
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.current, 'http://h/Alfa.ts');
    expectOneStreamAtATime();

    // Zapping now goes through that group.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(player.current, 'http://h/Beta.ts');
    await _leave(tester);
  });

  testWidgets('Right and Menu open the audio and subtitle tracks', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    player.fakeState = PlayerState(
      tracks: Tracks(
        audio: [
          AudioTrack.auto(),
          AudioTrack.no(),
          const AudioTrack('1', 'Español', 'spa'),
          const AudioTrack('2', null, 'eng'),
        ],
        subtitle: [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          const SubtitleTrack('3', 'Inglés', 'eng'),
        ],
      ),
      track: const Track(audio: AudioTrack('1', 'Español', 'spa')),
    );

    await _press(tester, LogicalKeyboardKey.arrowRight);
    final options = find.byKey(const ValueKey('tv-options'));
    expect(options, findsOneWidget);
    for (final text in ['Audio', 'Español', 'eng', 'Subtítulos', 'Inglés']) {
      expect(
        find.descendant(of: options, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: options, matching: find.text('Desactivados')),
      findsOneWidget,
    );

    await tester.tap(find.text('eng'));
    await tester.pump();
    expect(player.calls, contains('audio 2'));
    await tester.tap(find.text('Inglés'));
    await tester.pump();
    expect(player.calls, contains('subtitle 3'));

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(options, findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.contextMenu);
    expect(options, findsOneWidget);
    await _leave(tester);
  });

  testWidgets('typing 1 and 2 shows 12 and jumps there after 1.5 s', (
    tester,
  ) async {
    await pumpFullScreen(tester);

    await _press(tester, LogicalKeyboardKey.digit1);
    await _press(tester, LogicalKeyboardKey.digit2);
    expect(find.byKey(const ValueKey('tv-typed')), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(player.current, 'http://h/k1.ts');

    await tester.pump(const Duration(milliseconds: 1600));
    expect(player.current, 'http://h/k12.ts');
    expect(find.byKey(const ValueKey('tv-typed')), findsNothing);
    expectOneStreamAtATime();
    await _leave(tester);
  });

  testWidgets('a number without a channel says so and stays', (tester) async {
    await pumpFullScreen(tester);

    await _press(tester, LogicalKeyboardKey.digit9);
    await _press(tester, LogicalKeyboardKey.digit9);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Canal 99 no existe'), findsOneWidget);
    expect(player.opened, ['http://h/k1.ts']);
    await _leave(tester);
  });

  testWidgets('Back closes layer by layer, then returns to Directo', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(player.current, 'http://h/k2.ts');
    expect(find.byKey(const ValueKey('tv-info')), findsOneWidget);
    await _back(tester);
    // Zapping showed the info bar: Back hides it first.
    expect(find.byKey(const ValueKey('tv-info')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-channel-list')), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const ValueKey('tv-channel-list')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const ValueKey('tv-options')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.digit3);
    await _back(tester);
    expect(find.byKey(const ValueKey('tv-typed')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    final opened = player.opened.length;
    await _back(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    // Directo previews the same channel, without opening it again.
    expect(player.current, 'http://h/k2.ts');
    expect(player.opened.length, opened);
    expect(find.text('Canal 2'), findsWidgets);
    await _leave(tester);
  });

  testWidgets('back in Directo the row of the channel zapped to has the '
      'focus, and OK goes full screen on it', (tester) async {
    await pumpFullScreen(tester);
    await _press(tester, LogicalKeyboardKey.digit1);
    await _press(tester, LogicalKeyboardKey.digit2);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(player.current, 'http://h/k12.ts');
    await _back(tester);
    await _back(tester);
    expect(find.byType(PlayerScreen), findsNothing);

    final focused = FocusManager.instance.primaryFocus!.context!;
    final row = focused.findAncestorWidgetOfExactType<ChannelRow>();
    expect(row?.channel.key, 'k12');
    expect(
      viewRect(tester).contains(tester.getCenter(find.byWidget(row!))),
      isTrue,
    );

    final opened = player.opened.length;
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.current, 'http://h/k12.ts');
    expect(player.opened.length, opened);
    await _leave(tester);
  });

  testWidgets('play/pause on the remote toggles the live player', (
    tester,
  ) async {
    await pumpFullScreen(tester);
    await _press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(player.calls, contains('playOrPause'));
    await _leave(tester);
  });

  testWidgets('the list and the options hide the start error', (tester) async {
    await pumpFullScreen(tester, startTimeout: const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    const failed = 'No se ha podido abrir el canal';
    expect(find.text(failed), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    final list = find.byKey(const ValueKey('tv-channel-list'));
    expect(list, findsOneWidget);
    expect(find.text(failed), findsNothing);
    expect(focusedChannel(), 'k1');
    final rect = tester.getRect(list);
    expect(viewRect(tester).contains(rect.topLeft), isTrue);
    expect(
      viewRect(tester).contains(rect.bottomRight - const Offset(1, 1)),
      isTrue,
    );

    await _back(tester);
    expect(find.text(failed), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    expect(find.text(failed), findsNothing);
    await _leave(tester);
  });

  testWidgets('the options open over a playback error, which hides under '
      'them', (tester) async {
    await pumpFullScreen(tester);
    player.emitError('Error decoding audio.');
    await tester.pump();
    await tester.pump();
    const error = 'Error: Error decoding audio.';
    expect(find.text(error), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    expect(find.text(error), findsNothing);
    await _back(tester);
    expect(find.byKey(const ValueKey('tv-options')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a channel picked in another group clears the filter of '
      'Directo', (tester) async {
    await pumpDirecto(tester);
    await tester.enterText(find.byType(TextField), 'Canal 1');
    await tester.pump();
    final name = find.descendant(
      of: find.byType(ChannelRow),
      matching: find.text('Canal 1'),
    );
    Focus.of(tester.element(name)).requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.current, 'http://h/Beta.ts');
    await _back(tester);
    await _back(tester);
    expect(find.byType(PlayerScreen), findsNothing);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    final beta = find.ancestor(
      of: find.text('Beta'),
      matching: find.byType(ChannelRow),
    );
    expect(beta, findsOneWidget);
    expect(tester.widget<ChannelRow>(beta).number, 2);
    await _leave(tester);
  });

  testWidgets('without the group playing among the groups, the first one '
      'takes the focus', (tester) async {
    useTvView(tester);
    final playback = LivePlayback(
      settings: () => AppSettings(),
      createPlayer: (_) => (player, FakeVideoController(player)),
    );
    addTearDown(playback.dispose);
    await pumpTvApp(
      tester,
      db,
      Scaffold(
        body: TvLiveControls(
          playback: playback,
          title: 'Canal',
          source: _FixedSource(
            groupId: 'hidden',
            groups: const [('a', 'Primero'), ('b', 'Segundo')],
          ),
        ),
      ),
    );
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.text('Primero'),
      ),
      findsOneWidget,
    );
    // The focus is on that tile alone, not on something around both.
    expect(
      find.descendant(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.text('Segundo'),
      ),
      findsNothing,
    );
    await _leave(tester);
  });

  testWidgets('in Directo OK previews a channel and OK again goes full '
      'screen', (tester) async {
    await pumpDirecto(tester);

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(player.current, 'http://h/k1.ts');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.opened, ['http://h/k1.ts']);
    await _leave(tester);
  });
}

/// Directo's channels as a fixed list: the group playing is [groupId], and
/// [groups] the ones offered.
class _FixedSource implements TvLiveSource {
  _FixedSource({required this.groupId, required this.groups});

  final String groupId;
  final List<(String, String)> groups;

  @override
  Channel? get currentChannel => null;

  @override
  String? get currentGroupId => groupId;

  @override
  List<(String, String)> get groupChoices => groups;

  @override
  List<Channel> channelsOf(String groupId) => const [];

  @override
  String channelName(Channel channel) => channel.name;

  @override
  Map<String, (Programme?, Programme?)> guideOf(List<Channel> channels) =>
      const {};

  @override
  DateTime now() => _now;

  @override
  void playChannel(Channel channel, String groupId) {}
}

/// Presses and releases [key], then lets a frame run.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The system Back, as Android sends it when no widget takes the key.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

/// Lets routes finish their transitions (the preview's loader keeps
/// animating, so `pumpAndSettle` would never return).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Removes the app and lets the pending timers run out.
Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}
