import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/catalog_db.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import 'auth_gateway.dart';
import 'key_store.dart';
import 'sync_backend.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'sync_ids.dart';
import 'sync_items.dart';

/// Where the account stands.
enum AccountStatus {
  /// No account session; the app works locally.
  signedOut,

  /// The account was created but its email still has to be confirmed.
  awaitingConfirmation,

  /// Signed in with the data key available: syncing works.
  signedIn,

  /// Signed in, but the cloud data was encrypted with a key that this password
  /// cannot open (the password was reset). Nothing syncs until the cloud data
  /// is replaced with [AccountService.resetRemoteData].
  needsReset,

  /// Signed in as a different account than the last one on this device, which
  /// still has local playlists. Nothing syncs until the user decides with
  /// [AccountService.resolveLocalData].
  chooseLocalData,
}

/// Shortest password accepted for a new account or a password change.
const minPasswordLength = 10;

const _networkError =
    'No se ha podido conectar con el servidor. Inténtalo de nuevo.';
const _cryptoError =
    'No se pueden descifrar los datos de la nube. Si cambiaste la contraseña '
    'en otro dispositivo, cierra sesión y vuelve a entrar.';

/// Sign-up, sign-in, password changes and automatic synchronisation.
///
/// The data key is created on the first device, wrapped with a key derived
/// from the password and stored in the backend; this service unwraps it on
/// sign-in and keeps it in the [DataKeyStore]. Passwords and keys are never
/// logged and errors reach the UI only as Spanish text in [lastError].
class AccountService extends ChangeNotifier {
  AccountService({
    required this._db,
    required this._auth,
    required this._backend,
    required this._keys,
    required this._passwords,
    this.onSettingsChanged,
    this.debounce = const Duration(seconds: 3),
    this.progressDebounce = const Duration(seconds: 60),
    this.pullInterval = const Duration(minutes: 5),
  });

  final CatalogDb _db;
  final AuthGateway _auth;
  final SyncBackend _backend;
  final DataKeyStore _keys;
  final PasswordStore _passwords;

  /// Called after a sync that applied remote settings, because that changes
  /// the database under the settings controller.
  final void Function()? onSettingsChanged;

  /// How long to wait after a local change before syncing.
  final Duration debounce;

  /// How long to wait when only playback progress changed.
  final Duration progressDebounce;

  /// How often to sync while signed in, to pick up changes made on other
  /// devices.
  final Duration pullInterval;

  /// Playlists that arrived or changed in the last sync and whose catalog has
  /// to be downloaded. A new list is assigned on every sync that has some.
  final playlistsToRefresh = ValueNotifier<List<Playlist>>(const []);

  AccountStatus _status = AccountStatus.signedOut;
  bool _syncing = false;
  DateTime? _lastSync;
  String? _lastError;
  SyncEngine? _engine;
  Future<void>? _running;
  Timer? _debounceTimer;
  Timer? _pullTimer;
  bool _disposed = false;

  /// Current state of the account.
  AccountStatus get status => _status;

  /// Email of the signed-in user, if any.
  String? get email => _auth.email;

  /// Whether signing in with Google is available. Not yet: the welcome screen
  /// shows the button disabled until the auth gateway supports it.
  bool get supportsGoogle => false;

  /// Whether a sync is running.
  bool get syncing => _syncing;

  /// When the last sync finished successfully, if one did.
  DateTime? get lastSync => _lastSync;

  /// Spanish text describing the last failure; cleared by the next action.
  String? get lastError => _lastError;

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _pullTimer?.cancel();
    if (_db.onLocalChange == _scheduleSync) _db.onLocalChange = null;
    playlistsToRefresh.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Resumes a previous session at app start: syncs when both a session and
  /// the data key exist. A session without key cannot decrypt anything, so it
  /// is closed and the user signs in again.
  Future<void> start() async {
    try {
      if (_auth.userId == null) return;
      final key = await _keys.read();
      if (key == null) {
        await _dropSession();
        return;
      }
      _useKey(key);
    } catch (e) {
      _lastError = _messageFor(e);
      notifyListeners();
      return;
    }
    await syncNow();
  }

  /// Creates an account. With a session the encryption profile is created and
  /// the data uploaded; when the email must be confirmed the state becomes
  /// [AccountStatus.awaitingConfirmation] and the user signs in later.
  Future<void> signUp(String email, String password) => _guard(() async {
    _requireLongPassword(password);
    if (!await _auth.signUp(email, password)) {
      _status = AccountStatus.awaitingConfirmation;
      notifyListeners();
      return;
    }
    await _openSession(password);
  });

