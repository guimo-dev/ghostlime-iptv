import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A [Player] without libmpv that records `open` and `stop` in [calls]
/// (`open <uri>` / `stop`, also `audio <id>`, `subtitle <id>` and
/// `playOrPause`). Members a test does not use answer with a
/// completed future.
class FakePlayer implements Player {
  final calls = <String>[];

  /// URIs passed to `open`, in order.
  List<String> get opened => [
    for (final call in calls)
      if (call.startsWith('open ')) call.substring(5),
  ];

  /// The URI mpv would be streaming now, or `null` when stopped.
  String? current;
  final _position = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();

  /// While set, `open` waits for it before returning.
  Completer<void>? openGate;

  /// Emits [position] as if playback had reached it.
  void emitPosition(Duration position) => _position.add(position);

  /// Emits the end of the stream.
  void emitCompleted() => _completed.add(true);

  /// Emits a playback error.
  void emitError(String message) => _error.add(message);

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    const Stream.empty(),
    _completed.stream,
    _position.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _error.stream,
  );

  /// What [state] returns (tracks, for example).
  PlayerState fakeState = const PlayerState();

  @override
  PlayerState get state => fakeState;

  @override
  Future<void> setAudioTrack(AudioTrack track) async =>
      calls.add('audio ${track.id}');

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async =>
      calls.add('subtitle ${track.id}');

  @override
  Future<void> playOrPause() async => calls.add('playOrPause');

  @override
  PlatformPlayer? get platform => null;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final uri = (playable as Media).uri;
    calls.add('open $uri');
    current = uri;
    await openGate?.future;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    current = null;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    current = null;
    await _position.close();
    await _completed.close();
    await _error.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// A [VideoController] for a [FakePlayer]: it never gets a texture, so a
/// `Video` using it shows nothing.
class FakeVideoController implements VideoController {
  FakeVideoController(this.player);

  @override
  final Player player;

  @override
  final platform = Completer<PlatformVideoController>();

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  @override
  final id = ValueNotifier<int?>(null);

  @override
  final rect = ValueNotifier<Rect?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
