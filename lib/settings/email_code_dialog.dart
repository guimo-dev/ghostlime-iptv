import 'package:flutter/material.dart';

import '../sync/auth_gateway.dart' show AccountException;
import '../tv/tv_text_input.dart';
import '../ui/tv_device.dart';

/// Asks for the code emailed to the account (the caller already sent it).
/// [onSubmit] checks the code without closing the dialog, so a mistyped code
/// can be corrected; an [AccountException] from it (or from [onResend]) is
/// shown inside. "Reenviar código" calls [onResend]. [extra] is shown under
/// the code field. Closes with `true` once [onSubmit] succeeds, `null` when
/// cancelled.
class EmailCodeDialog extends StatefulWidget {
  const EmailCodeDialog({
    super.key,
    required this.title,
    required this.email,
    required this.purpose,
    required this.confirmLabel,
    required this.onSubmit,
    required this.onResend,
    this.extra,
  });

  final String title;

  /// Where the code was sent; `null` leaves the address out of the text.
  final String? email;

  /// Ends the sentence "Escríbelo aquí …", e.g. "para crear un PIN nuevo.".
  final String purpose;

  final String confirmLabel;
  final Future<void> Function(String code) onSubmit;
  final Future<void> Function() onResend;
  final Widget? extra;

  @override
  State<EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<EmailCodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Confirmation shown after a code was sent again.
  String? _notice;

  /// The confirm button: on a TV "Hecho" in the code goes there.
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _confirmFocus.dispose();
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
      await widget.onSubmit(code);
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _resend() => _run(() async {
    await widget.onResend();
    if (mounted) setState(() => _notice = 'Te hemos enviado otro código.');
  });

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final to = email == null ? '' : ' a $email';
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Te hemos enviado un correo$to con un código. Escríbelo aquí '
              '${widget.purpose}',
            ),
            const SizedBox(height: 16),
            TvKeyboardGate(
              builder: (context, locked) => TextField(
                readOnly: locked,
                controller: _code,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Código del correo',
                ),
                // On a TV "Hecho" goes to the confirm button, pressed with OK.
                onSubmitted: (_) => isTvDevice
                    ? _confirmFocus.requestFocus()
                    : _busy
                    ? null
                    : _submit(),
              ),
            ),
            if (widget.extra != null) widget.extra!,
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
          focusNode: _confirmFocus,
          onPressed: _busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
