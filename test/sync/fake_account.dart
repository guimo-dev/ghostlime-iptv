import 'package:iptv_player/sync/auth_gateway.dart';
import 'package:iptv_player/sync/key_store.dart';

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
