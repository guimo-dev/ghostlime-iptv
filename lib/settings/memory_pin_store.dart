import 'pin_store.dart';

/// Keeps the parental PIN in memory only, for runs that must not touch the OS
/// secure storage (review harness and tests).
class MemoryPinStore implements PinStore {
  String? _pin;

  /// Whether a PIN has been set.
  @override
  Future<bool> hasPin() async => _pin != null;

  /// Stores [pin], replacing any previous one.
  @override
  Future<void> setPin(String pin) async => _pin = pin;

  /// Removes the PIN.
  @override
  Future<void> clear() async => _pin = null;

  /// Whether [pin] matches the stored PIN (`false` when none is set).
  @override
  Future<bool> verify(String pin) async {
    final stored = _pin;
    return stored != null && constantTimeEquals(stored, pin);
  }
}
