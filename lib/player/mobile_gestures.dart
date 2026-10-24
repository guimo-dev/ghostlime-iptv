import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/form_factor.dart';

/// Distance a finger must travel for a swipe to change channel or seek:
/// shorter moves are taps (they show the video controls).
const swipeMinDistance = 72.0;

/// How far a swipe may lean off its axis: the main axis must be at least
/// this many times the other one, so a sloppy diagonal does nothing.
const _axisDominance = 2.0;

/// Band at the bottom of the player left to the video controls (seek bar,
/// buttons): swipes starting there are not gestures.
const controlsBandHeight = 96.0;

/// How far a horizontal swipe moves a movie or episode.
const seekStep = Duration(seconds: 10);

/// Share of the player's height a vertical swipe covers to go from the
/// lowest to the highest volume or brightness.
const _levelSwipeShare = 0.75;

/// How long the volume, brightness or seek label stays after the gesture.
const _feedbackDuration = Duration(milliseconds: 800);

/// The platform channel that sets the brightness of the app's window.
const brightnessChannel = MethodChannel('ghostlime/brightness');

/// What a finished swipe does.
enum SwipeAction { previousChannel, nextChannel, seekBack, seekForward }

/// What a vertical swipe controls, by where it starts.
enum GestureZone { brightness, channel, volume }

/// What a released swipe that moved by [delta] does, or `null` for a tap, a
/// diagonal or a swipe the content does not take. Live streams change
/// channel with vertical swipes (up is the next one); movies and episodes
/// ([live] false) seek with horizontal ones (right goes forward).
SwipeAction? swipeAction(Offset delta, {required bool live}) {
  final along = live ? delta.dy : delta.dx;
  final across = live ? delta.dx : delta.dy;
  if (along.abs() < swipeMinDistance) return null;
  if (along.abs() < across.abs() * _axisDominance) return null;
  if (live) {
    return along < 0 ? SwipeAction.nextChannel : SwipeAction.previousChannel;
  }
  return along > 0 ? SwipeAction.seekForward : SwipeAction.seekBack;
}

/// What a vertical swipe starting at [x], across a player [width] wide,
/// controls. With [levels] (the setting), the left side sets the brightness
/// and the right side the volume; a live stream keeps the middle third for
/// changing channel. Without it a live stream changes channel anywhere and a
/// movie takes no vertical swipes (`null`).
GestureZone? gestureZone(
  double x,
  double width, {
  required bool live,
  required bool levels,
}) {
  if (!levels) return live ? GestureZone.channel : null;
  final share = x / width;
  if (live) {
    if (share < 1 / 3) return GestureZone.brightness;
    if (share > 2 / 3) return GestureZone.volume;
    return GestureZone.channel;
  }
  return share < 0.5 ? GestureZone.brightness : GestureZone.volume;
}

/// The brightness of the app's window (not the system's), through
/// [brightnessChannel]; Android and iOS implement it. Failures are ignored:
/// brightness is a nicety.
class WindowBrightness {
  const WindowBrightness();

