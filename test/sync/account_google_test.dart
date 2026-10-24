import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_crypto.dart';

import 'fake_account.dart';
import 'fake_passwords.dart';

const _googleEmail = 'ana@example.com';
const _password = 'correct horse';
const _cancelled = 'Se ha cancelado el acceso con Google.';
const _xtream = Playlist(
  name: 'Mi proveedor',
  type: PlaylistType.xtream,
  serverUrl: 'http://secret-server:8080',
  username: 'secret-user',
);

/// One simulated device signing in with Google: its own database, secure
/// storage and session, sharing the [backend], the [accounts] and the
/// server's [escrow] with the other devices.
class GoogleDevice {
  GoogleDevice(
    InMemorySyncBackend backend,
    Map<String, String> accounts,
    Map<String, Uint8List> escrow,
  ) : auth = FakeAuthGateway(accounts, escrow: escrow)
        ..supportsGoogle = true
        ..googleEmail = _googleEmail
        ..profiles = backend {
    service = AccountService(
      db: db,
      auth: auth,
      backend: backend,
      keys: keys,
      passwords: passwords,
    );
    addTearDown(service.dispose);
  }

  final db = CatalogDb.inMemory();
  final passwords = FakePasswords();
  final keys = FakeKeyStore();
  final FakeAuthGateway auth;
  late final AccountService service;

  /// Saves the Xtream test playlist with a password.
  Future<void> addPlaylist() async {
    final id = db.savePlaylist(_xtream);
    await passwords.write(id, 'secret-pass');
  }
}

/// A backend whose next [loadProfile] answers "none", as when a password
/// device creates the profile right after this one looked.
class _LateProfileBackend extends InMemorySyncBackend {
  bool hideProfileOnce = false;

  @override
  Future<RemoteProfile?> loadProfile() async {
    if (hideProfileOnce) {
      hideProfileOnce = false;
      return null;
    }
    return super.loadProfile();
  }
}

/// A backend holding a Google account's row: no password profile, and no
/// room to create one.
class _GoogleRowBackend extends InMemorySyncBackend {
  @override
  Future<bool> createProfile(RemoteProfile profile) async => false;
}

/// Throws the [AccountException] with [message].
Matcher _throwsAccount(String message) => throwsA(
  isA<AccountException>().having((e) => e.message, 'message', message),
);

