import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ui/tv_device.dart';

/// On a TV, gives the focus to the first focusable widget inside [child]
/// once it is built, when nothing in its route (or dialog) has the focus
/// yet. For pages whose first useful widget has no `autofocus` of its own
/// (a segmented button, a list of settings). Elsewhere it returns [child].
class TvInitialFocus extends StatefulWidget {
  /// Focuses the first focusable widget of [child] on a TV.
  const TvInitialFocus({super.key, required this.child});

  /// The content that gets the initial focus.
  final Widget child;

  @override
  State<TvInitialFocus> createState() => _TvInitialFocusState();
}

class _TvInitialFocusState extends State<TvInitialFocus> {
  /// Marks the content in the focus tree; never focused itself.
  final _area = FocusNode(
    debugLabel: 'TvInitialFocus',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    // After the frame and after the `autofocus` requests made while
    // building it (applied in a microtask scheduled earlier), so a widget
    // that asks for the focus itself keeps it.
    if (isTvDevice) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(_focusFirst),
      );
    }
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  /// Focuses the first focusable widget of the content, unless something in
  /// the same scope already has the focus.
  void _focusFirst() {
    if (!mounted || FocusScope.of(context).focusedChild != null) return;
    final first = _area.traversalDescendants
        .where((node) => node is! FocusScopeNode)
        .firstOrNull;
    first?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(focusNode: _area, child: widget.child);
  }
}
