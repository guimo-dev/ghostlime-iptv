import 'dart:async';
import 'dart:typed_data';

import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/key_store.dart';

/// Auth that keeps accounts in a map shared between "devices"; each instance
/// has its own session.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway(
    this.accounts, {
    this.requireConfirmation = false,
    Map<String, Uint8List>? escrow,
  }) : escrow = escrow ?? {};

  final Map<String, String> accounts;
  bool requireConfirmation;

  /// The server's escrowed data keys by user id; share one map between
  /// devices to simulate one server.
  final Map<String, Uint8List> escrow;

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

  /// How many account codes [sendEmailCode] has sent.
  int emailCodesSent = 0;

  /// When set, [sendEmailCode] throws it (e.g. the rate limit).
  AccountException? emailCodeError;

  @override
  Future<void> sendEmailCode() async {
    if (_email == null) {
      throw const AccountException('Entra en tu cuenta primero.');
    }
    if (emailCodeError case final error?) throw error;
    emailCodesSent++;
  }

  @override
  Future<void> verifyEmailCode(String code) async {
    if (_email == null || code != validCode) {
      throw const AccountException('El código no es correcto o ha caducado.');
    }
  }

  /// How many times [deleteAccount] succeeded.
  int accountsDeleted = 0;

  /// When set, [deleteAccount] throws it (e.g. no network).
  AccountException? deleteAccountError;

  @override
  Future<void> deleteAccount() async {
    if (_email == null) {
      throw const AccountException('Entra en tu cuenta primero.');
    }
    if (deleteAccountError case final error?) throw error;
    accounts.remove(_email);
    accountsDeleted++;
  }

  @override
  bool supportsGoogle = false;

  /// The Google account the "browser" signs in with in
  /// [signInWithOAuthGoogle]; Supabase links it by email, so an existing
  /// email account gets the same user id.
  String googleEmail = 'google@example.com';

  /// When set, [signInWithOAuthGoogle] throws it (cancelled or failed).
  AccountException? oauthError;

  /// How many times [cancelOAuthGoogle] was called.
  int oauthCancels = 0;

  /// When set, [signInWithOAuthGoogle] waits for it, as for the browser;
  /// [cancelOAuthGoogle] fails it.
  Completer<void>? browser;

  @override
  Future<void> signInWithOAuthGoogle() async {
    await browser?.future;
    if (oauthError case final error?) throw error;
    _email = googleEmail;
  }

  @override
  void cancelOAuthGoogle() {
    oauthCancels++;
    final pending = browser;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const AccountException('Se ha cancelado el acceso con Google.'),
      );
    }
  }

  /// When set, [fetchEscrowedKey] throws it (e.g. no network).
  AccountException? escrowError;

  /// Runs first in [storeEscrowedKey], e.g. to let another device win.
  Future<void> Function()? beforeStoreEscrowedKey;

  /// How many keys [storeEscrowedKey] was asked to store.
  int escrowStores = 0;

  @override
  Future<Uint8List?> fetchEscrowedKey() async {
    if (escrowError case final error?) throw error;
    return escrow[_signedInUserId()];
  }

  /// Like the `key-escrow` function: keeps the first key, never replaces it.
  @override
  Future<void> storeEscrowedKey(Uint8List key) async {
    await beforeStoreEscrowedKey?.call();
    escrowStores++;
    escrow.putIfAbsent(_signedInUserId(), () => key);
  }

  /// The signed-in user id; throws [AccountException] without a session.
  String _signedInUserId() =>
      userId ?? (throw const AccountException('Entra en tu cuenta primero.'));
}

/// In-memory stand-in for the secure storage of the sync key.
class FakeKeyStore implements DataKeyStore {
  List<int>? key;

  @override
  Future<List<int>?> read() async => key;

  @override
  Future<void> write(List<int> key) async => this.key = key;

  @override
  Future<void> clear() async => key = null;
}