void main() {
  late InMemorySyncBackend backend;
  late Map<String, String> accounts;
  late Map<String, Uint8List> escrow;

  setUp(() {
    backend = InMemorySyncBackend();
    accounts = {};
    escrow = {};
  });

  test('supportsGoogle follows the gateway', () {
    final device = GoogleDevice(backend, accounts, escrow);
    expect(device.service.supportsGoogle, isTrue);
    device.auth.supportsGoogle = false;
    expect(device.service.supportsGoogle, isFalse);
  });

  test(
    'first Google sign-in creates a key, escrows it and syncs with it',
    () async {
      final a = GoogleDevice(backend, accounts, escrow);
      await a.addPlaylist();

      await a.service.signInWithGoogle();

      expect(a.service.status, AccountStatus.signedIn);
      expect(a.service.lastError, isNull);
      expect(a.service.lastSync, isNotNull);
      expect(a.auth.escrowStores, 1);
      final escrowed = escrow['user-$_googleEmail'];
      expect(escrowed, hasLength(32));
      expect(a.keys.key, escrowed);
      // No password profile: the key lives only in the escrow.
      expect(await backend.loadProfile(), isNull);
      expect(backend.items, isNotEmpty);
      expect(
        backend.items.map((i) => i.payload).join(),
        isNot(contains('secret')),
      );
      expect(a.db.syncUserId(), 'user-$_googleEmail');
    },
  );

  test('a second device fetches the escrowed key without asking', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    await a.addPlaylist();
    await a.service.signInWithGoogle();

    final b = GoogleDevice(backend, accounts, escrow);
    await b.service.signInWithGoogle();

    expect(b.service.status, AccountStatus.signedIn);
    expect(b.keys.key, a.keys.key);
    expect(b.auth.escrowStores, 0);
    expect(b.db.playlists().single.name, 'Mi proveedor');
    expect(await b.passwords.read(b.db.playlists().single.id!), 'secret-pass');
  });

  test('when another device escrows first, its key is the one used', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    final winner = Uint8List.fromList(SyncCrypto.randomBytes(32));
    a.auth.beforeStoreEscrowedKey = () async =>
        escrow['user-$_googleEmail'] = winner;

    await a.service.signInWithGoogle();

    expect(a.service.status, AccountStatus.signedIn);
    expect(a.keys.key, winner);
    expect(escrow['user-$_googleEmail'], winner);
  });

  group('an account that already has a password', () {
    late GoogleDevice b;
    late List<int> passwordKey;

    setUp(() async {
      final a = GoogleDevice(backend, accounts, escrow);
      await a.addPlaylist();
      await a.service.signUp(_googleEmail, _password);
      passwordKey = a.keys.key!;

      b = GoogleDevice(backend, accounts, escrow);
      await b.service.signInWithGoogle();
    });

    test('asks for the password and escrows nothing', () async {
      expect(b.service.status, AccountStatus.needsPassword);
      expect(b.service.email, _googleEmail);
      expect(b.keys.key, isNull);
      expect(b.db.playlists(), isEmpty);
      expect(b.auth.escrowStores, 0);
      expect(escrow, isEmpty);
    });

    test('a wrong password keeps asking', () async {
      await expectLater(
        b.service.unlockWithPassword('wrong password'),
        _throwsAccount('La contraseña no es correcta.'),
      );
      expect(b.service.status, AccountStatus.needsPassword);
      expect(b.service.lastError, 'La contraseña no es correcta.');
      expect(b.keys.key, isNull);
    });

    test('the password opens the key, syncs and never escrows it', () async {
      await b.service.unlockWithPassword(_password);

      expect(b.service.status, AccountStatus.signedIn);
      expect(b.service.lastError, isNull);
      expect(b.keys.key, passwordKey);
      expect(b.db.playlists().single.name, 'Mi proveedor');
      expect(b.auth.escrowStores, 0);
      expect(escrow, isEmpty);
      // Still end-to-end: the profile is the password one.
      expect(await backend.loadProfile(), isNotNull);
    });

    test('the next start on this device opens without asking', () async {
      await b.service.unlockWithPassword(_password);
      final again = AccountService(
        db: b.db,
        auth: b.auth,
        backend: backend,
        keys: b.keys,
        passwords: b.passwords,
      );
      addTearDown(again.dispose);

      await again.start();

      expect(again.status, AccountStatus.signedIn);
      expect(b.auth.escrowStores, 0);
    });
  });

  test('unlockWithPassword needs the needsPassword state', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    await expectLater(
      a.service.unlockWithPassword(_password),
      _throwsAccount('No hay nada que abrir ahora.'),
    );
  });

  test('a cancelled Google sign-in leaves everything signed out', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    await a.addPlaylist();
    a.auth.oauthError = const AccountException(_cancelled);

    await expectLater(a.service.signInWithGoogle(), _throwsAccount(_cancelled));

    expect(a.service.status, AccountStatus.signedOut);
    expect(a.service.lastError, _cancelled);
    expect(a.auth.userId, isNull);
    expect(a.keys.key, isNull);
    expect(a.auth.escrowStores, 0);
    expect(escrow, isEmpty);
    expect(backend.items, isEmpty);
    expect(a.db.syncUserId(), isNull);
  });

  test('a failed Google sign-in shows its Spanish message', () async {
    const failed = 'No se ha podido entrar con Google. Inténtalo de nuevo.';
    final a = GoogleDevice(backend, accounts, escrow);
    a.auth.oauthError = const AccountException(failed);

    await expectLater(a.service.signInWithGoogle(), _throwsAccount(failed));

    expect(a.service.status, AccountStatus.signedOut);
    expect(a.service.lastError, failed);
  });

  test('when the escrow cannot be reached the session is closed', () async {
    const offline =
        'No se ha podido recuperar tu clave de sincronización. '
        'Inténtalo de nuevo.';
    final a = GoogleDevice(backend, accounts, escrow);
    a.auth.escrowError = const AccountException(offline);

    await expectLater(a.service.signInWithGoogle(), _throwsAccount(offline));

    expect(a.service.status, AccountStatus.signedOut);
    expect(a.auth.userId, isNull);
    expect(a.keys.key, isNull);
    expect(a.auth.escrowStores, 0);
    expect(a.db.syncUserId(), isNull);
  });

  test('the escrow never takes the key of a password account', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    await a.service.signUp(_googleEmail, _password);

    await a.auth.storeEscrowedKey(
      Uint8List.fromList(SyncCrypto.randomBytes(32)),
    );

    expect(escrow, isEmpty);
  });

  test('a password profile created meanwhile is never escrowed over', () async {
    final lateBackend = _LateProfileBackend();
    final a = GoogleDevice(lateBackend, accounts, escrow);
    await a.service.signUp(_googleEmail, _password);
    await a.service.signOut();
    final b = GoogleDevice(lateBackend, accounts, escrow);
    lateBackend.hideProfileOnce = true;

    await expectLater(
      b.service.signInWithGoogle(),
      throwsA(isA<AccountException>()),
    );

    expect(b.service.status, AccountStatus.signedOut);
    expect(b.auth.userId, isNull);
    expect(b.keys.key, isNull);
    expect(escrow, isEmpty);
  });

  test('an escrowed key of the wrong size is refused', () async {
    escrow['user-$_googleEmail'] = Uint8List(16);
    final a = GoogleDevice(backend, accounts, escrow);

    await expectLater(
      a.service.signInWithGoogle(),
      _throwsAccount(
        'La clave de sincronización guardada en el servidor no es válida.',
      ),
    );

    expect(a.service.status, AccountStatus.signedOut);
    expect(a.auth.userId, isNull);
    expect(a.keys.key, isNull);
  });

  test('a failed Google sign-in drops a stray session', () async {
    accounts['other@example.com'] = _password;
    final a = GoogleDevice(backend, accounts, escrow);
    // A session the service does not know about, e.g. a late browser return.
    await a.auth.signIn('other@example.com', _password);
    a.auth.oauthError = const AccountException(_cancelled);

    await expectLater(a.service.signInWithGoogle(), _throwsAccount(_cancelled));

    expect(a.auth.userId, isNull);
    expect(a.service.status, AccountStatus.signedOut);
  });

  test(
    'a Google account using password recovery is told to use Google',
    () async {
      accounts[_googleEmail] = 'old password';
      final a = GoogleDevice(_GoogleRowBackend(), accounts, escrow);

      await expectLater(
        a.service.recoverPassword(
          _googleEmail,
          FakeAuthGateway.validCode,
          'a new password',
        ),
        _throwsAccount(
          'Esta cuenta entra con Google. Usa «Continuar con Google».',
        ),
      );

      expect(a.service.status, AccountStatus.signedOut);
      expect(a.auth.userId, isNull);
      expect(a.keys.key, isNull);
    },
  );

  test('cancelGoogleSignIn tells the gateway', () {
    final a = GoogleDevice(backend, accounts, escrow);
    a.service.cancelGoogleSignIn();
    expect(a.auth.oauthCancels, 1);
  });

  test('a Google account has no password to change', () async {
    final a = GoogleDevice(backend, accounts, escrow);
    await a.service.signInWithGoogle();

    await expectLater(
      a.service.changePassword('anything at all', 'a new password'),
      _throwsAccount(
        'Esta cuenta entra con Google y no tiene contraseña de '
        'sincronización.',
      ),
    );
    expect(a.service.status, AccountStatus.signedIn);
  });
}
