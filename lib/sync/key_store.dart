import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the sync data key in the OS secure storage so the password is not
/// asked on every start. Tests replace it with an in-memory fake.
class DataKeyStore {
  const DataKeyStore();

  static const _storage = FlutterSecureStorage();
  static const _name = 'sync_data_key';

  /// The stored key, or `null` when there is none.
  Future<List<int>?> read() async {
    final text = await _storage.read(key: _name);
    return text == null ? null : base64Decode(text);
  }

  /// Stores [key], replacing any previous one.
  Future<void> write(List<int> key) =>
      _storage.write(key: _name, value: base64Encode(key));

  /// Removes the stored key.
  Future<void> clear() => _storage.delete(key: _name);
}
