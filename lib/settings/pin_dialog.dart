import 'package:flutter/material.dart';

import '../sync/account_service.dart';
import '../sync/auth_gateway.dart' show AccountException;
import '../tv/tv_text_input.dart';
import '../ui/tv_device.dart';
import 'email_code_dialog.dart';
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
    builder: (_) => EmailCodeDialog(
      title: 'Recuperar el PIN',
      email: account.email,
      purpose: 'para crear un PIN nuevo.',
      confirmLabel: 'Comprobar',
      onSubmit: account.verifyPinResetCode,
      onResend: account.sendPinResetCode,
    ),
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

  /// Aceptar: on a TV "Hecho" in the last PIN goes there.
  final _acceptFocus = FocusNode();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _acceptFocus.dispose();
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

  /// A PIN field; [last] is whether no other PIN field follows it.
  /// Elsewhere Enter submits; on a TV "Siguiente" goes to the second PIN and
  /// "Hecho" in the last one to Aceptar.
  Widget _field(
    TextEditingController controller,
    String label, {
    required bool focus,
    required bool last,
  }) {
    return TvKeyboardGate(
      builder: (context, locked) => TextField(
        readOnly: locked,
        controller: controller,
        autofocus: focus,
        obscureText: true,
        keyboardType: TextInputType.number,
        textInputAction: isTvDevice && !last ? TextInputAction.next : null,
        maxLength: 4,
        decoration: InputDecoration(labelText: label, counterText: ''),
        onSubmitted: !isTvDevice
            ? (_) => _submit()
            : last
            ? (_) => _acceptFocus.requestFocus()
            : null,
      ),
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
            _field(_first, 'PIN', focus: true, last: !widget.confirm),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              _field(_second, 'Repite el PIN', focus: false, last: true),
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
        FilledButton(
          focusNode: _acceptFocus,
          onPressed: _submit,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
