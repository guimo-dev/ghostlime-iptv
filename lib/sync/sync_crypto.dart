import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const _nonceLength = 12;
const _macLength = 16;

final _argon2id = Argon2id(
  memory: 19456,
  iterations: 2,
  parallelism: 1,
  hashLength: 32,
);
final _aesGcm = AesGcm.with256bits();
final _random = Random.secure();

/// Thrown when sealed data cannot be opened: wrong key or tampered text.
class SyncCryptoException implements Exception {
  const SyncCryptoException(this.message);

  final String message;

  @override
  String toString() => 'SyncCryptoException: $message';
}

/// Key derivation and authenticated encryption for synced data.
class SyncCrypto {
  const SyncCrypto._();

  /// Derives a 32-byte key from [password] and [salt] with Argon2id
  /// (19 MiB, 2 iterations, parallelism 1). Runs in its own isolate: in pure
  /// Dart it takes a noticeable fraction of a second (more on phones), which
  /// would freeze the UI.
  static Future<List<int>> deriveKey(String password, List<int> salt) =>
      Isolate.run(() async {
        final key = await _argon2id.deriveKey(
          secretKey: SecretKey(utf8.encode(password)),
          nonce: salt,
        );
        return key.extractBytes();
      });

  /// [n] cryptographically secure random bytes.
  static List<int> randomBytes(int n) =>
      List.generate(n, (_) => _random.nextInt(256));

  /// Encrypts [plain] with AES-256-GCM under [key]; returns
  /// `base64(nonce | ciphertext | mac)` with a fresh random nonce. [aad] is
  /// authenticated but not stored: [open] only succeeds with the same bytes,
  /// which ties the ciphertext to the context it was made for.
  static Future<String> seal(
    List<int> key,
    List<int> plain, {
    List<int> aad = const [],
  }) async {
    final box = await _aesGcm.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: randomBytes(_nonceLength),
      aad: aad,
    );
    return base64Encode(box.concatenation());
  }

  /// Decrypts text made by [seal] with the same [aad]; throws
  /// [SyncCryptoException] when [key] or [aad] is wrong or [sealed] was
  /// altered.
  static Future<List<int>> open(
    List<int> key,
    String sealed, {
    List<int> aad = const [],
  }) async {
    try {
      final bytes = base64Decode(sealed);
      if (bytes.length < _nonceLength + _macLength) {
        throw const SyncCryptoException('Texto cifrado demasiado corto.');
      }
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      return await _aesGcm.decrypt(box, secretKey: SecretKey(key), aad: aad);
    } on SyncCryptoException {
      rethrow;
    } catch (_) {
      // Bad base64, wrong key length, or a failed authentication tag.
      throw const SyncCryptoException(
        'No se pueden descifrar los datos: clave incorrecta o datos alterados.',
      );
    }
  }
}
