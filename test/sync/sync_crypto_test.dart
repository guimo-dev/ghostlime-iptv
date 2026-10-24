import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sync/sync_crypto.dart';

void main() {
  final salt = List.generate(16, (i) => i);
  late List<int> key;

  setUpAll(() async => key = await SyncCrypto.deriveKey('secreto', salt));

  group('seal and open', () {
    test('round-trip', () async {
      final plain = utf8.encode('{"name":"Lista ñ"}');
      final sealed = await SyncCrypto.seal(key, plain);
      expect(await SyncCrypto.open(key, sealed), plain);
    });

    test('round-trip of an empty message', () async {
      final sealed = await SyncCrypto.seal(key, const []);
      expect(await SyncCrypto.open(key, sealed), isEmpty);
    });

    test('the same plain text seals differently each time', () async {
      final plain = utf8.encode('igual');
      final a = await SyncCrypto.seal(key, plain);
      final b = await SyncCrypto.seal(key, plain);
      expect(a, isNot(b));
    });

    test('sealed text is nonce(12) + ciphertext + mac(16) in base64', () async {
      final sealed = await SyncCrypto.seal(key, utf8.encode('abcde'));
      expect(base64Decode(sealed).length, 12 + 5 + 16);
    });

    test('a wrong key throws SyncCryptoException', () async {
      final sealed = await SyncCrypto.seal(key, utf8.encode('datos'));
      final other = await SyncCrypto.deriveKey('otra', salt);
      expect(
        SyncCrypto.open(other, sealed),
        throwsA(isA<SyncCryptoException>()),
      );
    });

    test('a changed byte throws SyncCryptoException', () async {
      final sealed = await SyncCrypto.seal(key, utf8.encode('datos'));
      final bytes = base64Decode(sealed);
      for (final index in [0, 12, bytes.length - 1]) {
        final tampered = List.of(bytes)..[index] ^= 1;
        expect(
          SyncCrypto.open(key, base64Encode(tampered)),
          throwsA(isA<SyncCryptoException>()),
        );
      }
    });

    test('garbage and truncated text throw SyncCryptoException', () async {
      expect(
        SyncCrypto.open(key, 'no es base64!'),
        throwsA(isA<SyncCryptoException>()),
      );
      expect(
        SyncCrypto.open(key, base64Encode(List.filled(10, 1))),
        throwsA(isA<SyncCryptoException>()),
      );
    });

    test('a key of the wrong length throws SyncCryptoException', () async {
      final sealed = await SyncCrypto.seal(key, utf8.encode('datos'));
      expect(
        SyncCrypto.open([1, 2, 3], sealed),
        throwsA(isA<SyncCryptoException>()),
      );
    });

    test('associated data must match to open', () async {
      final aad = utf8.encode('favorite|a');
      final sealed = await SyncCrypto.seal(key, utf8.encode('datos'), aad: aad);

      expect(
        await SyncCrypto.open(key, sealed, aad: aad),
        utf8.encode('datos'),
      );
      await expectLater(
        SyncCrypto.open(key, sealed, aad: utf8.encode('favorite|b')),
        throwsA(isA<SyncCryptoException>()),
      );
      await expectLater(
        SyncCrypto.open(key, sealed),
        throwsA(isA<SyncCryptoException>()),
      );
    });
  });

  group('deriveKey', () {
    test('is deterministic for the same password and salt', () async {
      expect(await SyncCrypto.deriveKey('secreto', salt), key);
    });

    test('is 32 bytes and changes with another salt or password', () async {
      expect(key, hasLength(32));
      final otherSalt = List.generate(16, (i) => i + 1);
      expect(await SyncCrypto.deriveKey('secreto', otherSalt), isNot(key));
      expect(await SyncCrypto.deriveKey('Secreto', salt), isNot(key));
    });
  });

  test(
    'randomBytes returns the requested length and differs between calls',
    () {
      final a = SyncCrypto.randomBytes(16);
      final b = SyncCrypto.randomBytes(16);
      expect(a, hasLength(16));
      expect(a, isNot(b));
      expect(SyncCrypto.randomBytes(0), isEmpty);
    },
  );
}
