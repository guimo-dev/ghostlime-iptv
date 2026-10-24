import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps Xtream passwords in the OS secure storage, keyed by playlist id.
class PasswordStore {
  const PasswordStore();

  static const _storage = FlutterSecureStorage();

  static String _key(int playlistId) => 'playlist_${playlistId}_password';

  /// The stored password, or `null`.
  Future<String?> read(int playlistId) => _storage.read(key: _key(playlistId));

  /// Stores [password] for the playlist, replacing any previous one.
  Future<void> write(int playlistId, String password) =>
      _storage.write(key: _key(playlistId), value: password);

  /// Removes the playlist's password.
  Future<void> delete(int playlistId) => _storage.delete(key: _key(playlistId));
}