  /// Signs in, unwrapping the data key (or creating the profile the first
  /// time). When the key cannot be unwrapped the state becomes
  /// [AccountStatus.needsReset]; nothing is deleted.
  Future<void> signIn(String email, String password) => _guard(() async {
    await _auth.signIn(email, password);
    await _openSession(password);
  });

  /// Ends the session and forgets the data key and the sync cursor. Local data
  /// stays. Anything scheduled or running is stopped before the first await,
  /// so nothing can sync (or save a cursor) while the session is closing.
  Future<void> signOut() => _guard(() async {
    _debounceTimer?.cancel();
    _pullTimer?.cancel();
    if (_db.onLocalChange == _scheduleSync) _db.onLocalChange = null;
    _engine?.close();
    _engine = null;
    await _running;
    try {
      await _auth.signOut();
    } finally {
      await _forgetSession();
    }
  });

  /// Changes the password. [oldPassword] is checked by unwrapping the data
  /// key, which is wrapped again with [newPassword] and saved first; only then
  /// the account password changes. If that fails the previous profile is put
  /// back, so the account never ends up with a password that opens nothing.
  /// Synced items are not touched.
  Future<void> changePassword(String oldPassword, String newPassword) =>
      _guard(() async {
        _requireLongPassword(newPassword);
        final profile = await _backend.loadProfile();
        if (_status != AccountStatus.signedIn || profile == null) {
          throw const AccountException('Entra en tu cuenta primero.');
        }
        final dataKey = await _unwrapOrNull(profile, oldPassword);
        if (dataKey == null) {
          throw const AccountException('La contraseña actual no es correcta.');
        }
        await _backend.saveProfile(await _wrap(newPassword, dataKey));
        try {
          await _auth.updatePassword(newPassword);
        } catch (_) {
          try {
            await _backend.saveProfile(profile);
          } catch (_) {
            // Left half done; the next sign-in with the old password
            // re-wraps the stored key (see _recoverStoredKey).
          }
          rethrow;
        }
      });

