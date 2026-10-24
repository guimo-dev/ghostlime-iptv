import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/sync_backend.dart';

import 'fake_account.dart';
import 'fake_passwords.dart';

const _email = 'ana@example.com';
const _password = 'correct horse';
const _wrongCode = 'El código no es correcto o ha caducado.';
const _networkMessage =
    'No hay conexión con el servidor. Comprueba tu red e inténtalo de nuevo.';

void main() {
  late CatalogDb db;
  late FakeAuthGateway auth;
  late FakeKeyStore keys;
  late FakePasswords passwords;
  late MemoryPinStore pins;
  late AccountService service;
  var settingsChanges = 0;

  setUp(() async {
    settingsChanges = 0;
    db = CatalogDb.inMemory();
    auth = FakeAuthGateway({});
    keys = FakeKeyStore();
    passwords = FakePasswords();
    pins = MemoryPinStore();
    service = AccountService(
      db: db,
      auth: auth,
      backend: InMemorySyncBackend(),
      keys: keys,
      passwords: passwords,
      pins: pins,
      onSettingsChanged: () => settingsChanges++,
    );
    final id = db.savePlaylist(
      const Playlist(name: 'A', type: PlaylistType.m3uUrl, source: 's'),
    );
    await passwords.write(id, 'secret-pass');
    db.saveSettings(const AppSettings(networkCacheSecs: 60).toJson());
    await pins.setPin('1234');
    await service.signUp(_email, _password);
  });

  tearDown(() {
    service.dispose();
    db.close();
  });

  /// Whether the device still has its playlists, settings and PIN.
  Future<bool> deviceIntact() async =>
      db.playlists().length == 1 &&
      passwords.values.isNotEmpty &&
      db.loadSettings().isNotEmpty &&
      await pins.hasPin();

  test('a wrong code deletes nothing', () async {
    await expectLater(
      service.deleteAccount(code: '000000', wipeDevice: true),
      throwsA(
        isA<AccountException>().having((e) => e.message, 'message', _wrongCode),
      ),
    );

    expect(auth.accountsDeleted, 0);
    expect(service.status, AccountStatus.signedIn);
    expect(keys.key, isNotNull);
    expect(await deviceIntact(), isTrue);
  });

  test('without network nothing is deleted', () async {
    auth.deleteAccountError = const AccountException(_networkMessage);

    await expectLater(
      service.deleteAccount(code: FakeAuthGateway.validCode, wipeDevice: true),
      throwsA(
        isA<AccountException>().having(
          (e) => e.message,
          'message',
          _networkMessage,
        ),
      ),
    );

    expect(service.lastError, _networkMessage);
    expect(service.status, AccountStatus.signedIn);
    expect(keys.key, isNotNull);
    expect(await deviceIntact(), isTrue);
  });

  test('the right code deletes the account, signs out and drops the key, '
      'keeping the local lists', () async {
    await service.deleteAccount(
      code: FakeAuthGateway.validCode,
      wipeDevice: false,
    );

    expect(auth.accountsDeleted, 1);
    expect(auth.userId, isNull);
    expect(service.status, AccountStatus.signedOut);
    expect(keys.key, isNull);
    expect(db.playlists(), hasLength(1));
    expect(db.loadSettings()['networkCacheSecs'], 60);
  });

  test(
    'without wipe the parental lock goes off and the PIN is deleted',
    () async {
      db.saveSettings(
        const AppSettings(networkCacheSecs: 60, parentalLock: true).toJson(),
      );

      await service.deleteAccount(
        code: FakeAuthGateway.validCode,
        wipeDevice: false,
      );

      expect(AppSettings.fromJson(db.loadSettings()).parentalLock, isFalse);
      expect(await pins.hasPin(), isFalse);
      expect(settingsChanges, 1);
    },
  );

  test('wipeDevice also deletes lists, settings and PIN', () async {
    await service.deleteAccount(
      code: FakeAuthGateway.validCode,
      wipeDevice: true,
    );

    expect(auth.accountsDeleted, 1);
    expect(service.status, AccountStatus.signedOut);
    expect(keys.key, isNull);
    expect(db.playlists(), isEmpty);
    expect(passwords.values, isEmpty);
    expect(db.loadSettings(), isEmpty);
    expect(await pins.hasPin(), isFalse);
    expect(settingsChanges, 1);
  });

  test('sending the code needs a session', () async {
    await service.signOut();

    await expectLater(
      service.sendDeleteAccountCode(),
      throwsA(isA<AccountException>()),
    );
    expect(auth.emailCodesSent, 0);
  });
}
