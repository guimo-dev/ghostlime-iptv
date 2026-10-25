import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv/tv_initial_focus.dart';
import 'tv_device.dart';

/// Pops the current route when `Esc` reaches it, like the player does; keys
/// pressed in a focused child (a text field, say) still get first go. It takes
/// focus itself when nothing inside does, so Esc works on a bare page too.
/// On a TV (Back does that job) the focus goes to the page's first widget
/// instead.
class BackOnEscape extends StatelessWidget {
  const BackOnEscape({super.key, required this.child});

  final Widget child;

  /// Handles `Esc` by going back; ignores every other key.
  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    Navigator.of(context).maybePop();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: !isTvDevice,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onKey(context, event),
      child: TvInitialFocus(child: child),
    );
  }
}
