import 'package:flutter/foundation.dart';

/// Per-run parental state: whether locked categories are unlocked for this
/// session. Never persisted, so it is locked again on every start.
class ParentalSession {
  const ParentalSession._();

  /// `true` after the PIN has been entered in this session.
  static final ValueNotifier<bool> unlocked = ValueNotifier(false);
}