  /// Emails a code (and a link) to reset the password of [email]. The code is
  /// used with [recoverPassword]; desktop builds have no deep links, so the
  /// code is the way in.
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordReset(email));

  /// Sets [newPassword] using the [code] from the reset email, then opens the
  /// account with it. The data key was wrapped with the old password, so
  /// unless this device still holds the key the state becomes
  /// [AccountStatus.needsReset] (see [resetRemoteData]); nothing is deleted.
  Future<void> recoverPassword(String email, String code, String newPassword) =>
      _guard(() async {
        _requireLongPassword(newPassword);
        await _auth.verifyRecoveryCode(email, code);
        try {
          await _auth.updatePassword(newPassword);
        } catch (_) {
          await _dropSession();
          rethrow;
        }
        await _openSession(newPassword);
      });

  /// Finishes a sign-up that needed email confirmation with the [code] from
  /// the confirmation email; [password] is the one typed when signing up.
  Future<void> confirmSignUp(String email, String code, String password) =>
      _guard(() async {
        await _auth.verifySignupCode(email, code);
        await _openSession(password);
      });

  /// Emails a code to the account so a forgotten parental PIN can be replaced
  /// (see [verifyPinResetCode]). Throws [AccountException] without a session
  /// or when sending fails; [lastError] is left alone, the PIN dialog shows it.
  Future<void> sendPinResetCode() async {
    _requireSignedIn();
    await _auth.sendEmailCode();
  }

  /// Checks the [code] emailed by [sendPinResetCode]. Throws
  /// [AccountException] on a wrong or expired code. The code is never logged.
  Future<void> verifyPinResetCode(String code) async {
    _requireSignedIn();
    await _auth.verifyEmailCode(code);
  }

  /// Throws an [AccountException] unless the account is signed in.
  void _requireSignedIn() {
    if (_status != AccountStatus.signedIn) {
      throw const AccountException('Entra en tu cuenta primero.');
    }
  }

  /// Settles [AccountStatus.chooseLocalData]: with [merge] the playlists and
  /// data on this device are added to the account; without it they are deleted
  /// (with their passwords) and the account's data is downloaded instead.
  Future<void> resolveLocalData({required bool merge}) => _guard(() async {
    if (_status != AccountStatus.chooseLocalData) {
      throw const AccountException('No hay nada que decidir ahora.');
    }
    if (!merge) {
      for (final playlist in _db.playlists()) {
        await _passwords.delete(playlist.id!);
      }
      _db.deleteLocalLibrary();
      _debounceTimer?.cancel();
    }
    _status = AccountStatus.signedIn;
    _db.saveSyncUserId(_auth.userId);
    notifyListeners();
    if (merge) _db.markAllDirty(SyncLocalIndex(_db).allItems());
    await syncNow();
  });

  /// Deletes the cloud data and replaces it with this device's, under a new
  /// data key wrapped with [password] (the account password). The way out of
  /// [AccountStatus.needsReset].
  Future<void> resetRemoteData(String password) => _guard(() async {
    final email = _auth.email;
    if (email == null) {
      throw const AccountException('Entra en tu cuenta primero.');
    }
    await _auth.signIn(email, password);
    await _backend.deleteAll();
    await _createProfile(password, replace: true);
    _db.saveSyncUserId(_auth.userId);
    await syncNow();
  });

  /// Whether this device syncs settings and per-list preferences.
  bool get syncSettings => _db.syncSettingsEnabled();

  /// Turns settings sync on or off on this device only; turning it on syncs
  /// right away, and the newest side wins as usual.
  Future<void> setSyncSettings(bool enabled) async {
    if (enabled == syncSettings) return;
    _db.saveSyncSettingsEnabled(enabled);
    notifyListeners();
    if (enabled) await syncNow();
  }

  /// Synchronises now; returns when done. A call made while a sync runs waits
  /// for that one. Failures end up in [lastError], never thrown.
  Future<void> syncNow() =>
      _running ??= _sync().whenComplete(() => _running = null);

  /// Syncs shortly after a local change, collapsing bursts into one sync.
  /// Playback saves progress every few seconds, so progress alone waits
  /// [progressDebounce] and never postpones a sync already scheduled.
  void _scheduleSync(String kind) {
    if (kind == progressKind) {
      if (_debounceTimer?.isActive != true) {
        _debounceTimer = Timer(progressDebounce, syncNow);
      }
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, syncNow);
  }

  Future<void> _sync() async {
    final engine = _engine;
    if (engine == null || _status != AccountStatus.signedIn) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final report = await engine.syncNow();
      _lastSync = DateTime.now();
      if (report.settingsApplied) onSettingsChanged?.call();
      final toRefresh = [
        ...report.createdPlaylists,
        ...report.changedPlaylists,
      ];
      if (toRefresh.isNotEmpty && !_disposed) {
        playlistsToRefresh.value = toRefresh;
      }
      if (report.skipped > 0) _lastError = _skippedWarning(report.skipped);
    } catch (e) {
      _lastError = _messageFor(e, fallback: _syncError);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Throws an [AccountException] when [password] is shorter than
  /// [minPasswordLength].
  static void _requireLongPassword(String password) {
    if (password.length < minPasswordLength) {
      throw const AccountException(
        'La contraseña debe tener al menos $minPasswordLength caracteres.',
      );
    }
  }

  static String _skippedWarning(int count) => count == 1
      ? 'Se ha omitido 1 elemento de la nube que no se puede leer.'
      : 'Se han omitido $count elementos de la nube que no se pueden leer.';

  static const _syncError =
      'No se ha podido sincronizar. Se reintentará más tarde.';

  /// Runs [action] for a user-triggered operation: clears the last error, and
  /// on failure stores a Spanish message in [lastError] and throws it as an
  /// [AccountException] (never the raw error).
  Future<void> _guard(Future<void> Function() action) async {
    _lastError = null;
    try {
      await action();
    } catch (e) {
      final message = _messageFor(e);
      _lastError = message;
      notifyListeners();
      if (e is AccountException) rethrow;
      throw AccountException(message);
    }
  }

  /// After authenticating: loads the profile and opens it with [password], or
  /// creates it when the account has none. If anything fails the session is
  /// closed again.
  Future<void> _openSession(String password) async {
    // A cursor left by an earlier session must never leak into this one.
    _db.saveSyncCursor(null);
    try {
      final profile = await _backend.loadProfile();
      if (profile == null) {
        await _createProfile(password);
      } else {
        await _openProfile(profile, password);
      }
    } catch (_) {
      await _dropSession();
      rethrow;
    }
    if (_status != AccountStatus.signedIn) return;
    final last = _db.syncUserId();
    if (last != null && last != _auth.userId && _db.playlists().isNotEmpty) {
      _status = AccountStatus.chooseLocalData;
      notifyListeners();
      return;
    }
    _db.saveSyncUserId(_auth.userId);
    await syncNow();
  }

  /// Unwraps the data key of [profile] with [password] and starts using it.
  /// When [password] does not open it but this device still holds a verified
  /// key of the same user, that key is wrapped again with [password] (the
  /// profile of a half-done password change, or of a reset made here). With
  /// neither the state becomes [AccountStatus.needsReset].
  Future<void> _openProfile(RemoteProfile profile, String password) async {
    var dataKey = await _unwrapOrNull(profile, password);
    if (dataKey == null) {
      dataKey = await _recoverStoredKey();
      if (dataKey != null) {
        await _backend.saveProfile(await _wrap(password, dataKey));
      }
    }
    if (dataKey == null) {
      _status = AccountStatus.needsReset;
      notifyListeners();
      return;
    }
    await _keys.write(dataKey);
    _useKey(dataKey);
  }

  /// The data key kept on this device when it belongs to the signed-in user
  /// and really opens the cloud data (a stale key, from before a reset on
  /// another device, would otherwise overwrite the good profile); else `null`.
  Future<List<int>?> _recoverStoredKey() async {
    if (_auth.userId == null || _db.syncUserId() != _auth.userId) return null;
    final key = await _keys.read();
    if (key == null) return null;
    final previousIds = _db.itemIds;
    try {
      final opens = await SyncEngine(
        _db,
        _backend,
        key,
        _passwords,
      ).keyOpensRemoteData();
      return opens ? key : null;
    } finally {
      _db.itemIds = previousIds;
    }
  }

  /// Creates a new data key and encryption profile for [password], stores the
  /// key and forgets the cursor so the next sync uploads everything. The
  /// profile is inserted only if none exists: when another device created one
  /// in the meantime, that one is opened instead. With [replace] (starting
  /// over) the existing profile is overwritten.
  Future<void> _createProfile(String password, {bool replace = false}) async {
    final dataKey = SyncCrypto.randomBytes(32);
    final wrapped = await _wrap(password, dataKey);
    if (replace) {
      await _backend.saveProfile(wrapped);
    } else if (!await _backend.createProfile(wrapped)) {
      final existing = await _backend.loadProfile();
      if (existing == null) throw const AccountException(_networkError);
      await _openProfile(existing, password);
      return;
    }
    await _keys.write(dataKey);
    _db.saveSyncCursor(null);
    _useKey(dataKey);
  }

  void _useKey(List<int> dataKey) {
    _engine?.close();
    _engine = SyncEngine(_db, _backend, dataKey, _passwords);
    _db.onLocalChange = _scheduleSync;
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(pullInterval, (_) => unawaited(syncNow()));
    _status = AccountStatus.signedIn;
    notifyListeners();
  }

  /// Wraps [dataKey] with a key derived from [password] and a fresh salt.
  Future<RemoteProfile> _wrap(String password, List<int> dataKey) async {
    final salt = SyncCrypto.randomBytes(16);
    final wrapKey = await SyncCrypto.deriveKey(password, salt);
    return RemoteProfile(
      kdfSalt: base64Encode(salt),
      wrappedKey: await SyncCrypto.seal(wrapKey, dataKey),
    );
  }

  /// The data key in [profile], or `null` when [password] does not open it.
  Future<List<int>?> _unwrapOrNull(
    RemoteProfile profile,
    String password,
  ) async {
    final wrapKey = await SyncCrypto.deriveKey(
      password,
      base64Decode(profile.kdfSalt),
    );
    try {
      return await SyncCrypto.open(wrapKey, profile.wrappedKey);
    } on SyncCryptoException {
      return null;
    }
  }

  /// Closes the session, ignoring failures (used when the key is lost or
  /// opening the session failed).
  Future<void> _dropSession() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Nothing more to do: the local state is reset below anyway.
    }
    await _forgetSession();
  }

  /// Forgets the data key, the cursor and the engine; local data stays.
  Future<void> _forgetSession() async {
    _debounceTimer?.cancel();
    _pullTimer?.cancel();
    if (_db.onLocalChange == _scheduleSync) _db.onLocalChange = null;
    _engine?.close();
    _engine = null;
    _db.itemIds = null;
    await _keys.clear();
    _db.saveSyncCursor(null);
    _lastSync = null;
    _status = AccountStatus.signedOut;
    notifyListeners();
  }

  /// A user-facing Spanish message for [error]; never its raw text.
  static String _messageFor(Object error, {String fallback = _networkError}) =>
      switch (error) {
        AccountException(:final message) => message,
        SyncCryptoException() => _cryptoError,
        _ => fallback,
      };
}
