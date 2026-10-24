import 'package:flutter/material.dart';

import '../sync/account_service.dart';
import '../sync/auth_gateway.dart' show AccountException;
import 'pin_store.dart';

/// What the PIN dialog returns for "¿Olvidaste el PIN?"; never a valid PIN.
const _forgotPin = 'forgot';

/// Asks for a 4-digit PIN. With [confirm], asks twice and checks both match.
/// Returns the PIN, or `null` when cancelled.
Future<String?> askPin(
  BuildContext context, {
  required String title,
  bool confirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: title, confirm: confirm),
  );
}

/// Asks for the current PIN and checks it. Returns whether it matched.
///
/// With a signed-in [account] the dialog also offers "¿Olvidaste el PIN?",
/// which emails a code to the account and, when the code is right, asks for a
/// new PIN. That path returns `false`: the action that asked for the PIN is
/// not done, and the parental control stays on.
Future<bool> verifyPin(
  BuildContext context,
  PinStore store, {
  AccountService? account,
}) async {
  final canReset = account?.status == AccountStatus.signedIn;
  final pin = await showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(
      title: 'Introduce el PIN',
      confirm: false,
      canReset: canReset,
    ),
  );
  if (pin == null || !context.mounted) return false;
  if (pin == _forgotPin) {
    await _resetForgottenPin(context, store, account!);
    return false;
  }
  final ok = await store.verify(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
  }
  return ok;
}

/// Emails a code to [account], asks for it and, if it is right, stores a new
/// PIN in [store]. A failed first send is shown as a snack bar; code errors
/// show inside the code dialog. The code is not kept.
Future<void> _resetForgottenPin(
  BuildContext context,
  PinStore store,
  AccountService account,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
  try {
    await account.sendPinResetCode();
  } on AccountException catch (e) {
    say(e.message);
    return;
  }
  if (!context.mounted) return;
  final verified = await showDialog<bool>(
    context: context,
    builder: (_) => _CodeDialog(account: account),
  );
  if (verified != true || !context.mounted) return;
  final pin = await askPin(context, title: 'Crea un PIN nuevo', confirm: true);
  if (pin == null) return;
  await store.setPin(pin);
  say('PIN cambiado.');
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.title,
    required this.confirm,
    this.canReset = false,
  });

  final String title;
  final bool confirm;

  /// Whether to offer "¿Olvidaste el PIN?" (closes with [_forgotPin]).
  final bool canReset;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _first.text;
    if (!isValidPin(pin)) {
      setState(() => _error = 'El PIN son 4 números.');
      return;
    }
    if (widget.confirm && pin != _second.text) {
      setState(() => _error = 'Los PIN no coinciden.');
      return;
    }
    Navigator.pop(context, pin);
  }

  Widget _field(TextEditingController controller, String label, bool focus) {
    return TextField(
      controller: controller,
      autofocus: focus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onSubmitted: (_) => _submit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_first, 'PIN', true),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              _field(_second, 'Repite el PIN', false),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () => Navigator.pop(context, _forgotPin),
            child: const Text('¿Olvidaste el PIN?'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Aceptar')),
      ],
    );
  }
}

/// Asks for the code emailed to reset the PIN and checks it with [account]
/// without closing, so a mistyped code can be corrected; "Reenviar código"
/// emails a new one. Returns `true` once a code is accepted, `null` when
/// cancelled.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.account});

  final AccountService account;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Confirmation shown after a code was sent again.
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Runs [action] with the buttons disabled; an [AccountException] (wrong
  /// code, rate limit, network) is shown in the dialog.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Escribe el código.');
      return;
    }
    await _run(() async {
      await widget.account.verifyPinResetCode(code);
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _resend() => _run(() async {
    await widget.account.sendPinResetCode();
    if (mounted) setState(() => _notice = 'Te hemos enviado otro código.');
  });

  @override
  Widget build(BuildContext context) {
    final email = widget.account.email;
    final to = email == null ? '' : ' a $email';
    return AlertDialog(
      title: const Text('Recuperar el PIN'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Te hemos enviado un correo$to con un código. Escríbelo aquí '
              'para crear un PIN nuevo.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Código del correo'),
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            if (_error != null || _notice != null) ...[
              const SizedBox(height: 12),
              Text(
                _error ?? _notice!,
                style: _error == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Reenviar código'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Comprobar'),
        ),
      ],
    );
  }
}
