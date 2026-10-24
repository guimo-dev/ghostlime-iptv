import 'package:flutter/material.dart';

import 'account_service.dart';
import 'auth_gateway.dart' show AccountException;
import 'google_sign_in.dart';

/// What an account syncs and what forgetting the password means; shown next
/// to the [AccountForm].
const accountSyncExplanation =
    'Tus listas, favoritos, progreso y ajustes se sincronizan cifrados: el '
    'servidor no puede leerlos. Si olvidas la contraseña tendrás que empezar '
    'de cero en la nube.';

/// Email and password form to sign in or create an account, with password
/// recovery, the confirmation code of a new account and, where it works,
/// "Continuar con Google". Shared by Ajustes →
/// Cuenta and the welcome screen (inside a dialog, so its hints are inline
/// text, never SnackBars). Shows the [account]'s last error and a progress
/// bar while an action runs.
class AccountForm extends StatefulWidget {
  const AccountForm({super.key, required this.account, this.onSignedIn});

  final AccountService account;

  /// Called when an action of this form leaves a session open: signed in, or
  /// in a state still to settle in Ajustes → Cuenta
  /// ([AccountStatus.needsReset], [AccountStatus.chooseLocalData],
  /// [AccountStatus.needsPassword]).
  final VoidCallback? onSignedIn;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  /// What the user has to do before an action can run, e.g. type the email.
  String? _hint;

  AccountService get _account => widget.account;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Runs an account action with the buttons disabled. Failures are already in
  /// the service's `lastError`, which this form shows. Calls
  /// [AccountForm.onSignedIn] when the action left a session open.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _hint = null;
    });
    try {
      await action();
    } on AccountException {
      // Shown through AccountService.lastError.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final status = _account.status;
    if (mounted &&
        status != AccountStatus.signedOut &&
        status != AccountStatus.awaitingConfirmation) {
      widget.onSignedIn?.call();
    }
  }

  Future<void> _signIn() async {
    await _run(() => _account.signIn(_email.text.trim(), _password.text));
    if (mounted && _account.lastError == null) _password.clear();
  }

  Future<void> _signUp() async {
    final email = _email.text.trim();
    final password = _password.text;
    await _run(() => _account.signUp(email, password));
    if (!mounted || _account.lastError != null) return;
    if (_account.status == AccountStatus.awaitingConfirmation) {
      await _confirmSignUp(email, password);
    } else {
      _password.clear();
    }
  }

  /// Asks for the code of the confirmation email and finishes the sign-up.
  Future<void> _confirmSignUp(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      setState(
        () => _hint = 'Escribe tu email y tu contraseña en el formulario.',
      );
      return;
    }
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => PasswordDialog(
        title: 'Confirma tu email',
        message:
            'Te hemos enviado un correo con un código. Escríbelo aquí para '
            'terminar de crear la cuenta.',
        labels: const ['Código del correo'],
        plainFields: const {0},
        confirmLabel: 'Confirmar',
        validate: (values) =>
            values.first.trim().isEmpty ? 'Escribe el código.' : null,
      ),
    );
    if (values == null) return;
    await _run(
      () => _account.confirmSignUp(email, values.first.trim(), password),
    );
    if (mounted && _account.lastError == null) _password.clear();
  }

  /// Emails a reset code and asks for it with the new password.
  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _hint = 'Escribe tu email y vuelve a pulsar.');
      return;
    }
    await _run(() => _account.sendPasswordReset(email));
    if (!mounted || _account.lastError != null) return;
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => PasswordDialog(
        title: 'Restablecer contraseña',
        message:
            'Te hemos enviado un correo con un código. Escríbelo con tu '
            'contraseña nueva. Tus datos de la nube están cifrados con la '
            'contraseña anterior: si este dispositivo no los tenía ya '
            'abiertos, tendrás que empezar de cero en la nube (se te '
            'ofrecerá después, con un aviso).',
        labels: const ['Código del correo', 'Contraseña nueva', 'Repetir'],
        plainFields: const {0},
        confirmLabel: 'Restablecer',
        validate: (values) {
          if (values.any((v) => v.trim().isEmpty)) {
            return 'Rellena los tres campos.';
          }
          if (values[1].length < minPasswordLength) {
            return 'Usa al menos $minPasswordLength caracteres.';
          }
          if (values[1] != values[2]) return 'Las contraseñas no coinciden.';
          return null;
        },
      ),
    );
    if (values == null) return;
    await _run(
      () => _account.recoverPassword(email, values[0].trim(), values[1]),
    );
    if (mounted && _account.lastError == null) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => _busy ? null : _signIn(),
                  ),
                ),
                if (_account.status == AccountStatus.awaitingConfirmation)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _confirmSignUp(
                            _email.text.trim(),
                            _password.text,
                          ),
                    child: const Text('Introducir código'),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Entrar'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _signUp,
                  child: const Text('Crear cuenta'),
                ),
                if (_account.supportsGoogle)
                  GoogleSignInButton(
                    account: _account,
                    enabled: !_busy,
                    onSignedIn: widget.onSignedIn,
                  ),
                TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('¿Olvidaste la contraseña?'),
                ),
              ],
            ),
          ),
          for (final message in [?_hint, ?_account.lastError])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

/// Dialog with one hidden-text field per label. Returns the typed values, or
/// `null` when cancelled; [validate] returns an error to show instead of
/// closing.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.confirmLabel,
    required this.validate,
    this.message,
    this.plainFields = const {},
  });

  final String title;
  final String? message;

  /// Indexes of the fields shown as plain text (not passwords).
  final Set<int> plainFields;
  final List<String> labels;
  final String confirmLabel;
  final String? Function(List<String> values) validate;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  late final _controllers = [
    for (final _ in widget.labels) TextEditingController(),
  ];
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = [for (final c in _controllers) c.text];
    final error = widget.validate(values);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.pop(context, values);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 16),
            ],
            for (var i = 0; i < _controllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[i],
                  obscureText: !widget.plainFields.contains(i),
                  autofocus: i == 0,
                  decoration: InputDecoration(labelText: widget.labels[i]),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
