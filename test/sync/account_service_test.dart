import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/key_store.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_crypto.dart';

import 'fake_passwords.dart';

const _email = 'ana@example.com';
const _password = 'correct horse';
const _xtream = Playlist(
  name: 'Mi proveedor',
  type: PlaylistType.xtream,
  serverUrl: 'http://secret-server:8080',
  username: 'secret-user',
);

/// Auth that keeps accounts in a map shared between "devices"; each instance
/// has its own session.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway(this.accounts, {this.requireConfirmation = false});

  final Map<String, String> accounts;
  bool requireConfirmation;

  /// Runs first in [updatePassword]; may throw to simulate a failure.
  Future<void> Function()? onUpdatePassword;

  /// When set, [signOut] waits for it.
  Future<void>? signOutGate;
  String? _email;

  @override
  String? get userId => _email == null ? null : 'user-$_email';

  @override
  String? get email => _email;

  @override
  Future<bool> signUp(String email, String password) async {
    if (accounts.containsKey(email)) {
      throw const AccountException('Ya existe una cuenta con ese email.');
    }
    accounts[email] = password;
    if (requireConfirmation) return false;
    _email = email;
    return true;
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (accounts[email] != password) {
      throw const AccountException(
        'El email o la contraseña no son correctos.',
      );
    }
    _email = email;
  }

  @override
  Future<void> signOut() async {
    await signOutGate;
    _email = null;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await onUpdatePassword?.call();
    accounts[_email!] = newPassword;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  /// The only code the fake accepts, for both kinds of email.
  static const validCode = '123456';

  @override
  Future<void> verifyRecoveryCode(String email, String code) async {
    if (!accounts.containsKey(email) || code != validCode) {
      throw const AccountException('El código no es correcto o ha caducado.');
    }
    _email = email;
  }

  @override
  Future<void> verifySignupCode(String email, String code) =>
      verifyRecoveryCode(email, code);
}

class FakeKeyStore implements DataKeyStore {
  List<int>? key;

  @override
  Future<List<int>?> read() async => key;

  @override
  Future<void> write(List<int> key) async => this.key = key;

  @override
  Future<void> clear() async => key = null;
}

/// A backend whose profile writes can be made to fail.
class FlakyBackend extends InMemorySyncBackend {
  bool failSaves = false;

  /// When set, a pull waits for it before answering.
  Future<void>? pullGate;

  /// Makes the next [loadProfile] answer "none" even if a profile exists, as
  /// when another device creates it right after this one looked.
  bool hideProfileOnce = false;

  /// How many times [pull] was called.
  int pulls = 0;

  @override
  Future<List<RemoteItem>> pull(DateTime? since) async {
    pulls++;
    await pullGate;
    return super.pull(since);
  }

  @override
  Future<RemoteProfile?> loadProfile() async {
    if (hideProfileOnce) {
      hideProfileOnce = false;
      return null;
    }
    return super.loadProfile();
  }

  @override
  Future<void> saveProfile(RemoteProfile profile) async {
    if (failSaves) throw const AccountException('sin red');
    await super.saveProfile(profile);
  }
}

/// One simulated device: its own database, secure storage and session.
class Device {
  Device(
    InMemorySyncBackend backend,
    Map<String, String> accounts, {
    bool requireConfirmation = false,
    Duration debounce = const Duration(seconds: 3),
    Duration progressDebounce = const Duration(seconds: 60),
    Duration pullInterval = const Duration(minutes: 5),
  }) : auth = FakeAuthGateway(
         accounts,
         requireConfirmation: requireConfirmation,
       ) {
    service = AccountService(
      db: db,
      auth: auth,
      backend: backend,
      keys: keys,
      passwords: passwords,
      onSettingsChanged: () => settingsChanges++,
      debounce: debounce,
      progressDebounce: progressDebounce,
      pullInterval: pullInterval,
    );
    addTearDown(service.dispose);
  }

  final db = CatalogDb.inMemory();
  final passwords = FakePasswords();
  final keys = FakeKeyStore();
  final FakeAuthGateway auth;
  late final AccountService service;
  int settingsChanges = 0;