  /// The current brightness from 0 to 1, or `null` when unknown.
  Future<double?> current() async {
    try {
      return await brightnessChannel.invokeMethod<double>('get');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Sets the window brightness to [value], from 0 to 1.
  Future<void> set(double value) => _call('set', value);

  /// Gives the brightness back to the system.
  Future<void> reset() => _call('reset');

  Future<void> _call(String method, [Object? argument]) async {
    try {
      await brightnessChannel.invokeMethod<void>(method, argument);
    } on PlatformException {
      // Ignored: see the class.
    } on MissingPluginException {
      // Ignored: see the class.
    }
  }
}

/// Touch gestures over the video on phones and tablets (Android, iOS):
///
/// * live: a vertical swipe changes channel ([onChannelStep] with +1 for up,
///   -1 for down);
/// * movies and episodes: a horizontal swipe seeks ([onSeek], ±[seekStep]);
/// * with [levels], vertical swipes on the right set the player's volume
///   ([volume], [onVolume], 0 to 100) and on the left the window brightness.
///
/// Taps and short moves go on to [child] (the video controls show). It reads
/// raw pointer events, so the video controls' own recognizers still work;
/// swipes starting on the controls band at the bottom are left to them. On
/// a desktop it is just [child]. The window brightness goes back to the
/// system's when it is disposed, if it was changed.
class MobileGestures extends StatefulWidget {
  const MobileGestures({
    super.key,
    required this.live,
    required this.levels,
    required this.volume,
    required this.onVolume,
    required this.child,
    this.onChannelStep,
    this.onSeek,
    this.brightness = const WindowBrightness(),
  });

  /// Whether a live stream plays (channel swipes) or a VOD (seek swipes).
  final bool live;

  /// The "volume and brightness gestures" setting.
  final bool levels;

  /// The player's current volume, 0 to 100.
  final double Function() volume;
  final ValueChanged<double> onVolume;

  /// Changes to the channel [step] places away; `null` disables it.
  final ValueChanged<int>? onChannelStep;

  /// Moves the playback by the given offset; `null` disables it.
  final ValueChanged<Duration>? onSeek;
  final WindowBrightness brightness;
  final Widget child;

  @override
  State<MobileGestures> createState() => _MobileGesturesState();
}

/// How the finger being followed moves.
enum _Axis { vertical, horizontal }

class _MobileGesturesState extends State<MobileGestures> {
  /// Fingers on the screen; a second one cancels the gesture.
  int _fingers = 0;

  /// The pointer being followed, or `null` when there is no gesture.
  int? _pointer;
  Offset _start = Offset.zero;
  GestureZone? _zone;
  _Axis? _axis;

  /// Brightness of the window: read on start, then what was last set.
  double _brightness = 0.5;
  bool _brightnessChanged = false;

  /// Label shown over the video, e.g. `Volumen 60 %`, or `null`.
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    if (isTouchPlatform && widget.levels) {
      widget.brightness.current().then((value) {
        if (value != null && !_brightnessChanged) _brightness = value;
      });
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    if (_brightnessChanged) widget.brightness.reset();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    _fingers++;
    if (_fingers > 1) {
      _pointer = null;
      return;
    }
    final size = context.size;
    if (size == null ||
        event.localPosition.dy > size.height - controlsBandHeight) {
      return;
    }
    _pointer = event.pointer;
    _start = event.localPosition;
    _axis = null;
    _zone = gestureZone(
      _start.dx,
      size.width,
      live: widget.live,
      levels: widget.levels,
    );
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final moved = event.localPosition - _start;
    _axis ??= moved.distance < kTouchSlop
        ? null
        : moved.dy.abs() > moved.dx.abs()
        ? _Axis.vertical
        : _Axis.horizontal;
    if (_axis != _Axis.vertical) return;
    final height = context.size?.height ?? 0;
    if (height <= 0) return;
    // Up raises the level; the full range takes a share of the height.
    final change = -event.delta.dy / (height * _levelSwipeShare);
    switch (_zone) {
      case GestureZone.volume:
        final volume = (widget.volume() + change * 100).clamp(0.0, 100.0);
        widget.onVolume(volume);
        _show('Volumen ${volume.round()} %');
      case GestureZone.brightness:
        _brightness = (_brightness + change).clamp(0.0, 1.0);
        _brightnessChanged = true;
        widget.brightness.set(_brightness);
        _show('Brillo ${(_brightness * 100).round()} %');
      case GestureZone.channel || null:
        break;
    }
  }

  void _onUp(PointerUpEvent event) {
    _release();
    if (event.pointer != _pointer) return;
    _pointer = null;
    final action = swipeAction(event.localPosition - _start, live: widget.live);
    switch (action) {
      case SwipeAction.nextChannel || SwipeAction.previousChannel
          when _zone == GestureZone.channel:
        widget.onChannelStep?.call(action == SwipeAction.nextChannel ? 1 : -1);
      case SwipeAction.seekForward:
        widget.onSeek?.call(seekStep);
        _show('+${seekStep.inSeconds} s');
      case SwipeAction.seekBack:
        widget.onSeek?.call(-seekStep);
        _show('−${seekStep.inSeconds} s');
      default:
        break;
    }
  }

  void _onCancel(PointerCancelEvent event) {
    _release();
    if (event.pointer == _pointer) _pointer = null;
  }

  /// Counts a finger lifted (or cancelled).
  void _release() {
    if (_fingers > 0) _fingers--;
  }

  /// Shows [text] over the video for a moment.
  void _show(String text) {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(_feedbackDuration, () {
      if (mounted) setState(() => _feedback = null);
    });
    setState(() => _feedback = text);
  }

  @override
  Widget build(BuildContext context) {
    if (!isTouchPlatform) return widget.child;
    final feedback = _feedback;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: widget.child,
        ),
        if (feedback != null)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  feedback,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
