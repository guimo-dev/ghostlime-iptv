import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/player/tv_vod_controls.dart';
import 'package:iptv_player/ui/tv_device.dart';
import 'package:media_kit/media_kit.dart'
    show AudioTrack, PlayerState, SubtitleTrack, Track, Tracks;
import 'package:media_kit_video/media_kit_video.dart';

import '../tv/tv_harness.dart';
import 'fake_player.dart';

void main() {
  late CatalogDb db;
  late FakePlayer player;

  /// Progress reported by the player, as `(position, duration)`.
  late List<(Duration, Duration)> progress;

  setUp(() {
    db = CatalogDb.inMemory();
    player = FakePlayer()
      ..fakeState = const PlayerState(
        position: Duration(minutes: 5),
        duration: Duration(minutes: 100),
      );
    progress = [];
  });
  tearDown(() => db.close());

  /// A movie playing full screen on a TV, over a page it returns to.
  Future<void> pumpMovie(
    WidgetTester tester, {
    VoidCallback? onNext,
    bool tv = true,
  }) async {
    if (tv) {
      useTvView(tester);
    } else {
      addTearDown(() => debugTvDevice = null);
      debugTvDevice = false;
    }
    await pumpTvApp(tester, db, const Scaffold(body: Text('Ficha')));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              url: 'http://h/movie.mp4',
              title: 'La película',
              onProgress: (position, duration) =>
                  progress.add((position, duration)),
              onNext: onNext,
              nextTitle: onNext == null ? null : 'Episodio 2',
              createPlayer: (_) => (player, FakeVideoController(player)),
            ),
          ),
        );
    await _settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
  }

  /// The seeks asked of the player, in seconds.
  List<int> seeks() => [
    for (final call in player.calls)
      if (call.startsWith('seek ')) int.parse(call.substring(5)),
  ];

  final controls = find.byKey(const ValueKey('tv-vod-controls'));

  testWidgets('on a TV a movie has the remote controls, without media_kit '
      'controls nor app bar', (tester) async {
    await pumpMovie(tester);
    expect(tester.widget<Video>(find.byType(Video)).controls, isNull);
    expect(find.byType(TvVodControls), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await _leave(tester);
  });

  testWidgets('off a TV a movie keeps the media_kit controls', (tester) async {
    await pumpMovie(tester, tv: false);
    expect(
      tester.widget<Video>(find.byType(Video)).controls,
      AdaptiveVideoControls,
    );
    expect(find.byType(TvVodControls), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('OK pauses and resumes', (tester) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.calls.where((c) => c == 'playOrPause'), hasLength(2));
    await _leave(tester);
  });

  testWidgets('Left and Right jump 10 s, from where the last jump went', (
    tester,
  ) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(seeks(), [310, 320, 310]);
    // The bar shows where the jumps go.
    expect(controls, findsOneWidget);
    expect(find.text('5:10'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('holding Right jumps 10 s every 250 ms, and 30 s after 2 s', (
    tester,
  ) async {
    await pumpMovie(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    // Android repeats a held key about every 50 ms.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // The press and one repeat every 250 ms (13 jumps in 3 s): 10 s each
    // until 2 s, then 30 s.
    expect(seeks(), [
      310, 320, 330, 340, 350, 360, 370, 380, //
      410, 440, 470, 500, 530,
    ]);

    // Released, a press jumps 10 s again.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(seeks().last, 540);
    await _leave(tester);
  });

  testWidgets(
    'holding fast forward or rewind is throttled like Right and Left',
    (tester) async {
      await pumpMovie(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaFastForward);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.mediaFastForward);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump();
      // As holding Right: the press and one repeat every 250 ms, 30 s each
      // after 2 s.
      expect(seeks(), [
        310, 320, 330, 340, 350, 360, 370, 380, //
        410, 440, 470, 500, 530,
      ]);

      final before = seeks().length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaRewind);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.mediaRewind);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaRewind);
      await tester.pump();
      // One second held: the press and a repeat every 250 ms (5 jumps, not 21).
      expect(seeks().length - before, 5);
      await _leave(tester);
    },
  );

  testWidgets('jumps stop 2 s before the end, without seeking again there', (
    tester,
  ) async {
    player.fakeState = const PlayerState(
      position: Duration(seconds: 4),
      duration: Duration(seconds: 15),
    );
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(seeks(), [0, 10, 13]);
    await _leave(tester);
  });

  testWidgets('the bar shows where a jump goes until the player gets there '
      'or for 1 s', (tester) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('5:10'), findsOneWidget);
    player.emitPosition(const Duration(seconds: 312));
    await tester.pump();
    await tester.pump();
    expect(find.text('5:12'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('5:20'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5:20'), findsNothing);
    expect(controls, findsOneWidget);
    await _leave(tester);
  });

  testWidgets('Up and Down show the controls with the progress for 4 s', (
    tester,
  ) async {
    await pumpMovie(tester);
    expect(controls, findsNothing);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(controls, findsOneWidget);
    expect(
      find.descendant(of: controls, matching: find.text('La película')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tv-vod-progress')), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('1:40:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(controls, findsNothing);
    expect(seeks(), isEmpty);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(controls, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(controls, findsNothing);
    await _leave(tester);
  });

  testWidgets('play/pause, fast forward and rewind on the remote', (
    tester,
  ) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(player.calls, contains('playOrPause'));
    await _press(tester, LogicalKeyboardKey.mediaFastForward);
    await _press(tester, LogicalKeyboardKey.mediaRewind);
    await _press(tester, LogicalKeyboardKey.mediaRewind);
    expect(seeks(), [310, 300, 290]);
    await _leave(tester);
  });

  testWidgets('the separate play and pause keys play and pause', (
    tester,
  ) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.mediaPause);
    await _press(tester, LogicalKeyboardKey.mediaPause);
    await _press(tester, LogicalKeyboardKey.mediaPlay);
    expect(player.calls.where((c) => c == 'pause'), hasLength(2));
    expect(player.calls.where((c) => c == 'play'), hasLength(1));
    expect(player.calls, isNot(contains('playOrPause')));
    await _leave(tester);
  });

  testWidgets('Menu opens the audio and subtitle options', (tester) async {
    player.fakeState = PlayerState(
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 100),
      tracks: Tracks(
        audio: const [
          AudioTrack('1', 'Castellano', 'spa'),
          AudioTrack('2', null, 'eng'),
        ],
        subtitle: [SubtitleTrack.no(), const SubtitleTrack('3', null, 'spa')],
      ),
      track: const Track(audio: AudioTrack('1', 'Castellano', 'spa')),
    );
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.contextMenu);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Subtítulos'), findsOneWidget);

    // The arrows move through the options, without seeking.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(player.calls, contains('audio 2'));
    expect(seeks(), isEmpty);

    await _back(tester);
    expect(find.byKey(const ValueKey('tv-options')), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(seeks(), [310]);
    await _leave(tester);
  });

  testWidgets('Menu opens the options over a playback error, which hides '
      'under them', (tester) async {
    await pumpMovie(tester);
    player.emitError('Error decoding audio.');
    await tester.pump();
    await tester.pump();
    const error = 'Error: Error decoding audio.';
    expect(find.text(error), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.contextMenu);
    expect(find.byKey(const ValueKey('tv-options')), findsOneWidget);
    expect(find.text(error), findsNothing);
    await _back(tester);
    expect(find.byKey(const ValueKey('tv-options')), findsNothing);
    expect(find.text(error), findsOneWidget);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('Back hides the controls, then leaves saving the position', (
    tester,
  ) async {
    await pumpMovie(tester);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _back(tester);
    expect(controls, findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(progress, isEmpty);

    await _back(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Ficha'), findsOneWidget);
    expect(progress, [
      (const Duration(minutes: 5), const Duration(minutes: 100)),
    ]);
    expect(player.calls, contains('stop'));
    await _leave(tester);
  });

  testWidgets('the next episode countdown takes the focus, and Cancel gives '
      'it back to the player', (tester) async {
    await pumpMovie(tester, onNext: () {});
    player.emitCompleted();
    await tester.pump();
    await tester.pump();
    final watchNow = find.widgetWithText(FilledButton, 'Ver ahora');
    expect(watchNow, findsOneWidget);
    expect(
      Focus.of(tester.element(find.text('Ver ahora'))).hasPrimaryFocus,
      isTrue,
    );

    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('Ver ahora'), findsNothing);
    expect(seeks(), isEmpty);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(seeks(), [310]);
    await _leave(tester);
  });
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

/// Lets routes finish their transitions (the loader keeps animating, so
/// `pumpAndSettle` would never return).
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
