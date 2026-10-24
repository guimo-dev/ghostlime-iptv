import 'package:flutter/widgets.dart';

import 'settings_controller.dart';

/// Exposes the [SettingsController] to the whole widget tree.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, rebuilding the caller whenever the settings change.
  static SettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

  /// The controller without subscribing to changes (for event handlers and
  /// one-off reads such as when a player opens).
  static SettingsController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