  /// Saves the Xtream test playlist with a password; returns its sync id.
  Future<String> addPlaylist() async {
    final id = db.savePlaylist(_xtream);
    await passwords.write(id, 'secret-pass');
    return db.playlists().single.syncId!;
  }
}

void main() {
  late FlakyBackend backend;
  late Map<String, String> accounts;

  setUp(() {
    backend = FlakyBackend();
    accounts = {};
  });

  test(
    'signUp creates the profile and key and uploads encrypted data',
    () async {
      final a = Device(backend, accounts);
      await a.addPlaylist();

      await a.service.signUp(_email, _password);

      expect(a.service.status, AccountStatus.signedIn);
      expect(a.service.email, _email);
      expect(a.service.lastSync, isNotNull);
      expect(a.keys.key, hasLength(32));
      final profile = (await backend.loadProfile())!;
      final wrapKey = await SyncCrypto.deriveKey(
        _password,
        base64Decode(profile.kdfSalt),
      );
      expect(await SyncCrypto.open(wrapKey, profile.wrappedKey), a.keys.key);
      final uploaded = backend.items.map((i) => i.payload).join();
      expect(backend.items, isNotEmpty);
      expect(uploaded, isNot(contains('secret')));
    },
  );

  test('a second device signs in and receives the playlist', () async {
    final a = Device(backend, accounts);
    final syncId = await a.addPlaylist();
    await a.service.signUp(_email, _password);

    final b = Device(backend, accounts);
    await b.service.signIn(_email, _password);

    expect(b.service.status, AccountStatus.signedIn);
    final arrived = b.db.playlists().single;
    expect(arrived.syncId, syncId);
    expect(await b.passwords.read(arrived.id!), 'secret-pass');
    expect(b.service.playlistsToRefresh.value.map((p) => p.syncId), [syncId]);
    expect(b.settingsChanges, 0, reason: "no settings travelled");
    expect(b.keys.key, a.keys.key);
  });

  test('a wrong login password throws AccountException', () async {
    final a = Device(backend, accounts);
    await a.service.signUp(_email, _password);

    final b = Device(backend, accounts);
    await expectLater(
      b.service.signIn(_email, 'nope'),
      throwsA(isA<AccountException>()),
    );
    expect(b.service.status, AccountStatus.signedOut);
    expect(b.service.lastError, isNotNull);
    expect(b.keys.key, isNull);
  });

  test('changePassword re-wraps the key and leaves the items alone', () async {
    final a = Device(backend, accounts);
    await a.addPlaylist();
    await a.service.signUp(_email, _password);
    final payloadsBefore = backend.items.map((i) => i.payload).toList();

    await expectLater(
      a.service.changePassword('wrong', 'new password'),
      throwsA(isA<AccountException>()),
    );
    await a.service.changePassword(_password, 'new password');

    final profile = (await backend.loadProfile())!;
    final salt = base64Decode(profile.kdfSalt);
    final oldKey = await SyncCrypto.deriveKey(_password, salt);
    await expectLater(
      SyncCrypto.open(oldKey, profile.wrappedKey),
      throwsA(isA<SyncCryptoException>()),
    );
    final newKey = await SyncCrypto.deriveKey('new password', salt);
    expect(await SyncCrypto.open(newKey, profile.wrappedKey), a.keys.key);
    expect(backend.items.map((i) => i.payload).toList(), payloadsBefore);
    expect(accounts[_email], 'new password');

    final b = Device(backend, accounts);
    await b.service.signIn(_email, 'new password');
    expect(b.db.playlists(), hasLength(1));
  });

  test(
    'a changed remote key needs a reset, which uploads this device',
    () async {
      final a = Device(backend, accounts);
      final aSyncId = await a.addPlaylist();
      await a.service.signUp(_email, _password);
      // The password was reset elsewhere: the profile now wraps another key.
      final salt = SyncCrypto.randomBytes(16);
      final other = await SyncCrypto.deriveKey('another password', salt);
      await backend.saveProfile(
        RemoteProfile(
          kdfSalt: base64Encode(salt),
          wrappedKey: await SyncCrypto.seal(other, SyncCrypto.randomBytes(32)),
        ),
      );
      final itemsBefore = backend.items.length;

      final b = Device(backend, accounts);
      final bSyncId = await b.addPlaylist();
      await b.service.signIn(_email, _password);

      expect(b.service.status, AccountStatus.needsReset);
      expect(b.keys.key, isNull);
      expect(backend.items, hasLength(itemsBefore), reason: 'nothing deleted');

      await b.service.resetRemoteData(_password);

      expect(b.service.status, AccountStatus.signedIn);
      final ids = backend.items.map((i) => i.itemId).toList();
      expect(ids, contains(bSyncId));
      expect(ids, isNot(contains(aSyncId)));
      final profile = (await backend.loadProfile())!;
      final wrapKey = await SyncCrypto.deriveKey(
        _password,
        base64Decode(profile.kdfSalt),
      );
      expect(await SyncCrypto.open(wrapKey, profile.wrappedKey), b.keys.key);
    },
  );

  test('signOut clears the key and cursor but keeps local data', () async {
    final a = Device(backend, accounts);
    await a.addPlaylist();
    await a.service.signUp(_email, _password);
    expect(a.db.syncCursor(), isNotNull);

    await a.service.signOut();

    expect(a.service.status, AccountStatus.signedOut);
    expect(a.keys.key, isNull);
    expect(a.db.syncCursor(), isNull);
    expect(a.auth.userId, isNull);
    expect(a.db.playlists(), hasLength(1));
  });

  test(
    'signUp needing confirmation waits, then signIn creates the profile',
    () async {
      final a = Device(backend, accounts, requireConfirmation: true);
      await a.addPlaylist();

      await a.service.signUp(_email, _password);

      expect(a.service.status, AccountStatus.awaitingConfirmation);
      expect(await backend.loadProfile(), isNull);
      expect(a.keys.key, isNull);

      await a.service.signIn(_email, _password);

      expect(a.service.status, AccountStatus.signedIn);
      expect(await backend.loadProfile(), isNotNull);
      expect(backend.items, isNotEmpty);
    },
  );

  test('start syncs when a key and a session exist', () async {
    final a = Device(backend, accounts);
    await a.service.signUp(_email, _password);

    final restarted = AccountService(
      db: a.db,
      auth: a.auth,
      backend: backend,
      keys: a.keys,
      passwords: a.passwords,
    );
    addTearDown(restarted.dispose);
    await restarted.start();

    expect(restarted.status, AccountStatus.signedIn);
    expect(restarted.lastSync, isNotNull);
  });

  test('start without a stored key drops the session', () async {
    final a = Device(backend, accounts);
    await a.service.signUp(_email, _password);
    a.keys.key = null;

    final restarted = AccountService(
      db: a.db,
      auth: a.auth,
      backend: backend,
      keys: a.keys,
      passwords: a.passwords,
    );
    addTearDown(restarted.dispose);
    await restarted.start();

    expect(restarted.status, AccountStatus.signedOut);
    expect(a.auth.userId, isNull);
  });

  test('syncs periodically while signed in and stops after sign-out', () async {
    final a = Device(
      backend,
      accounts,
      pullInterval: const Duration(milliseconds: 20),
    );
    await a.service.signUp(_email, _password);
    final before = backend.pulls;
    for (var i = 0; i < 100 && backend.pulls < before + 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(backend.pulls, greaterThanOrEqualTo(before + 2));

    await a.service.signOut();
    final after = backend.pulls;
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(backend.pulls, after);
  });

  test('a local change triggers a sync after the debounce', () async {
    final a = Device(
      backend,
      accounts,
      debounce: const Duration(milliseconds: 20),
    );
    await a.service.signUp(_email, _password);
    final before = backend.items.length;

    await a.addPlaylist();
    for (var i = 0; i < 100 && backend.items.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(backend.items.length, greaterThan(before));
  });

  test(
    'a failing sync keeps a Spanish error without leaking details',
    () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      backend.overwrite(
        RemoteItem(
          kind: 'favorite',
          itemId: 'foreign',
          payload: base64Encode(List.filled(40, 7)),
          updatedAt: DateTime.now().toUtc(),
          deleted: false,
          syncedAt: DateTime.utc(2027),
        ),
      );

      await a.service.syncNow();

      expect(a.service.lastError, isNotNull);
      expect(a.service.lastError, isNot(contains('Exception')));
      expect(a.service.syncing, isFalse);
    },
  );

  test('unreadable elements are skipped with a Spanish warning', () async {
    final a = Device(backend, accounts);
    await a.addPlaylist();
    await a.service.signUp(_email, _password);
    backend.overwrite(
      RemoteItem(
        kind: 'favorite',
        itemId: 'foreign',
        payload: base64Encode(List.filled(40, 7)),
        updatedAt: DateTime.now().toUtc(),
        deleted: false,
        syncedAt: DateTime.utc(2027),
      ),
    );

    await a.service.syncNow();

    expect(a.service.lastError, contains('omitido'));
    expect(a.service.lastSync, isNotNull);
    expect(a.service.status, AccountStatus.signedIn);
  });

  group('password change and recovery', () {
    /// True when [password] opens the wrapped key in the stored profile.
    Future<bool> profileOpensWith(String password) async {
      final profile = (await backend.loadProfile())!;
      final wrapKey = await SyncCrypto.deriveKey(
        password,
        base64Decode(profile.kdfSalt),
      );
      try {
        await SyncCrypto.open(wrapKey, profile.wrappedKey);
        return true;
      } on SyncCryptoException {
        return false;
      }
    }

    test('the new wrap is saved before the password is updated', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      var openedWithNewDuringUpdate = false;
      a.auth.onUpdatePassword = () async {
        openedWithNewDuringUpdate = await profileOpensWith('new password');
      };

      await a.service.changePassword(_password, 'new password');

      expect(openedWithNewDuringUpdate, isTrue);
    });

    test(
      'if updating the password fails the old profile is restored',
      () async {
        final a = Device(backend, accounts);
        await a.service.signUp(_email, _password);
        final before = (await backend.loadProfile())!;
        a.auth.onUpdatePassword = () async =>
            throw const AccountException('sin red');

        await expectLater(
          a.service.changePassword(_password, 'new password'),
          throwsA(isA<AccountException>()),
        );

        final after = (await backend.loadProfile())!;
        expect(after.kdfSalt, before.kdfSalt);
        expect(after.wrappedKey, before.wrappedKey);
        expect(accounts[_email], _password);
        expect(await profileOpensWith(_password), isTrue);
      },
    );

    /// A change interrupted for good: the profile wraps the new password but
    /// the account still has the old one.
    Future<Device> halfDoneChange() async {
      final a = Device(backend, accounts);
      await a.addPlaylist();
      await a.service.signUp(_email, _password);
      a.auth.onUpdatePassword = () async {
        backend.failSaves = true;
        throw const AccountException('sin red');
      };
      await expectLater(
        a.service.changePassword(_password, 'new password'),
        throwsA(isA<AccountException>()),
      );
      backend.failSaves = false;
      a.auth.onUpdatePassword = null;
      expect(await profileOpensWith('new password'), isTrue);
      return a;
    }

    test('signIn re-wraps the stored key of the same user', () async {
      final a = await halfDoneChange();
      final key = a.keys.key;

      await a.service.signIn(_email, _password);

      expect(a.service.status, AccountStatus.signedIn);
      expect(await profileOpensWith(_password), isTrue);
      expect(a.keys.key, key);
    });

    test(
      'a stored key that does not open the cloud data is not used',
      () async {
        final a = await halfDoneChange();
        a.keys.key = SyncCrypto.randomBytes(32);
        final before = (await backend.loadProfile())!;

        await a.service.signIn(_email, _password);

        expect(a.service.status, AccountStatus.needsReset);
        expect((await backend.loadProfile())!.wrappedKey, before.wrappedKey);
      },
    );

    test('a stored key of another user is not used', () async {
      final a = await halfDoneChange();
      accounts['otro@example.com'] = _password;

      await a.service.signIn('otro@example.com', _password);

      expect(a.service.status, AccountStatus.needsReset);
      expect(await profileOpensWith(_password), isFalse);
    });
  });

  test('a profile created meanwhile by another device is used', () async {
    final a = Device(backend, accounts);
    await a.addPlaylist();
    await a.service.signUp(_email, _password);
    final created = (await backend.loadProfile())!;

    final b = Device(backend, accounts);
    backend.hideProfileOnce = true;
    await b.service.signIn(_email, _password);

    expect(b.service.status, AccountStatus.signedIn);
    expect(b.keys.key, a.keys.key);
    expect((await backend.loadProfile())!.wrappedKey, created.wrappedKey);
    expect(b.db.playlists(), hasLength(1));
  });

  group('sign-out and sign-in races', () {
    test('a pending debounced sync does not run after signOut', () async {
      final a = Device(
        backend,
        accounts,
        debounce: const Duration(milliseconds: 20),
      );
      await a.service.signUp(_email, _password);
      final gate = Completer<void>();
      a.auth.signOutGate = gate.future;
      final pullsBefore = backend.pulls;

      await a.addPlaylist(); // schedules a sync in 20 ms
      final signingOut = a.service.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(backend.pulls, pullsBefore, reason: 'the timer must be gone');
      gate.complete();
      await signingOut;

      expect(a.service.status, AccountStatus.signedOut);
      expect(backend.pulls, pullsBefore);
      expect(a.db.syncCursor(), isNull);
    });

    test('a sync in flight when signing out leaves no cursor behind', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      final gate = Completer<void>();
      backend.pullGate = gate.future;

      final syncing = a.service.syncNow();
      final signingOut = a.service.signOut();
      gate.complete();
      await Future.wait([syncing, signingOut]);

      expect(a.db.syncCursor(), isNull);
    });

    test('signIn always starts from an empty cursor', () async {
      final a = Device(backend, accounts);
      final syncId = await a.addPlaylist();
      await a.service.signUp(_email, _password);

      final b = Device(backend, accounts);
      b.db.saveSyncCursor(DateTime.utc(2099));
      await b.service.signIn(_email, _password);

      expect(b.db.playlists().single.syncId, syncId);
    });
  });

  group('switching accounts', () {
    const otherEmail = 'otra@example.com';

    /// A device that was signed in as the first account, signed out, and has
    /// a local playlist made since.
    Future<(Device, String)> signedOutWithLocalPlaylist({
      Duration debounce = const Duration(seconds: 3),
    }) async {
      accounts[otherEmail] = _password;
      final a = Device(backend, accounts, debounce: debounce);
      await a.service.signUp(_email, _password);
      await a.service.signOut();
      return (a, await a.addPlaylist());
    }

    test(
      'a different account must choose what to do with local data',
      () async {
        final (a, _) = await signedOutWithLocalPlaylist();
        final itemsBefore = backend.items.length;

        await a.service.signIn(otherEmail, _password);

        expect(a.service.status, AccountStatus.chooseLocalData);
        expect(backend.items, hasLength(itemsBefore), reason: 'nothing synced');
        expect(a.db.playlists(), hasLength(1));
      },
    );

    test('nothing syncs while the choice is pending', () async {
      final (a, _) = await signedOutWithLocalPlaylist(
        debounce: const Duration(milliseconds: 20),
      );
      await a.service.signIn(otherEmail, _password);
      final pulls = backend.pulls;

      a.db.savePlaylist(_xtream.copyWith(name: 'Otra'));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(backend.pulls, pulls);
      expect(a.service.status, AccountStatus.chooseLocalData);
    });

    test('merging uploads the local data to the new account', () async {
      final (a, syncId) = await signedOutWithLocalPlaylist();
      await a.service.signIn(otherEmail, _password);

      await a.service.resolveLocalData(merge: true);

      expect(a.service.status, AccountStatus.signedIn);
      expect(backend.items.map((i) => i.itemId), contains(syncId));
      expect(a.db.playlists(), hasLength(1));
    });

    test('discarding deletes local data and downloads the account', () async {
      final remote = Device(backend, accounts);
      final remoteSyncId = await remote.addPlaylist();
      await remote.service.signUp(_email, _password);

      accounts[otherEmail] = _password;
      final a = Device(backend, accounts);
      await a.service.signIn(_email, _password);
      await a.service.signOut();
      final localId = a.db.savePlaylist(
        const Playlist(
          name: 'Local',
          type: PlaylistType.m3uUrl,
          source: 'http://x/l.m3u',
        ),
      );
      await a.passwords.write(localId, 'local-pass');
      a.db.setFavorite(localId, MediaKind.live, 'k', true);
      a.db.saveDefaultChannelSort(const ChannelSort(mode: SortMode.alphaAsc));
      await a.service.signIn(otherEmail, _password);
      expect(a.service.status, AccountStatus.chooseLocalData);

      await a.service.resolveLocalData(merge: false);

      expect(a.service.status, AccountStatus.signedIn);
      expect(a.db.playlists().map((p) => p.syncId), [remoteSyncId]);
      expect(a.passwords.values.values, ['secret-pass']);
      expect(a.db.allFavorites(), isEmpty);
      expect(backend.items.where((i) => i.deleted), isEmpty);
    });

    test('the same account signing back in is not asked', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      await a.service.signOut();
      await a.addPlaylist();

      await a.service.signIn(_email, _password);

      expect(a.service.status, AccountStatus.signedIn);
    });

    test('resolveLocalData outside the choice is an error', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);

      await expectLater(
        a.service.resolveLocalData(merge: true),
        throwsA(isA<AccountException>()),
      );
    });
  });

  group('recovery codes and password length', () {
    const newPassword = 'brand new password';

    test('a reset by code on a device without the key needs a reset', () async {
      final a = Device(backend, accounts);
      await a.addPlaylist();
      await a.service.signUp(_email, _password);

      final b = Device(backend, accounts);
      await b.service.recoverPassword(
        _email,
        FakeAuthGateway.validCode,
        newPassword,
      );

      expect(accounts[_email], newPassword);
      expect(b.service.status, AccountStatus.needsReset);
      await b.service.resetRemoteData(newPassword);
      expect(b.service.status, AccountStatus.signedIn);
    });

    test('a device that still holds the key keeps the cloud data', () async {
      final a = Device(backend, accounts);
      await a.addPlaylist();
      await a.service.signUp(_email, _password);
      final key = a.keys.key;
      await a.auth.signOut(); // the session expired; the key stays stored
      final itemsBefore = backend.items.map((i) => i.payload).toList();

      await a.service.recoverPassword(
        _email,
        FakeAuthGateway.validCode,
        newPassword,
      );

      expect(a.service.status, AccountStatus.signedIn);
      expect(a.keys.key, key);
      expect(backend.items.map((i) => i.payload), containsAll(itemsBefore));
      final c = Device(backend, accounts);
      await c.service.signIn(_email, newPassword);
      expect(c.db.playlists(), hasLength(1));
    });

    test('a wrong code changes nothing', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      await a.service.signOut();

      await expectLater(
        a.service.recoverPassword(_email, '000000', newPassword),
        throwsA(isA<AccountException>()),
      );

      expect(accounts[_email], _password);
      expect(a.service.status, AccountStatus.signedOut);
    });

    test('a short new password is refused before using the code', () async {
      final a = Device(backend, accounts);
      await a.service.signUp(_email, _password);
      await a.service.signOut();

      await expectLater(
        a.service.recoverPassword(_email, FakeAuthGateway.validCode, 'short'),
        throwsA(isA<AccountException>()),
      );

      expect(accounts[_email], _password);
      expect(a.service.lastError, contains('10'));
    });

    test('confirming the sign-up code opens the account', () async {
      final a = Device(backend, accounts, requireConfirmation: true);
      await a.addPlaylist();
      await a.service.signUp(_email, _password);
      expect(a.service.status, AccountStatus.awaitingConfirmation);

      await expectLater(
        a.service.confirmSignUp(_email, '000000', _password),
        throwsA(isA<AccountException>()),
      );
      await a.service.confirmSignUp(
        _email,
        FakeAuthGateway.validCode,
        _password,
      );

      expect(a.service.status, AccountStatus.signedIn);
      expect(await backend.loadProfile(), isNotNull);
      expect(backend.items, isNotEmpty);
    });

    test('passwords under 10 characters are refused', () async {
      final a = Device(backend, accounts);
      await expectLater(
        a.service.signUp(_email, '123456789'),
        throwsA(isA<AccountException>()),
      );
      expect(accounts, isEmpty);
      expect(a.service.lastError, contains('10'));

      await a.service.signUp(_email, _password);
      await expectLater(
        a.service.changePassword(_password, 'short'),
        throwsA(isA<AccountException>()),
      );
      expect(accounts[_email], _password);
    });
  });

  group('quiet and slow triggers', () {
    test('onSettingsChanged fires only when settings were applied', () async {
      final a = Device(backend, accounts);
      a.db.saveSettings(const AppSettings(networkCacheSecs: 60).toJson());
      await a.service.signUp(_email, _password);

      final b = Device(backend, accounts);
      await b.service.signIn(_email, _password);

      expect(b.settingsChanges, 1);
      await b.service.syncNow();
      expect(b.settingsChanges, 1, reason: 'nothing new, nothing reloaded');
    });

    test('progress alone waits for the longer debounce', () async {
      final a = Device(
        backend,
        accounts,
        debounce: const Duration(milliseconds: 20),
        progressDebounce: const Duration(seconds: 30),
      );
      await a.addPlaylist();
      await a.service.signUp(_email, _password);
      final playlistId = a.db.playlists().single.id!;
      final pulls = backend.pulls;

      a.db.saveProgress(
        playlistId,
        const PlayTarget(kind: MediaKind.movie, key: 'xm:5', title: 'Peli'),
        const Duration(seconds: 1),
        const Duration(seconds: 9),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(backend.pulls, pulls, reason: 'progress is not urgent');

      a.db.setFavorite(playlistId, MediaKind.live, 'k', true);
      for (var i = 0; i < 100 && backend.pulls == pulls; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(backend.pulls, greaterThan(pulls));
    });

    test('progress does not postpone a sync already scheduled', () async {
      final a = Device(
        backend,
        accounts,
        debounce: const Duration(milliseconds: 20),
        progressDebounce: const Duration(seconds: 30),
      );
      await a.addPlaylist();
      await a.service.signUp(_email, _password);
      final playlistId = a.db.playlists().single.id!;
      final pulls = backend.pulls;

      a.db.setFavorite(playlistId, MediaKind.live, 'k', true);
      a.db.saveProgress(
        playlistId,
        const PlayTarget(kind: MediaKind.movie, key: 'xm:5', title: 'Peli'),
        const Duration(seconds: 1),
        const Duration(seconds: 9),
      );
      for (var i = 0; i < 100 && backend.pulls == pulls; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(backend.pulls, greaterThan(pulls));
    });
  });

  group('settings sync switch', () {
    test(
      'is on by default and turning it on syncs the skipped settings',
      () async {
        final a = Device(backend, accounts);
        await a.service.signUp(_email, _password);
        final b = Device(backend, accounts);
        await b.service.signIn(_email, _password);
        expect(b.service.syncSettings, isTrue);

        await b.service.setSyncSettings(false);
        expect(b.service.syncSettings, isFalse);
        a.db.saveSettings(const AppSettings(networkCacheSecs: 60).toJson());
        await a.service.syncNow();
        await b.service.syncNow();
        expect(b.settingsChanges, 0);

        await b.service.setSyncSettings(true);
        expect(b.settingsChanges, 1, reason: 'turning it on syncs right away');
        expect(AppSettings.fromJson(b.db.loadSettings()).networkCacheSecs, 60);
      },
    );
  });
}
