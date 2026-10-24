import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// An account error with a message that is safe to show to the user (Spanish,
/// never the raw server text).
class AccountException implements Exception {
  const AccountException(this.message);

  final String message;

  @override
  String toString() => 'AccountException: $message';
}

/// Email and password authentication, apart from any particular service so the
/// account logic can be tested with a fake.
abstract class AuthGateway {
  /// Id of the signed-in user, or `null` without a session.
  String? get userId;

  /// Email of the signed-in user, or `null` without a session.
  String? get email;

  /// Creates the account. Returns `true` when a session started, `false` when
  /// the email has to be confirmed first. Throws [AccountException].
  Future<bool> signUp(String email, String password);

  /// Starts a session. Throws [AccountException] on wrong credentials.
  Future<void> signIn(String email, String password);

  /// Ends the session.
  Future<void> signOut();

  /// Changes the signed-in user's password.
  Future<void> updatePassword(String newPassword);

  /// Emails a code (and link) to reset the password.
  Future<void> sendPasswordReset(String email);

  /// Completes a password recovery with the code from the reset email: starts
  /// a session on success. Throws [AccountException] on a wrong or expired
  /// code.
  Future<void> verifyRecoveryCode(String email, String code);

  /// Confirms a new account with the code from the confirmation email: starts
  /// a session on success. Throws [AccountException] on a wrong or expired
  /// code.
  Future<void> verifySignupCode(String email, String code);

  /// Emails the signed-in user a one-time code that proves they own the
  /// account (used to replace a forgotten parental PIN). Throws
  /// [AccountException].
  Future<void> sendEmailCode();

  /// Checks the [code] sent by [sendEmailCode]. Throws [AccountException] on a
  /// wrong or expired code.
  Future<void> verifyEmailCode(String code);

  /// Deletes the signed-in user and all their server data (the `delete-account`
  /// Edge Function, called with the current session). Throws
  /// [AccountException].
  Future<void> deleteAccount();
}

/// [AuthGateway] over Supabase Auth. Needs `Supabase.initialize` to have run.
class SupabaseAuthGateway implements AuthGateway {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  String? get userId => _auth.currentUser?.id;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Future<bool> signUp(String email, String password) => _translate(() async {
    final response = await _auth.signUp(email: email, password: password);
    return response.session != null;
  });

  @override
  Future<void> signIn(String email, String password) => _translate(
    () => _auth.signInWithPassword(email: email, password: password),
  );

  @override
  Future<void> signOut() => _translate(_auth.signOut);

  @override
  Future<void> updatePassword(String newPassword) =>
      _translate(() => _auth.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<void> sendPasswordReset(String email) =>
      _translate(() => _auth.resetPasswordForEmail(email));

  @override
  Future<void> verifyRecoveryCode(String email, String code) => _translate(
    () => _auth.verifyOTP(email: email, token: code, type: OtpType.recovery),
  );

  @override
  Future<void> verifySignupCode(String email, String code) => _translate(
    () => _auth.verifyOTP(email: email, token: code, type: OtpType.signup),
  );

  /// Sends an email sign-in code to the current user ("Magic Link" template,
  /// which must include `{{ .Token }}`). Not `reauthenticate()`: its code can
  /// only be checked by a password update, and that would re-key the sync.
  @override
  Future<void> sendEmailCode() => _translate(
    () => _auth.signInWithOtp(email: _currentEmail(), shouldCreateUser: false),
  );

  /// Verifies the sign-in code; on success Supabase renews the session of the
  /// same user.
  @override
  Future<void> verifyEmailCode(String code) => _translate(
    () => _auth.verifyOTP(
      email: _currentEmail(),
      token: code,
      type: OtpType.email,
    ),
  );

  /// Calls the `delete-account` Edge Function, which identifies the user by the
  /// session token Supabase attaches to the call.
  @override
  Future<void> deleteAccount() => _translate(() async {
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
    } on FunctionException {
      throw const AccountException(_deleteError);
    }
  });

  /// Email of the signed-in user; throws [AccountException] without one.
  String _currentEmail() =>
      _auth.currentUser?.email ??
      (throw const AccountException('Entra en tu cuenta primero.'));

  /// Runs [action], turning any Supabase or network failure into an
  /// [AccountException] with a Spanish message.
  Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthRetryableFetchException {
      throw const AccountException(_networkMessage);
    } on AuthException catch (e) {
      throw AccountException(_messageForCode(e.code));
    } on SocketException {
      throw const AccountException(_networkMessage);
    } on http.ClientException {
      throw const AccountException(_networkMessage);
    } on TimeoutException {
      throw const AccountException(_networkMessage);
    }
  }

  static const _deleteError =
      'No se ha podido borrar la cuenta. Inténtalo de nuevo.';

  static const _networkMessage =
      'No hay conexión con el servidor. Comprueba tu red e inténtalo de nuevo.';

  static String _messageForCode(String? code) => switch (code) {
    'invalid_credentials' => 'El email o la contraseña no son correctos.',
    'email_not_confirmed' =>
      'Falta confirmar el email. Abre el enlace que te hemos enviado.',
    'weak_password' =>
      'La contraseña es demasiado débil. Usa al menos 10 caracteres.',
    'otp_expired' ||
    'otp_disabled' => 'El código no es correcto o ha caducado.',
    'same_password' => 'La contraseña nueva debe ser distinta de la actual.',
    'user_already_exists' ||
    'email_exists' => 'Ya existe una cuenta con ese email.',
    'validation_failed' ||
    'email_address_invalid' => 'Ese email no parece válido.',
    'over_request_rate_limit' || 'over_email_send_rate_limit' =>
      'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
    _ => 'No se ha podido completar la operación con tu cuenta.',
  };
}
