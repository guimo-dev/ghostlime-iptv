import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pops the current route when `Esc` reaches it, like the player does; keys
/// pressed in a focused child (a text field, say) still get first go. It takes
/// focus itself when nothing inside does, so Esc works on a bare page too.
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
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onKey(context, event),
      child: child,
    );
  }
}
