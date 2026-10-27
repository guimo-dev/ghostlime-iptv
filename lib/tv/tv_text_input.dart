import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/tv_device.dart';

/// Whether [node] is the focus of a text field (the one inside its
/// [EditableText]).
bool isTextFieldFocus(FocusNode? node) =>
    node?.context?.findAncestorStateOfType<EditableTextState>() != null;

/// The keys that open the system keyboard on a field: OK on the remote.
final _okKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// Where a field goes when typing starts, as a fraction of the visible area:
/// the system keyboard of a TV floats over the lower half of the screen and
/// does not tell the app.
const _typingAlignment = 0.1;

/// Room to leave under the last field of a scrolling form on a TV (half the
/// 1280x720 canvas), so that field too can scroll to the top half, above the
/// floating system keyboard.
const tvTypingRoom = 360.0;

/// The text field built by [builder], made for the remote on a TV.
///
/// On a TV the field takes the focus without opening the system keyboard
/// ([builder] gets `locked` true: pass it as `readOnly`), so the arrows, Left
/// and Right included, go past it; OK opens the keyboard and scrolls the field to the top. "Siguiente"
/// on the keyboard keeps it open in the next field; when the field drops the
/// focus to nothing ("Hecho" on a search box) it keeps it, with the keyboard
/// closed. Elsewhere [builder] gets `false` and nothing changes.
class TvKeyboardGate extends StatefulWidget {
  /// Builds the field with [builder].
  const TvKeyboardGate({super.key, required this.builder});

  /// Builds the field; `locked` is whether it must be read-only.
  final Widget Function(BuildContext context, bool locked) builder;

  @override
  State<TvKeyboardGate> createState() => _TvKeyboardGateState();
}

class _TvKeyboardGateState extends State<TvKeyboardGate> {
  /// The field with the keyboard open, if any: "Siguiente" leaves it for the
  /// next field without a key of the remote, and that field opens too.
  static _TvKeyboardGateState? _typing;

  /// Holds the field in the focus tree; never focused itself.
  final _area = FocusNode(
    debugLabel: 'TvKeyboardGate',
    skipTraversal: true,
    canRequestFocus: false,
  );

  bool _locked = true;

  @override
  void dispose() {
    if (_typing == this) _typing = null;
    _area.dispose();
    super.dispose();
  }

  /// The focus node of the field.
  FocusNode? get _fieldFocus =>
      _area.descendants.where((node) => node.canRequestFocus).firstOrNull;

  /// Opens the keyboard on the focused field and scrolls it to the top.
  void _startTyping() {
    _typing = this;
    if (_locked) {
      // The field opens the keyboard itself once it is no longer read-only.
      setState(() => _locked = false);
    } else {
      _fieldFocus?.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.requestKeyboard();
    }
    final field = _fieldFocus?.context;
    if (field != null) {
      unawaited(
        Scrollable.ensureVisible(
          field,
          alignment: _typingAlignment,
          duration: const Duration(milliseconds: 200),
        ),
      );
    }
  }

  /// OK starts typing; until then Left and Right leave the field, as Up and
  /// Down always do (once typing they move the caret).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final sideways = key == LogicalKeyboardKey.arrowLeft
        ? TraversalDirection.left
        : key == LogicalKeyboardKey.arrowRight
        ? TraversalDirection.right
        : null;
    if (_locked && sideways != null) {
      _fieldFocus?.focusInDirection(sideways);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent || !_okKeys.contains(key)) {
      return KeyEventResult.ignored;
    }
    _startTyping();
    return KeyEventResult.handled;
  }

  void _onFocusChange(bool focused) {
    if (focused) {
      // Moved here by "Siguiente" (no key of the remote is down): keep typing.
      final previous = _typing;
      if (previous != null &&
          previous != this &&
          HardwareKeyboard.instance.logicalKeysPressed.isEmpty) {
        _startTyping();
      }
      return;
    }
    // Forgotten after the other fields heard of the change.
    scheduleMicrotask(() {
      if (_typing == this && !_area.hasFocus) _typing = null;
    });
    if (!mounted) return;
    if (!_locked) setState(() => _locked = true);
    // "Hecho" without a next step leaves the focus on the page itself:
    // nothing visible would have it.
    final scope = _area.enclosingScope;
    if (scope != null && FocusManager.instance.primaryFocus == scope) {
      _fieldFocus?.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.builder(context, false);
    return Focus(
      focusNode: _area,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: widget.builder(context, _locked),
    );
  }
}

/// On a TV, makes the system Back leave a focused text field before it
/// leaves the page or dialog: the focus goes to the closest other control
/// of the same page or dialog. Elsewhere it does nothing.
///
/// It goes above the `MaterialApp`, so it hears Back before its navigator.
class TvTextFieldBack extends StatefulWidget {
  /// Watches Back over [child].
  const TvTextFieldBack({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  State<TvTextFieldBack> createState() => _TvTextFieldBackState();
}

class _TvTextFieldBackState extends State<TvTextFieldBack>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!isTvDevice) return false;
    final field = FocusManager.instance.primaryFocus;
    if (!isTextFieldFocus(field)) return false;
    final candidates = field!.enclosingScope?.traversalDescendants.where(
      (node) => node is! FocusScopeNode && !isTextFieldFocus(node),
    );
    if (candidates == null || candidates.isEmpty) return false;
    // The closest one, so the focus stays where the user was looking.
    final from = field.rect.center;
    final closest = candidates.reduce(
      (a, b) =>
          (a.rect.center - from).distance <= (b.rect.center - from).distance
          ? a
          : b,
    );
    closest.requestFocus();
    final target = closest.context;
    if (target != null) unawaited(Scrollable.ensureVisible(target));
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
