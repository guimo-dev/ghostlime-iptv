import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/tv_device.dart';
import 'account_service.dart';
import 'auth_gateway.dart' show AccountException;
import 'google_device_dialog.dart';
import 'google_device_flow.dart';

/// Whether to offer "Continuar con Google" for [account]: on a TV only with
/// the TV client of the build ([googleTvConfigured]; the browser sign-in is
/// never offered there), elsewhere when the gateway supports it.
bool googleSignInOffered(AccountService account) =>
    isTvDevice ? googleTvConfigured : account.supportsGoogle;

/// "Continuar con Google": signs in with Google in the browser while a dialog
/// says to finish there, with "Cancelar" to give up; on a TV it opens the
/// code and QR dialog instead ([showGoogleDeviceDialog]), which shows its own
/// failures. Failures are left in the
/// account's `lastError`; with [showsError] the button also shows its own
/// failure below it, stretched to its parent's width (the welcome screen;
/// the account form shows `lastError` itself). [onSignedIn] runs when the
/// sign-in left a session open (signed in, or a state to settle in Ajustes →
/// Cuenta such as [AccountStatus.needsPassword]). [enabled] `false` disables
/// it, e.g. until the terms are accepted.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({
    super.key,
    required this.account,
    this.onSignedIn,
    this.enabled = true,
    this.showsError = false,
  });

  final AccountService account;
  final VoidCallback? onSignedIn;
  final bool enabled;
  final bool showsError;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _busy = false;

  /// The last failure of this button, shown with
  /// [GoogleSignInButton.showsError].
  String? _error;

  /// Shows the waiting dialog, signs in and closes the dialog when done.
  Future<void> _signIn() async {
    if (isTvDevice) return _signInOnTv();
    final account = widget.account;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    var waiting = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GoogleWaitDialog(onCancel: account.cancelGoogleSignIn),
      ).whenComplete(() => waiting = false),
    );
    try {
      await account.signInWithGoogle();
    } on AccountException catch (e) {
      _error = e.message;
    } finally {
      if (waiting) navigator.pop();
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        account.status != AccountStatus.signedOut &&
        account.status != AccountStatus.awaitingConfirmation) {
      widget.onSignedIn?.call();
    }
  }

  /// Signs in with the TV's code dialog, which shows its own failures.
  Future<void> _signInOnTv() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final signedIn = await showGoogleDeviceDialog(context, widget.account);
    if (!mounted) return;
    setState(() => _busy = false);
    if (signedIn) widget.onSignedIn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: widget.enabled && !_busy ? _signIn : null,
      child: const Text('Continuar con Google'),
    );
    final error = _error;
    if (!widget.showsError) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// "Continue in the browser" with a progress bar; [onCancel] gives up the
/// sign-in, which then closes this dialog.
class _GoogleWaitDialog extends StatelessWidget {
  const _GoogleWaitDialog({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Continúa en el navegador'),
        content: const SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              Text(
                'Hemos abierto el navegador para que entres con tu cuenta de '
                'Google. Cuando termines, vuelve aquí.',
              ),
              LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
