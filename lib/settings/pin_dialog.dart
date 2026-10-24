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
/// PIN in [store]. Failures are shown as snack bars; the code is not kept.
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
  final code = await showDialog<String>(
    context: context,
    builder: (_) => _CodeDialog(email: account.email),
  );
  if (code == null) return;
  try {
    await account.verifyPinResetCode(code);
  } on AccountException catch (e) {
    say(e.message);
    return;
  }
  if (!context.mounted) return;
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

/// Asks for the code emailed to reset the PIN. Returns it trimmed, or `null`
/// when cancelled.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.email});

  /// Where the code was sent, when known.
  final String? email;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Escribe el código.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.email == null ? '' : ' a ${widget.email}';
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
              onSubmitted: (_) => _submit(),
            ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Comprobar')),
      ],
    );
  }
}
