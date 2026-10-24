import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _pinKey = 'parental_pin';
final _pinPattern = RegExp(r'^\d{4}$');

/// Whether [pin] is a valid parental PIN: exactly four digits.
bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

/// Compares two strings in time that does not depend on where they differ.
bool constantTimeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Keeps the parental PIN in the OS secure storage (never in the database,
/// never exported or synced).
class PinStore {
  const PinStore();

  static const _storage = FlutterSecureStorage();

  /// Whether a PIN has been set.
  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  /// Stores [pin], replacing any previous one.
  Future<void> setPin(String pin) => _storage.write(key: _pinKey, value: pin);

  /// Removes the PIN.
  Future<void> clear() => _storage.delete(key: _pinKey);

  /// Whether [pin] matches the stored PIN (`false` when none is set).
  Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored != null && constantTimeEquals(stored, pin);
  }
}
