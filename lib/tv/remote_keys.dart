import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/tv_device.dart';
import 'tv_text_input.dart';

/// Channel up/down on the remote: zap [step] channels away (1 up, -1 down)
/// in the live player.
class ChannelStepIntent extends Intent {
  /// Zaps [step] channels away.
  const ChannelStepIntent(this.step);

  /// How many channels to move: positive goes forward in the list.
  final int step;
}

/// A number key on the remote, to type the number of a live channel.
class ChannelDigitIntent extends Intent {
  /// The key [digit] (0 to 9) was pressed.
  const ChannelDigitIntent(this.digit);

  /// The digit pressed, 0 to 9.
  final int digit;
}

/// Play/pause on the remote.
class PlayPauseIntent extends Intent {
  /// Toggles playback.
  const PlayPauseIntent();
}

/// The separate play key of some remotes and HDMI-CEC: starts playback.
class PlayIntent extends Intent {
  /// Starts playback.
  const PlayIntent();
}

/// The separate pause key of some remotes and HDMI-CEC: pauses playback.
class PauseIntent extends Intent {
  /// Pauses playback.
  const PauseIntent();
}

/// Fast forward or rewind on the remote: jump [offset] in a video.
class SeekIntent extends Intent {
  /// Jumps [offset] (negative goes back).
  const SeekIntent(this.offset);

  /// How far to jump; negative rewinds.
  final Duration offset;
}

/// The menu key (Fire TV "Menú"): the quick options of the player.
class QuickOptionsIntent extends Intent {
  /// Opens the quick options.
  const QuickOptionsIntent();
}

/// Back on the remote while a dialog, sheet or menu (a popup route) is on
/// top: there is a route to close. Elsewhere it lets the key go on to Android,
/// which pops the page (through `PopScope`): a focused text field would
/// otherwise take the [DismissIntent] and swallow Back. In a text field it
/// is left to Android as well, so Back first leaves the field.
///
/// It fires when the key is released, as Android does: Android goes back on
/// the release of an unhandled Back, so acting on the press would close the
/// dialog and then, on the release, pop the page under it too.
class _BackWithRouteToClose extends ShortcutActivator {
  const _BackWithRouteToClose();

  @override
  Iterable<LogicalKeyboardKey> get triggers => const [
    LogicalKeyboardKey.goBack,
  ];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyUpEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.goBack) return false;
    final focus = FocusManager.instance.primaryFocus;
    // A text field leaves it to Android too: its Back first leaves the field
    // (`TvTextFieldBack`).
    if (isTextFieldFocus(focus)) return false;
    final focused = focus?.context;
    // `Navigator.maybeOf` looks the navigator up without depending on it,
    // and a `popUntil` whose test passes on the top route pops nothing: it
    // only reads that route. `ModalRoute.of` would make the focused widget
    // depend on its route.
    final navigator = focused == null ? null : Navigator.maybeOf(focused);
    Route<Object?>? top;
    navigator?.popUntil((route) {
      top = route;
      return true;
    });
    return top is PopupRoute;
  }

  @override
  String debugDescribeKeys() => 'Go Back (with a route to close)';
}

/// How far fast forward and rewind jump.
const _seekStep = Duration(seconds: 10);

const _digitKeys = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadKeys = [
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// The keys of a TV remote and the intents they produce.
///
/// Back (and Esc) is a [DismissIntent] when a dialog or sheet is open: it
/// closes it. On a page Back is left alone, so the key goes on to Android,
/// which turns it into a pop of the route (and `PopScope` decides). The player intents do
/// nothing until a screen registers an [Action] for them, so a number typed
/// in a text field still reaches the field.
final Map<ShortcutActivator, Intent> remoteShortcuts = {
  const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
  const _BackWithRouteToClose(): const DismissIntent(),
  const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
  const SingleActivator(LogicalKeyboardKey.channelUp): const ChannelStepIntent(
    1,
  ),
  const SingleActivator(LogicalKeyboardKey.channelDown):
      const ChannelStepIntent(-1),
  for (var d = 0; d < 10; d++) ...{
    SingleActivator(_digitKeys[d]): ChannelDigitIntent(d),
    SingleActivator(_numpadKeys[d]): ChannelDigitIntent(d),
  },
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
      const PlayPauseIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlay): const PlayIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPause): const PauseIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaFastForward): const SeekIntent(
    _seekStep,
  ),
  const SingleActivator(LogicalKeyboardKey.mediaRewind): SeekIntent(-_seekStep),
  const SingleActivator(LogicalKeyboardKey.contextMenu):
      const QuickOptionsIntent(),
};

/// The shortcuts for `MaterialApp.shortcuts`: on a TV the default ones plus
/// [remoteShortcuts]; elsewhere `null` (the defaults, unchanged).
Map<ShortcutActivator, Intent>? appShortcuts() {
  if (!isTvDevice) return null;
  return {...WidgetsApp.defaultShortcuts, ...remoteShortcuts};
}

/// Up and Down that leave a text field for the widget above or below, even
/// when the caret could still move: with a remote they are the only way out
/// of a field (Left and Right keep moving the caret).
const _textFieldExits = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
    TraversalDirection.up,
    ignoreTextFields: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
    TraversalDirection.down,
    ignoreTextFields: false,
  ),
};

/// On a TV, lets Up and Down move the focus out of text fields; elsewhere it
/// returns [child] untouched.
///
/// It goes in `MaterialApp.builder`, below the app's text editing
/// shortcuts, which would otherwise take the arrows in a field.
class RemoteTextFieldKeys extends StatelessWidget {
  /// Wraps [child] on a TV.
  const RemoteTextFieldKeys({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return child;
    return Shortcuts(shortcuts: _textFieldExits, child: child);
  }
}
