import 'package:iptv_player/playlists/password_store.dart';

/// In-memory stand-in for the OS secure storage.
class FakePasswords implements PasswordStore {
  final Map<int, String> values = {};

  @override
  Future<String?> read(int playlistId) async => values[playlistId];

  @override
  Future<void> write(int playlistId, String password) async =>
      values[playlistId] = password;

  @override
  Future<void> delete(int playlistId) async => values.remove(playlistId);
}
