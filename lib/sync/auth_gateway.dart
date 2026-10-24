import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
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

  /// Whether [signInWithOAuthGoogle] works on this platform.
  bool get supportsGoogle;

  /// Signs in with Google in the system browser and returns once the session
  /// has started. Throws [AccountException] when the user cancels (see
  /// [cancelOAuthGoogle]), denies access or the sign-in fails.
  Future<void> signInWithOAuthGoogle();

  /// Gives up a pending [signInWithOAuthGoogle], which then throws; does
  /// nothing when none is pending.
  void cancelOAuthGoogle();

  /// The signed-in user's data key kept by the server (the `key-escrow` Edge
  /// Function), or `null` when it keeps none. Throws [AccountException].
  Future<Uint8List?> fetchEscrowedKey();

  /// Hands [key] to the server to keep as the user's data key. The server
  /// keeps only the first one, so when another device got there first this
  /// changes nothing: read the kept key back with [fetchEscrowedKey]. Throws
  /// [AccountException].
  Future<void> storeEscrowedKey(Uint8List key);
}

/// Where the browser sends the user back after signing in with Google. The
/// installer registers the `ghostlime` scheme for the app, and Supabase must
/// list this URL under Auth → URL Configuration → Redirect URLs.
const googleRedirectUrl = 'ghostlime://login-callback';

/// [AuthGateway] over Supabase Auth. Needs `Supabase.initialize` to have run.
class SupabaseAuthGateway implements AuthGateway {
  /// Listens to the auth events from the start, so the events replayed to a
  /// new listener (the stream keeps them all) arrive long before a Google
  /// sign-in waits for its own.
  SupabaseAuthGateway() {
    _auth.onAuthStateChange.listen(_onAuthState, onError: _onAuthError);
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// The Google sign-in waiting for the browser to come back, if any.
  Completer<void>? _pendingOAuth;

  /// How long a Google sign-in waits for the browser before giving up.
  static const _oauthTimeout = Duration(minutes: 5);

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
    } on Exception {
      // The emailed code is already spent, so network failures say the same.
      throw const AccountException(_deleteError);
    }
  });

  /// Google comes back through the `ghostlime` scheme, registered by the
  /// Windows installer; other platforms are not set up yet.
  @override
  bool get supportsGoogle => Platform.isWindows;

  /// Opens Google in the system browser (PKCE, the supabase_flutter default)
  /// and waits for [googleRedirectUrl]. supabase_flutter receives that link
  /// (app_links; the runner forwards it to the open window) and exchanges the
  /// code for the session, which arrives here as a `signedIn` event; a failed
  /// exchange arrives as a stream error.
  @override
  Future<void> signInWithOAuthGoogle() async {
    cancelOAuthGoogle();
    final pending = _pendingOAuth = Completer<void>();
    // A cancel can fail it before anyone awaits; the await below still sees
    // the error.
    pending.future.ignore();
    try {
      if (!await _launchGoogle()) {
        throw const AccountException(_browserError);
      }
      await pending.future.timeout(
        _oauthTimeout,
        onTimeout: () => throw const AccountException(_oauthTimeoutError),
      );
    } finally {
      if (identical(_pendingOAuth, pending)) _pendingOAuth = null;
    }
  }

  /// Opens the Google sign-in page; `false` when no browser could open it.
  Future<bool> _launchGoogle() async {
    try {
      return await _translate(
        () => _auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: googleRedirectUrl,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  @override
  void cancelOAuthGoogle() =>
      _finishOAuth(const AccountException(_oauthCancelledError));

  /// Ends the pending Google sign-in, if any: successfully, or with [error].
  void _finishOAuth([AccountException? error]) {
    final pending = _pendingOAuth;
    _pendingOAuth = null;
    if (pending == null || pending.isCompleted) return;
    if (error == null) {
      pending.complete();
    } else {
      pending.completeError(error);
    }
  }

  /// A new session ends the pending Google sign-in, if any. Sessions started
  /// otherwise (email, codes) arrive with none pending and change nothing.
  void _onAuthState(AuthState state) {
    if (state.event == AuthChangeEvent.signedIn && state.session != null) {
      _finishOAuth();
    }
  }

  /// The browser came back with an error (`access_denied` when the user
  /// said no) or the code could not be exchanged. Never logged.
  void _onAuthError(Object error) => _finishOAuth(
    AccountException(
      error is AuthException && error.code == 'access_denied'
          ? _oauthCancelledError
          : _oauthFailedError,
    ),
  );

  /// GET on the `key-escrow` Edge Function: `{key: base64}`, or 404 when the
  /// server keeps no key for this user.
  @override
  Future<Uint8List?> fetchEscrowedKey() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'key-escrow',
        method: HttpMethod.get,
      );
      final data = response.data as Map<String, dynamic>;
      return base64Decode(data['key'] as String);
    } on FunctionException catch (e) {
      if (e.status == 404) return null;
      throw const AccountException(_fetchEscrowError);
    }
  }

  /// PUT on the `key-escrow` Edge Function. 409 means the server already
  /// keeps a key (another device was first, or the account has a password):
  /// nothing changes, as the [AuthGateway] contract says.
  @override
  Future<void> storeEscrowedKey(Uint8List key) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'key-escrow',
        method: HttpMethod.put,
        body: {'key': base64Encode(key)},
      );
    } on FunctionException catch (e) {
      if (e.status == 409) return;
      throw const AccountException(_storeEscrowError);
    }
  }

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
      'No se ha podido borrar la cuenta. Pide un código nuevo con '
      '«Reenviar código» e inténtalo otra vez.';

  static const _browserError =
      'No se ha podido abrir el navegador para entrar con Google.';
  static const _oauthCancelledError = 'Se ha cancelado el acceso con Google.';
  static const _oauthFailedError =
      'No se ha podido entrar con Google. Inténtalo de nuevo.';
  static const _oauthTimeoutError =
      'Se ha agotado el tiempo para entrar con Google. Inténtalo de nuevo.';
  static const _fetchEscrowError =
      'No se ha podido recuperar tu clave de sincronización. '
      'Inténtalo de nuevo.';
  static const _storeEscrowError =
      'No se ha podido guardar tu clave de sincronización. '
      'Inténtalo de nuevo.';

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
