import 'password_store.dart';

/// Keeps passwords in memory only, for runs that must not touch the OS secure
/// storage (review harness and tests).
class MemoryPasswordStore implements PasswordStore {
  final Map<int, String> _values = {};

  /// The stored password, or `null`.
  @override
  Future<String?> read(int playlistId) async => _values[playlistId];

  /// Stores [password] for the playlist, replacing any previous one.
  @override
  Future<void> write(int playlistId, String password) async =>
      _values[playlistId] = password;

  /// Removes the playlist's password.
  @override
  Future<void> delete(int playlistId) async => _values.remove(playlistId);
}
