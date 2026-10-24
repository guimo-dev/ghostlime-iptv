import 'package:flutter/widgets.dart';

import 'pin_store.dart';

/// Exposes the [PinStore] to the widget tree, so isolated runs can swap the
/// OS secure storage for memory.
class PinScope extends InheritedWidget {
  const PinScope({super.key, required this.store, required super.child});

  final PinStore store;

  /// The store of the nearest scope, or the real one when there is none.
  static PinStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PinScope>()?.store ??
      const PinStore();

  @override
  bool updateShouldNotify(PinScope oldWidget) => store != oldWidget.store;
}
